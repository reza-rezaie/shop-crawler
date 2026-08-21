# Tests for not-found-page detection and child-category-link discovery,
# added after investigating a reported crawl of
# https://www.azurestandard.com/shop/category/food/ (a URL that turned
# out to be a genuine 404 in the site's own router) and the real
# category-tree structure underneath its working category pages. See
# openspec/changes/archive/...-add-category-drill-down-crawling/.
#
# Run with: pixi run mojo run -I backend/src backend/src/tests/test_category_drill_down.mojo

from std.python import Python
from testing import check
from html_extract import looks_like_not_found_page, find_child_links


def _read_fixture(name: String) raises -> String:
    var pyio = Python.import_module("builtins")
    var f = pyio.open("backend/src/tests/fixtures/" + name, "r", encoding="utf-8")
    var content = String(f.read())
    f.close()
    return content


def test_not_found_detection() raises:
    var not_found_html = _read_fixture("azure_not_found.html")
    check(
        looks_like_not_found_page(not_found_html),
        "the real azurestandard.com 404 page content is detected as not-found",
    )

    var spa_shell_html = _read_fixture("spa_shell_angular.html")
    check(
        not looks_like_not_found_page(spa_shell_html),
        "a page that legitimately has no products (but isn't a 404) is not flagged as not-found",
    )

    var listing_html = _read_fixture("books_toscrape_listing.html")
    check(
        not looks_like_not_found_page(listing_html),
        "an ordinary listing page is not flagged as not-found",
    )


def test_find_child_links() raises:
    # Real hrefs observed on azurestandard.com's own navigation during
    # live investigation of its category tree.
    var html = String(
        '<nav><a href="/shop/category/food/flour/whole-wheat/22513">Whole Wheat Flour</a>'
        + '<a href="/shop/category/food/flour/gluten-free-blends/22529?subcategories=true">Gluten Free Flour</a>'
        + '<a href="/shop/category/food/sweeteners/26411">Sweeteners</a>'
        + '<a href="/about/history">About Us</a>'
        + '<a href="https://other-site.com/shop/category/food/flour/whole-wheat/22513">Off-site copy</a>'
        + "</nav>"
    )
    var current_url = String("https://www.azurestandard.com/shop/category/food/flour/22474")

    var children = find_child_links(html, current_url, 10)
    check(len(children) == 2, "only the two real child links are found (sibling/unrelated/off-site excluded)")
    check(
        children[0] == "https://www.azurestandard.com/shop/category/food/flour/whole-wheat/22513",
        "relative child href is resolved to an absolute URL",
    )
    check(
        children[1] == "https://www.azurestandard.com/shop/category/food/flour/gluten-free-blends/22529?subcategories=true",
        "child href's query string doesn't prevent path matching, and is preserved in the resolved URL (it may affect what the site renders)",
    )


def test_find_child_links_respects_limit() raises:
    var html = String(
        '<a href="/shop/category/food/flour/a/1">A</a>'
        + '<a href="/shop/category/food/flour/b/2">B</a>'
        + '<a href="/shop/category/food/flour/c/3">C</a>'
    )
    var current_url = String("https://www.azurestandard.com/shop/category/food/flour/22474")
    var children = find_child_links(html, current_url, 2)
    check(len(children) == 2, "the per-page child-link cap is respected")


def main() raises:
    test_not_found_detection()
    test_find_child_links()
    test_find_child_links_respects_limit()
    print("All category-drill-down tests passed.")
