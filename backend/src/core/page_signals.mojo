# Generic listing-page signals shared by more than one module: "does this
# page have a next page", "does this page look like a client-rendered app
# shell that yielded zero products for that reason, not because it has
# none", "is this actually a 404 rather than a legitimately-empty page",
# and "what same-host child links does this page have". None of these are
# product-extraction logic -- crawler.mojo (product_extraction) and
# category_discovery's discovery.mojo both need them to decide what a fetched page
# means, which is why they live in core/ rather than under
# modules/product_extraction/. Split out of the former html_extract.mojo
# -- see openspec/changes/chg-0001-2026-08-21-modular-monolith-vertical-slice/
# design.md, Decision 4.

from std.python import Python
from core.http_client import resolve_url
from core.text_utils import (
    extract_attr,
    extract_blocks_by_class_hint,
    extract_first_tag_block,
    find_tag_open,
    clean_text,
    contains_ci,
    inner_text_of_first,
    find_all_anchor_hrefs,
    is_child_path,
)


def find_next_page_url(html: String, current_url: String) raises -> Optional[String]:
    """Find a pagination "next" link: <link rel="next"> in <head>, or any
    element whose class contains "next" with a nested href, resolved to an
    absolute URL relative to `current_url`."""
    var urlparse = Python.import_module("urllib.parse")

    # <link rel="next"> has no class, so scan <link> tags directly rather
    # than via extract_blocks_by_class_hint (which requires a class match).
    var pos = 0
    while True:
        var open_idx = find_tag_open(html, "link", pos)
        if open_idx == -1:
            break
        var open_end = html.find(">", open_idx)
        if open_end == -1:
            break
        var tag_text = String(html[byte = open_idx : open_end + 1])
        var rel = extract_attr(tag_text, "rel")
        if rel and String(rel.value()) == "next":
            var href = extract_attr(tag_text, "href")
            if href:
                var resolved = String(urlparse.urljoin(current_url, href.value()))
                return Optional[String](resolved)
        pos = open_end + 1

    var next_blocks = extract_blocks_by_class_hint(html, "a", String("next"))
    if len(next_blocks) == 0:
        next_blocks = extract_blocks_by_class_hint(html, "li", String("next"))
    for candidate in next_blocks:
        var a_block = extract_first_tag_block(candidate, "a")
        var target = candidate
        if a_block:
            target = a_block.value()
        var open_end2 = target.find(">")
        if open_end2 == -1:
            continue
        var tag_text2 = String(target[byte = 0 : open_end2 + 1])
        var href2 = extract_attr(tag_text2, "href")
        if href2:
            var resolved2 = String(urlparse.urljoin(current_url, href2.value()))
            if resolved2 != current_url:
                return Optional[String](resolved2)

    return None


def _spa_shell_markers() -> List[String]:
    var markers = List[String]()
    markers.append(String("ng-app="))
    markers.append(String("data-reactroot"))
    markers.append(String('id="root"'))
    markers.append(String('id="__next"'))
    markers.append(String("data-v-app"))
    return markers^


def looks_like_client_rendered_app(html: String, product_count: Int) -> Bool:
    """Heuristic: a page whose raw HTML carries a common client-side
    framework's app-shell marker (Angular, React, Next.js, Vue) AND for
    which extraction found zero products is likely rendering its real
    content via JavaScript this crawler never executes -- rather than
    the page genuinely having no products. Only meaningful when
    `product_count` is 0; a page with real static product markup plus an
    unrelated framework marker elsewhere is not flagged."""
    if product_count > 0:
        return False
    var markers = _spa_shell_markers()
    for marker in markers:
        if marker in html:
            return True
    return False


def looks_like_not_found_page(html: String) raises -> Bool:
    """Whether the page's own content is a "not found"/404 page -- as
    opposed to a real page that legitimately has no products (e.g. an
    empty category). Checked via the page's first heading (h1, then h2)
    mentioning "not found" or "404" and being short (an error page's
    heading is a phrase, not a long product/category title that happens
    to contain those words). A heuristic, not a guarantee: only ever
    consulted after extraction already found zero products, and only
    ever adds a note -- it never suppresses real results (see
    openspec/changes/archive/...-add-category-drill-down-crawling/)."""
    var heading_tags = List[String]()
    heading_tags.append(String("h1"))
    heading_tags.append(String("h2"))
    for tag in heading_tags:
        var inner = inner_text_of_first(html, tag)
        if inner:
            var text = clean_text(inner.value())
            if text.byte_length() > 0 and text.byte_length() <= 40:
                if contains_ci(text, "not found") or contains_ci(text, "404"):
                    return True
    return False


def find_child_links(html: String, current_url: String, limit: Int) raises -> List[String]:
    """Same-host links on `html` whose URL path is nested under
    `current_url`'s own path (see text_utils.is_child_path) -- candidate
    "drill down" pages for a category hub that lists no products of its
    own. Deduplicated, capped at `limit`."""
    var results = List[String]()
    var seen = Dict[String, Bool]()
    var hrefs = find_all_anchor_hrefs(html)
    for href in hrefs:
        if len(results) >= limit:
            break
        var resolved = resolve_url(current_url, href)
        if resolved in seen:
            continue
        seen[resolved] = True
        if is_child_path(resolved, current_url):
            results.append(resolved)
    return results^
