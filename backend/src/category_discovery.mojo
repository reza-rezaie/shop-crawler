# Native Mojo category-discovery crawl: walk a site's category-hub
# structure (the same same-host, path-nested "child link" heuristic
# product-extraction's drill-down uses -- see textutil.is_child_path) and
# persist it as a tree, independent of and cheaper than a product crawl.
# No product extraction that persists product rows, and no detail-page
# description fetches: the only extraction work done here is a throwaway
# existence check (does this page's own HTML show any product-card
# markup) used purely to record the has_own_products signal at no extra
# fetch cost. Live-testing against azurestandard.com -- the SPA reference
# site product-extraction's own drill-down was built and verified against
# -- found its raw HTML has no category links *at all* (a 73KB Angular
# shell with 26 unrelated hrefs); its real navigation only exists after
# client-side JS runs. So, like product-extraction, discovery DOES fall
# back to rendering a page with a headless browser, but only when it
# looks like an SPA shell AND its raw HTML yielded zero candidate links
# (see looks_like_client_rendered_app below) -- keyed off "no links"
# instead of product-extraction's "no products", same cost guard (a page
# whose raw HTML already has usable links never pays for a render).
#
# The per-page decision logic (decide_discovery_page) and the
# budget-cutoff bookkeeping (pending_after_budget) are pulled out as
# plain, no-I/O functions -- like html_extract.find_child_links is a pure
# piece crawler.mojo's own fetch loop calls -- so they're unit-testable
# without a live network fetch, which discover_categories' actual queue
# loop below necessarily needs (same reason crawler.mojo's own loop has
# no direct unit test, only its extraction/detection pieces do).
#
# See openspec/changes/add-category-discovery-crawl/design.md for why
# this is a separate module rather than a mode flag on crawler.mojo, and
# for how not-found pages and the has_own_products tri-state interact:
# a candidate child link is only ever upserted once its own content is
# confirmed to not be a not-found page (checked when it's fetched), or --
# for a link the budget never reached -- flushed at the end of the run
# with has_own_products left unknown, since a URL never fetched can't be
# a confirmed 404 but also can't have a known product-presence signal.

from std.python import Python, PythonObject
from core.http_client import fetch, can_fetch, resolve_url, rate_limit_sleep
from core.browser_client import render_fetch
from html_extract import (
    extract_json_ld_products,
    extract_heuristic_products,
    looks_like_not_found_page,
    looks_like_client_rendered_app,
    find_next_page_url,
)
from core.text_utils import is_child_path, find_all_anchor_hrefs_with_text, extract_host, url_path
from core.database import upsert_site_category

comptime MAX_DISCOVERY_PAGES_DEFAULT = 25
comptime MAX_DISCOVERY_PAGES_HARD_CAP = 200
comptime MAX_DISCOVERY_CHILDREN_PER_HUB = 20


struct DiscoveryQueueEntry(Copyable, Movable):
    """One page to visit during discovery, with the context it was
    discovered under (its parent page's URL, and the name its anchor was
    linked with -- or a URL-derived fallback)."""
    var url: String
    var parent_url: String
    var name: String

    def __init__(out self, url: String, parent_url: String, name: String):
        self.url = url
        self.parent_url = parent_url
        self.name = name


struct DiscoveryPageDecision(Copyable, Movable):
    """What decide_discovery_page concluded about one already-fetched
    page: whether it's a not-found page (in which case it's never
    upserted and `children`/`has_own_products` are unused), and -- for a
    confirmed real page -- whether it shows its own products plus the
    further child pages it links to."""
    var is_not_found: Bool
    var has_own_products: Bool
    var children: List[DiscoveryQueueEntry]

    def __init__(out self, is_not_found: Bool, has_own_products: Bool, var children: List[DiscoveryQueueEntry]):
        self.is_not_found = is_not_found
        self.has_own_products = has_own_products
        self.children = children^


def name_from_url(url: String) raises -> String:
    """Fallback category name when an anchor has no visible text: the
    URL's last path segment, or the host if the path is bare."""
    var path = url_path(url)
    var p = path
    if p.byte_length() > 1 and p[byte = p.byte_length() - 1 : p.byte_length()] == "/":
        var trimmed = String(p[byte = 0 : p.byte_length() - 1])
        p = trimmed
    var last_slash = p.rfind("/")
    var segment = p
    if last_slash != -1:
        segment = String(p[byte = last_slash + 1 : p.byte_length()])
    if segment.byte_length() == 0:
        return extract_host(url)
    return segment


def _strip_fragment(url: String) raises -> String:
    """Drop a trailing `#fragment` -- it never causes a different page
    load (is_child_path's own path comparison already ignores it, via
    textutil.url_path), so a same-page anchor link like `...#reviews`
    must not be recorded as a distinct child category node from the
    plain page it points at."""
    var idx = url.find("#")
    if idx == -1:
        return url
    return String(url[byte = 0 : idx])


def _has_any_products(html: String, url: String) raises -> Bool:
    """Cheap product-presence check reusing the same two extraction
    strategies product crawl uses, discarding the results -- see
    design.md's "Reuse full extraction functions" decision."""
    if len(extract_json_ld_products(html, url)) > 0:
        return True
    return len(extract_heuristic_products(html, url, String(""))) > 0


def decide_discovery_page(
    html: String,
    url: String,
    parent_url: String,
) raises -> DiscoveryPageDecision:
    """Given one already-fetched page's HTML, decide whether it's a
    not-found page and, if not, its own product-presence signal and the
    further same-host, path-nested child links it points to (deduplicated
    within this page, capped at MAX_DISCOVERY_CHILDREN_PER_HUB).

    Excludes whatever find_next_page_url identifies as this page's own
    same-listing pagination target: a path-nested "next page" link (e.g.
    a sibling `page-2.html` next to `page-1.html`/`index.html`) satisfies
    the same path-nesting rule a genuine subcategory does, and would
    otherwise show up as a bogus child category node named "next"/
    "previous". This is a best-effort filter, not a complete one -- see
    design.md's "Pagination noise" risk: a page reached *only* via a
    "previous" link back to a URL distinct from the one being paginated
    forward from can still slip through."""
    if looks_like_not_found_page(html):
        return DiscoveryPageDecision(True, False, List[DiscoveryQueueEntry]())

    var has_products = _has_any_products(html, url)

    var next_page_url = String("")
    var next_page_opt = find_next_page_url(html, url)
    if next_page_opt:
        next_page_url = next_page_opt.value()

    var children = List[DiscoveryQueueEntry]()
    var seen_on_page = Dict[String, Bool]()
    var links = find_all_anchor_hrefs_with_text(html)
    for link in links:
        if len(children) >= MAX_DISCOVERY_CHILDREN_PER_HUB:
            break
        var resolved = _strip_fragment(resolve_url(url, link.href))
        if resolved in seen_on_page:
            continue
        seen_on_page[resolved] = True
        if next_page_url.byte_length() > 0 and resolved == next_page_url:
            continue
        if not is_child_path(resolved, url):
            continue
        var child_name = link.text
        if child_name.byte_length() == 0:
            child_name = name_from_url(resolved)
        children.append(DiscoveryQueueEntry(resolved, url, child_name))

    return DiscoveryPageDecision(False, has_products, children^)


def pending_after_budget(
    queue: List[DiscoveryQueueEntry],
    start: Int,
    visited: Dict[String, Bool],
) -> List[DiscoveryQueueEntry]:
    """Entries from `start` onward that were queued (discovered as a
    child link) but never dequeued/fetched -- because the page budget ran
    out first. These still get recorded (with an unknown has_own_products
    signal), just not traversed further this run."""
    var out = List[DiscoveryQueueEntry]()
    var i = start
    while i < len(queue):
        var entry = queue[i].copy()
        i += 1
        if entry.url in visited:
            continue
        out.append(entry^)
    return out^


def discover_categories(
    conn: PythonObject,
    seed_url: String,
    max_pages: Int,
    progress: PythonObject,
) raises -> PythonObject:
    # See crawler.crawl's docstring for what `progress` is and why a
    # mutable dict rather than a callback.
    var errors = Python.list()
    var notes = Python.list()

    var capped_pages = max_pages
    if capped_pages < 1:
        capped_pages = MAX_DISCOVERY_PAGES_DEFAULT
    if capped_pages > MAX_DISCOVERY_PAGES_HARD_CAP:
        capped_pages = MAX_DISCOVERY_PAGES_HARD_CAP

    if progress is not None:
        progress["phase"] = "pages"
        progress["pages_visited"] = 0
        progress["pages_total"] = capped_pages
        progress["categories_found"] = 0

    if not can_fetch(seed_url):
        errors.append("Discovery of this URL is disallowed by the site's robots.txt")
        return _summary(seed_url, 0, 0, 0, errors, notes)

    var visited = Dict[String, Bool]()
    var queued_urls = Dict[String, Bool]()

    var queue = List[DiscoveryQueueEntry]()
    queue.append(DiscoveryQueueEntry(seed_url, String(""), name_from_url(seed_url)))
    queued_urls[seed_url] = True
    var queue_pos = 0
    var pages_visited = 0
    var categories_found = 0
    var categories_updated = 0

    while queue_pos < len(queue) and pages_visited < capped_pages:
        var entry = queue[queue_pos].copy()
        queue_pos += 1

        if entry.url in visited:
            continue
        visited[entry.url] = True

        var result = fetch(entry.url)
        pages_visited += 1
        if progress is not None:
            progress["pages_visited"] = pages_visited
        if not result.ok:
            errors.append("Failed to fetch " + entry.url + ": " + result.error)
        else:
            var decision = decide_discovery_page(result.body, entry.url, entry.parent_url)

            if not decision.is_not_found and len(decision.children) == 0 and looks_like_client_rendered_app(result.body, 0):
                var rendered = render_fetch(entry.url)
                if not rendered.ok:
                    notes.append(
                        entry.url
                        + " found no candidate category links and looks like it needs"
                        + " JavaScript rendering, but rendering it failed: "
                        + rendered.error
                    )
                else:
                    var rendered_decision = decide_discovery_page(rendered.body, entry.url, entry.parent_url)
                    if not rendered_decision.is_not_found:
                        if len(rendered_decision.children) > 0:
                            notes.append(
                                entry.url
                                + ": found "
                                + String(len(rendered_decision.children))
                                + " candidate subcategory link(s) by rendering the page with a"
                                + " headless browser (its raw HTML has no usable navigation"
                                + " links on its own)."
                            )
                        else:
                            notes.append(
                                entry.url
                                + " found no candidate category links, even after rendering it"
                                + " with a headless browser."
                            )
                    decision = rendered_decision^

            if decision.is_not_found:
                notes.append(
                    entry.url
                    + " does not appear to be a real page on this site (its content looks"
                    + " like a \"not found\" / 404 page), so it was not recorded or"
                    + " traversed further."
                )
            else:
                var outcome = upsert_site_category(
                    conn,
                    entry.url,
                    entry.name,
                    entry.parent_url,
                    extract_host(entry.url),
                    Optional[Bool](decision.has_own_products),
                )
                if outcome.created:
                    categories_found += 1
                else:
                    categories_updated += 1
                if progress is not None:
                    progress["categories_found"] = categories_found + categories_updated

                for child in decision.children:
                    if child.url not in queued_urls:
                        queued_urls[child.url] = True
                        queue.append(child.copy())

        if pages_visited < capped_pages:
            rate_limit_sleep()

    for leftover in pending_after_budget(queue, queue_pos, visited):
        visited[leftover.url] = True
        var outcome = upsert_site_category(
            conn,
            leftover.url,
            leftover.name,
            leftover.parent_url,
            extract_host(leftover.url),
            None,
        )
        if outcome.created:
            categories_found += 1
        else:
            categories_updated += 1

    return _summary(seed_url, pages_visited, categories_found, categories_updated, errors, notes)


def _summary(
    seed_url: String,
    pages_visited: Int,
    categories_found: Int,
    categories_updated: Int,
    errors: PythonObject,
    notes: PythonObject,
) raises -> PythonObject:
    var summary = Python.dict()
    summary["seed_url"] = seed_url
    summary["pages_visited"] = pages_visited
    summary["categories_found"] = categories_found
    summary["categories_updated"] = categories_updated
    summary["errors"] = errors
    summary["notes"] = notes
    return summary
