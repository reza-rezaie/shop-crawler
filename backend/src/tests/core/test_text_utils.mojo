# Unit-style tests for text_utils.mojo's class-hint matching and attribute
# lookup, covering the azurestandard.com bug: a heuristic product-card
# matcher that treated any substring of a `class` attribute as a match,
# so a JS-framework binding expression containing the word "product" was
# mistaken for a real product card. See openspec/changes/
# fix-product-extraction-and-browsing/ for the full writeup.
#
# Run with: pixi run mojo run -I backend/src backend/src/tests/core/test_text_utils.mojo

from std.python import Python
from tests.testing import check
from core.text_utils import (
    class_hint_matches,
    is_valid_class_token,
    extract_attr,
    extract_blocks_by_class_hint,
    find_all_anchor_hrefs_with_text,
)


def test_class_hint_matches() raises:
    # The exact pattern found on https://www.azurestandard.com/shop/category/ :
    # a `class` attribute holding an Angular binding expression, not a real
    # class list. Must NOT match, even though it contains "product" as text.
    var angular_expr = String(
        "{ 'Animate--heartPulse': product.favoriteProcessing, 'Animate--heartFavoritePop': (isAnyPackFavorited()) && (product.favoritePopActive) }"
    )
    check(
        not class_hint_matches(angular_expr, "product"),
        "Angular binding expression containing 'product' as text is not a class match",
    )

    # Real class values must still match, including multi-token and
    # hyphen/underscore-separated names.
    check(class_hint_matches(String("product_pod"), "product"), "product_pod token matches")
    check(
        class_hint_matches(String("product-item featured"), "product"),
        "product-item among multiple tokens matches",
    )
    check(
        not class_hint_matches(String("Superuser bg-[red]"), "product"),
        "unrelated real class tokens do not match",
    )


def test_is_valid_class_token() raises:
    check(is_valid_class_token(String("product-item_2")), "alnum/hyphen/underscore token is valid")
    check(not is_valid_class_token(String("product.favoriteProcessing")), "dotted expression is not a valid token")
    check(not is_valid_class_token(String("{product}")), "brace-wrapped expression is not a valid token")
    check(not is_valid_class_token(String("")), "empty token is not valid")


def test_extract_attr_boundary() raises:
    # `ng-class="..."` must never satisfy a lookup for `class`.
    var ng_only = String('<li ng-class="{\'is-childActive\': foo}">')
    var result = extract_attr(ng_only, "class")
    check(not result, "class lookup finds nothing when only ng-class is present")

    # A real `class` attribute earlier or later in the tag must still be
    # found even when ng-class is also present.
    var both_order1 = String('<li class="NavSlideout-li" ng-class="{...}">')
    var result1 = extract_attr(both_order1, "class")
    check(Bool(result1) and result1.value() == "NavSlideout-li", "class found when it precedes ng-class")

    var both_order2 = String('<li ng-class="{...}" class="NavSlideout-li">')
    var result2 = extract_attr(both_order2, "class")
    check(Bool(result2) and result2.value() == "NavSlideout-li", "class found when it follows ng-class")


def test_azurestandard_fixture_no_false_positive() raises:
    """Full end-to-end regression for the reported bug: scanning the real
    azurestandard.com SPA-shell markup for "product"-hinted div/li blocks
    must find zero matches (previously it found the favorite-heart div)."""
    var pyio = Python.import_module("builtins")
    var f = pyio.open("backend/src/tests/fixtures/spa_shell_angular.html", "r", encoding="utf-8")
    var html = String(f.read())
    f.close()

    var div_matches = extract_blocks_by_class_hint(html, "div", "product")
    check(len(div_matches) == 0, "no div is mistaken for a product card in the SPA-shell fixture")

    var li_matches = extract_blocks_by_class_hint(html, "li", "product")
    check(len(li_matches) == 0, "no li is mistaken for a product card in the SPA-shell fixture")


def test_books_toscrape_fixture_still_matches() raises:
    """Regression: the class-token fix must not break matching on real,
    non-templated class names like books.toscrape.com's `product_pod`."""
    var pyio = Python.import_module("builtins")
    var f = pyio.open("backend/src/tests/fixtures/books_toscrape_listing.html", "r", encoding="utf-8")
    var html = String(f.read())
    f.close()

    var matches = extract_blocks_by_class_hint(html, "article", "product")
    check(len(matches) == 2, "both product_pod articles in the fixture still match")


def test_find_all_anchor_hrefs_with_text() raises:
    var html = String(
        '<a href="/shop/category/food/flour/22474">Flour</a>'
        + '<a href="/shop/category/food/sweeteners/26411"><img src="x.png" alt="Sweeteners"/></a>'
        + '<a href="/about/history">  About   Us  </a>'
    )
    var links = find_all_anchor_hrefs_with_text(html)
    check(len(links) == 3, "all three anchors are found")
    check(links[0].href == "/shop/category/food/flour/22474", "first href is captured")
    check(links[0].text == "Flour", "first anchor's text is captured")
    check(links[1].href == "/shop/category/food/sweeteners/26411", "second href is captured")
    check(links[1].text == "", "an anchor with no visible text (image-only) has empty text, not a crash")
    check(links[2].text == "About Us", "surrounding/internal whitespace in anchor text is collapsed")


def main() raises:
    test_class_hint_matches()
    test_is_valid_class_token()
    test_extract_attr_boundary()
    test_azurestandard_fixture_no_false_positive()
    test_books_toscrape_fixture_still_matches()
    test_find_all_anchor_hrefs_with_text()
    print("All text_utils tests passed.")
