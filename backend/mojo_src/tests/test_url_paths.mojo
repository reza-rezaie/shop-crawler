# Tests for the generic URL path-structure helpers used to discover
# "child" category links on a hub page (see openspec/changes/archive/
# ...-add-category-drill-down-crawling/). Table-driven against real
# parent/child/sibling/unrelated URL examples found live on
# azurestandard.com's own category tree.
#
# Run with: pixi run mojo run -I backend/mojo_src backend/mojo_src/tests/test_url_paths.mojo

from testing import check
from textutil import url_path, url_path_stem, is_child_path, find_all_anchor_hrefs


def test_url_path() raises:
    check(
        url_path("https://x.com/shop/category/food/flour/22474?subcategories=true") == "/shop/category/food/flour/22474",
        "query string is stripped from the path",
    )
    check(
        url_path("https://x.com/a/b#frag") == "/a/b",
        "fragment is stripped from the path",
    )
    check(url_path("https://x.com") == "/", "bare host has path '/'")
    check(url_path("https://x.com/") == "/", "trailing-slash-only host has path '/'")


def test_url_path_stem() raises:
    check(
        url_path_stem("https://x.com/shop/category/food/flour/22474") == "/shop/category/food/flour",
        "stem removes the last path segment",
    )
    check(
        url_path_stem("https://x.com/shop/category/food/") == "/shop/category",
        "trailing slash doesn't count as an extra empty segment",
    )
    check(url_path_stem("https://x.com/") == "/", "root path's stem is root")


def test_is_child_path() raises:
    var parent = String("https://www.azurestandard.com/shop/category/food/flour/22474")

    check(
        is_child_path("https://www.azurestandard.com/shop/category/food/flour/whole-wheat/22513", parent),
        "a real child category (one path segment deeper) is recognized",
    )
    check(
        is_child_path("https://www.azurestandard.com/shop/category/food/flour/gluten-free-blends/22529", parent),
        "a sibling child category is also recognized",
    )
    check(
        not is_child_path("https://www.azurestandard.com/shop/category/food/sweeteners/26411", parent),
        "a sibling of the parent (not nested under it) is not a child",
    )
    check(
        not is_child_path("https://www.azurestandard.com/about/history", parent),
        "an unrelated same-host page is not a child",
    )
    check(
        not is_child_path("https://example.com/shop/category/food/flour/whole-wheat/22513", parent),
        "a different host is never a child, even with a matching path",
    )
    check(not is_child_path(parent, parent), "a page is not its own child")

    var leaf = String("https://www.azurestandard.com/shop/category/food/baking-pantry/26644")
    check(
        is_child_path("https://www.azurestandard.com/shop/category/food/baking-pantry/mixes/26832", leaf),
        "the path-stem rule works the same for any hub page, not just this one example",
    )


def test_find_all_anchor_hrefs() raises:
    var html = String('<a href="/a">A</a><a class="x" href="https://other.com/b">B</a><a>no href</a>')
    var hrefs = find_all_anchor_hrefs(html)
    check(len(hrefs) == 2, "only anchors with an href attribute are returned")
    check(hrefs[0] == "/a", "relative hrefs are returned as-is (resolved by the caller)")
    check(hrefs[1] == "https://other.com/b", "absolute hrefs are returned as-is")


def main() raises:
    test_url_path()
    test_url_path_stem()
    test_is_child_path()
    test_find_all_anchor_hrefs()
    print("All url_paths tests passed.")
