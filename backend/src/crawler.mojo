# Native Mojo crawl orchestration: fetch -> extract -> discover more pages
# -> (optionally) fetch descriptions -> upsert. This is the one place that
# ties together http_client.mojo, html_extract.mojo, pricing.mojo (via
# html_extract), browser_client.mojo, and db.mojo. The only Python interop
# used directly here is building the summary as a Python dict (so api.mojo
# can hand it straight back to the HTTP layer).
#
# "More pages" comes from two sources, treated uniformly as one work queue:
# same-listing pagination (a page that had products, following its
# `<link rel="next">`-style link), and category "drill-down" (a page that
# had *no* products of its own, following same-host links nested under its
# own URL path -- see html_extract.find_child_links). Both count against
# the same overall `max_pages` budget. See openspec/changes/archive/
# ...-add-category-drill-down-crawling/ for why this replaced a simpler
# linear pagination-only walk.

from std.python import Python, PythonObject
from core.models import Product
from core.http_client import fetch, can_fetch, resolve_url, rate_limit_sleep
from core.browser_client import render_fetch
from html_extract import (
    extract_json_ld_products,
    extract_heuristic_products,
    find_next_page_url,
    extract_breadcrumb_category,
    extract_last_breadcrumb_items,
    extract_product_description,
    looks_like_client_rendered_app,
    looks_like_not_found_page,
    find_child_links,
)
from core.database import upsert_product

comptime MAX_PAGES_DEFAULT = 3
comptime MAX_PAGES_HARD_CAP = 500
comptime MAX_DETAIL_FETCHES_DEFAULT = 60
comptime MAX_CHILD_LINKS_PER_HUB_PAGE = 8


def crawl(
    conn: PythonObject,
    seed_url: String,
    max_pages: Int,
    max_detail_fetches: Int,
    fetch_descriptions: Bool,
    progress: PythonObject,
) raises -> PythonObject:
    # `progress`, when not Python None, is a mutable Python dict the HTTP
    # layer (server.py) also holds a reference to -- writing into it here
    # is how a concurrent GET /api/progress request on another thread sees
    # this crawl's live state. See api.mojo/server.py for how it's wired
    # up; this function works the same (just silently skips reporting)
    # when called with Python None (e.g. `pixi run crawl`'s one-shot path).
    var errors = Python.list()
    var notes = Python.list()

    var capped_pages = max_pages
    if capped_pages < 1:
        capped_pages = MAX_PAGES_DEFAULT
    if capped_pages > MAX_PAGES_HARD_CAP:
        capped_pages = MAX_PAGES_HARD_CAP

    var capped_detail_fetches = max_detail_fetches
    if capped_detail_fetches < 0:
        capped_detail_fetches = MAX_DETAIL_FETCHES_DEFAULT

    if progress is not None:
        progress["phase"] = "pages"
        progress["pages_visited"] = 0
        progress["pages_total"] = capped_pages
        progress["products_found"] = 0
        progress["detail_index"] = 0
        progress["detail_total"] = 0

    if not can_fetch(seed_url):
        errors.append("Crawling this URL is disallowed by the site's robots.txt")
        return _summary(seed_url, 0, 0, 0, 0, errors, notes)

    var seen_product_urls = Dict[String, Bool]()
    var visited_pages = Dict[String, Bool]()
    var pending_products = List[Product]()

    var queue = List[String]()
    queue.append(seed_url)
    var queue_pos = 0
    var pages_crawled = 0

    while queue_pos < len(queue) and pages_crawled < capped_pages:
        var current_url = queue[queue_pos]
        queue_pos += 1

        if current_url in visited_pages:
            continue
        visited_pages[current_url] = True

        var result = fetch(current_url)
        pages_crawled += 1
        if progress is not None:
            progress["pages_visited"] = pages_crawled
        if not result.ok:
            errors.append("Failed to fetch " + current_url + ": " + result.error)
            continue

        var page_category = extract_breadcrumb_category(result.body)

        var products = extract_json_ld_products(result.body, current_url)
        if len(products) == 0:
            products = extract_heuristic_products(result.body, current_url, page_category)

        # Pagination and child-link discovery are normally done from the
        # raw HTML; if the JS-rendering fallback below runs, its rendered
        # HTML (a strict superset of the raw HTML's content, plus whatever
        # JS added) replaces it for both.
        var pagination_source = result.body
        var attempted_rendering = False

        if looks_like_client_rendered_app(result.body, len(products)):
            attempted_rendering = True
            var rendered = render_fetch(current_url)
            if not rendered.ok:
                notes.append(
                    current_url
                    + " found no product markup and looks like it needs JavaScript"
                    + " rendering, but rendering it failed: "
                    + rendered.error
                )
            else:
                pagination_source = rendered.body

                var rendered_category = extract_breadcrumb_category(rendered.body)
                if rendered_category.byte_length() > 0:
                    page_category = rendered_category

                var rendered_products = extract_json_ld_products(rendered.body, current_url)
                if len(rendered_products) == 0:
                    rendered_products = extract_heuristic_products(rendered.body, current_url, page_category)

                if len(rendered_products) > 0:
                    notes.append(
                        current_url
                        + ": found "
                        + String(len(rendered_products))
                        + " product(s) by rendering the page with a headless browser"
                        + " (its raw HTML has no product markup on its own)."
                    )
                    products = rendered_products^

        for p in products:
            var abs_url = resolve_url(current_url, p.url)
            if abs_url in seen_product_urls:
                continue
            seen_product_urls[abs_url] = True
            var product = p.copy()
            product.url = abs_url
            if product.image_url.byte_length() > 0:
                product.image_url = resolve_url(current_url, product.image_url)
            pending_products.append(product^)

        if progress is not None:
            progress["products_found"] = len(pending_products)

        if len(products) == 0 and looks_like_not_found_page(pagination_source):
            notes.append(
                current_url
                + " does not appear to be a real page on this site (its content looks"
                + " like a \"not found\" / 404 page), so it was not crawled further."
            )
        else:
            if len(products) > 0:
                var next_url_opt = find_next_page_url(pagination_source, current_url)
                if next_url_opt:
                    var next_url = next_url_opt.value()
                    if next_url != current_url:
                        queue.append(next_url)
            elif attempted_rendering:
                notes.append(
                    current_url
                    + " found no product markup, even after rendering it with a"
                    + " headless browser. It may need interaction (e.g. scrolling"
                    + " or clicking) beyond basic rendering, or use a structure"
                    + " this crawler's heuristics don't recognize."
                )

            # Look for narrower category links regardless of whether this
            # page also had products of its own -- a real category page
            # commonly shows some products *and* links to subcategories on
            # the same page (e.g. a department's top-level page), and a
            # crawl aimed at that page should still reach everything
            # beneath it, not just what's shown at this level.
            var children = find_child_links(pagination_source, current_url, MAX_CHILD_LINKS_PER_HUB_PAGE)
            if len(children) > 0:
                notes.append(
                    current_url
                    + " links to "
                    + String(len(children))
                    + " narrower category page(s); following them."
                )
                for child_url in children:
                    queue.append(child_url)

        if pages_crawled < capped_pages:
            rate_limit_sleep()

    var created = 0
    var updated = 0
    var detail_fetches = 0

    if progress is not None and len(pending_products) > 0:
        progress["phase"] = "details"
        progress["detail_total"] = len(pending_products)

    var i = 0
    while i < len(pending_products):
        if progress is not None:
            progress["detail_index"] = i + 1

        if fetch_descriptions and detail_fetches < capped_detail_fetches:
            var detail = fetch(pending_products[i].url)
            detail_fetches += 1
            rate_limit_sleep()
            if detail.ok:
                var desc = extract_product_description(detail.body)
                if desc.byte_length() > 0:
                    pending_products[i].description = desc
                var crumbs = extract_last_breadcrumb_items(detail.body, 2)
                if len(crumbs) >= 2:
                    pending_products[i].category = crumbs[0]
            else:
                errors.append("Failed to fetch product detail " + pending_products[i].url + ": " + detail.error)

        var outcome = upsert_product(conn, pending_products[i])
        if outcome.created:
            created += 1
        else:
            updated += 1
        i += 1

    return _summary(seed_url, pages_crawled, len(pending_products), created, updated, errors, notes)


def _summary(
    seed_url: String,
    pages_crawled: Int,
    products_found: Int,
    products_created: Int,
    products_updated: Int,
    errors: PythonObject,
    notes: PythonObject,
) raises -> PythonObject:
    var summary = Python.dict()
    summary["seed_url"] = seed_url
    summary["pages_crawled"] = pages_crawled
    summary["products_found"] = products_found
    summary["products_created"] = products_created
    summary["products_updated"] = products_updated
    summary["errors"] = errors
    summary["notes"] = notes
    return summary
