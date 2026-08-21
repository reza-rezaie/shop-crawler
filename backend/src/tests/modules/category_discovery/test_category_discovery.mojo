# Tests for modules/category_discovery/discovery.mojo's pure per-page decision logic
# (decide_discovery_page, name_from_url, pending_after_budget). The full
# discover_categories BFS loop does live network fetches (like
# crawler.mojo's own crawl() loop) and is verified manually instead -- see
# openspec/changes/add-category-discovery-crawl/tasks.md ss6.2/6.3.
#
# Run with: pixi run mojo run -I backend/src backend/src/tests/modules/category_discovery/test_category_discovery.mojo

from std.python import Python
from tests.testing import check
from modules.category_discovery.discovery import (
    decide_discovery_page,
    name_from_url,
    pending_after_budget,
    DiscoveryQueueEntry,
    MAX_DISCOVERY_CHILDREN_PER_HUB,
)


def _read_fixture(name: String) raises -> String:
    var pyio = Python.import_module("builtins")
    var f = pyio.open("backend/src/tests/fixtures/" + name, "r", encoding="utf-8")
    var content = String(f.read())
    f.close()
    return content


def test_nested_children_are_named_and_parented() raises:
    var html = String(
        '<a href="/shop/category/food/flour/whole-wheat/22513">Whole Wheat Flour</a>'
        + '<a href="/shop/category/food/flour/gluten-free-blends/22529">Gluten Free Flour</a>'
        + '<a href="/about/history">About Us</a>'
        + '<a href="https://other-site.com/shop/category/food/flour/whole-wheat/22513">Off-site copy</a>'
    )
    var url = String("https://www.azurestandard.com/shop/category/food/flour/22474")
    var decision = decide_discovery_page(html, url, String(""))

    check(not decision.is_not_found, "an ordinary hub page is not flagged as not-found")
    check(
        len(decision.children) == 2,
        "only the two same-host, path-nested links are kept (unrelated and off-site links excluded)",
    )
    check(
        decision.children[0].url == "https://www.azurestandard.com/shop/category/food/flour/whole-wheat/22513",
        "first child's href is resolved to an absolute URL",
    )
    check(decision.children[0].name == "Whole Wheat Flour", "first child's name comes from its anchor text")
    check(decision.children[0].parent_url == url, "first child's parent is the page it was found on")
    check(decision.children[1].name == "Gluten Free Flour", "second child's name comes from its anchor text")


def test_duplicate_link_on_one_page_is_not_repeated() raises:
    var html = String(
        '<a href="/shop/category/food/flour/22474">Flour (nav)</a>'
        + '<a href="/shop/category/food/flour/22474">Flour (footer)</a>'
    )
    var url = String("https://www.azurestandard.com/shop/category/food/")
    var decision = decide_discovery_page(html, url, String(""))
    check(len(decision.children) == 1, "the same href appearing twice on one page yields one child, not two")


def test_children_capped_at_the_per_page_limit() raises:
    var html = String("")
    var i = 0
    while i < MAX_DISCOVERY_CHILDREN_PER_HUB + 5:
        html += '<a href="/shop/category/food/sub' + String(i) + '/">Sub ' + String(i) + "</a>"
        i += 1
    var url = String("https://www.azurestandard.com/shop/category/food/")
    var decision = decide_discovery_page(html, url, String(""))
    check(len(decision.children) == MAX_DISCOVERY_CHILDREN_PER_HUB, "the per-page child cap is respected")


def test_anchor_with_no_text_falls_back_to_url_derived_name() raises:
    var html = String('<a href="/shop/category/food/sweeteners/26411"><img src="x.png" alt="Sweeteners"/></a>')
    var url = String("https://www.azurestandard.com/shop/category/food/")
    var decision = decide_discovery_page(html, url, String(""))
    check(len(decision.children) == 1, "the image-only-anchor child is still discovered")
    check(decision.children[0].name == "26411", "an empty anchor text falls back to a name derived from the URL")


def test_own_next_page_link_is_not_treated_as_a_child() raises:
    var html = String(
        '<a href="/shop/category/food/flour/whole-wheat/22513">Whole Wheat Flour</a>'
        + '<li class="next"><a href="/shop/category/food/flour/page-2.html">Next</a></li>'
    )
    var url = String("https://www.azurestandard.com/shop/category/food/flour/index.html")
    var decision = decide_discovery_page(html, url, String(""))
    check(
        len(decision.children) == 1,
        "the page's own pagination target is excluded from child candidates, only the real subcategory remains",
    )
    check(decision.children[0].name == "Whole Wheat Flour", "the surviving child is the genuine subcategory link")


def test_fragment_only_variant_is_not_a_distinct_child() raises:
    var html = String(
        '<a href="/shop/product/widget/8428">Widget</a>'
        + '<a href="/shop/product/widget/8428#reviews">356 reviews</a>'
    )
    var url = String("https://www.azurestandard.com/shop/clearance")
    var decision = decide_discovery_page(html, url, String(""))
    check(
        len(decision.children) == 1,
        "a plain link and its #fragment variant to the same page count as one child, not two",
    )
    check(decision.children[0].url == "https://www.azurestandard.com/shop/product/widget/8428", "the fragment is stripped from the stored child url")


def test_not_found_page_is_excluded_and_not_traversed() raises:
    var not_found_html = _read_fixture("azure_not_found.html")
    var decision = decide_discovery_page(not_found_html, String("https://www.azurestandard.com/shop/category/food/"), String(""))
    check(decision.is_not_found, "the real azurestandard.com 404 page content is detected as not-found")
    check(len(decision.children) == 0, "a not-found page yields no children, even if its own markup has links")


def test_hub_page_with_own_products_is_flagged() raises:
    var listing_html = _read_fixture("books_toscrape_listing.html")
    var decision = decide_discovery_page(listing_html, String("https://books.toscrape.com/"), String(""))
    check(not decision.is_not_found, "a real listing page is not flagged as not-found")
    check(decision.has_own_products, "a page whose HTML matches the product-card heuristic is flagged as having its own products")


def test_page_without_products_is_flagged_false() raises:
    var not_found_html = _read_fixture("azure_not_found.html")
    # (Already excluded above by is_not_found; here we confirm an ordinary,
    # real, but product-less page -- not a 404 -- gets false, not unknown.)
    var html = String("<html><body><h1>Flour</h1><a href=\"/shop/category/food/flour/sub/1\">Sub</a></body></html>")
    var decision = decide_discovery_page(html, String("https://www.azurestandard.com/shop/category/food/flour/"), String(""))
    check(not decision.is_not_found, "a genuine hub page with no product markup is not mistaken for a 404")
    check(not decision.has_own_products, "a page with no product-card markup is flagged as not having its own products")
    _ = not_found_html


def test_name_from_url() raises:
    check(name_from_url(String("https://x.com/shop/category/food/flour/22474")) == "22474", "last path segment is used as the fallback name")
    check(name_from_url(String("https://x.com/shop/category/food/flour/22474/")) == "22474", "a trailing slash doesn't change the fallback name")
    check(name_from_url(String("https://x.com/")) == "x.com", "a bare host with no path falls back to the host itself")


def test_pending_after_budget() raises:
    var queue = List[DiscoveryQueueEntry]()
    queue.append(DiscoveryQueueEntry(String("https://x.com/a"), String(""), String("A")))
    queue.append(DiscoveryQueueEntry(String("https://x.com/a/b"), String("https://x.com/a"), String("B")))
    queue.append(DiscoveryQueueEntry(String("https://x.com/a/c"), String("https://x.com/a"), String("C")))

    var visited = Dict[String, Bool]()
    visited[String("https://x.com/a")] = True

    var pending = pending_after_budget(queue, 0, visited)
    check(len(pending) == 2, "already-visited entries are excluded, unvisited ones remain")
    check(pending[0].url == "https://x.com/a/b", "an unvisited entry's url is preserved")
    check(pending[0].name == "B", "an unvisited entry's name is preserved")
    check(pending[0].parent_url == "https://x.com/a", "an unvisited entry's parent is preserved")

    var pending_from_later = pending_after_budget(queue, 2, visited)
    check(len(pending_from_later) == 1, "starting past the first two entries only considers what's left in the queue")


def main() raises:
    test_nested_children_are_named_and_parented()
    test_duplicate_link_on_one_page_is_not_repeated()
    test_children_capped_at_the_per_page_limit()
    test_anchor_with_no_text_falls_back_to_url_derived_name()
    test_own_next_page_link_is_not_treated_as_a_child()
    test_fragment_only_variant_is_not_a_distinct_child()
    test_not_found_page_is_excluded_and_not_traversed()
    test_hub_page_with_own_products_is_flagged()
    test_page_without_products_is_flagged_false()
    test_name_from_url()
    test_pending_after_budget()
    print("All category-discovery tests passed.")
