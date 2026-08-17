# Regression tests for extracting from a *rendered* SPA page's DOM --
# offline, fixture-based, no live Playwright/network needed here (that's
# covered by manual live verification; see openspec/changes/
# add-js-rendered-crawling/tasks.md ss5). Proves the existing class-token
# extraction heuristic needs no site-specific rules once given rendered
# HTML, plus the two small robustness additions this change made (ng-src
# image fallback, div-wrapped price).
#
# Run with: pixi run mojo run -I backend/mojo_src backend/mojo_src/tests/test_js_rendered_extraction.mojo

from std.python import Python
from testing import check
from html_extract import extract_heuristic_products, extract_breadcrumb_category
from textutil import extract_attr, extract_first_void_tag


def _read_fixture(name: String) raises -> String:
    var pyio = Python.import_module("builtins")
    var f = pyio.open("backend/mojo_src/tests/fixtures/" + name, "r", encoding="utf-8")
    var content = String(f.read())
    f.close()
    return content


def test_rendered_azure_listing_extracts_real_products() raises:
    var html = _read_fixture("azure_rendered_listing.html")
    var seed_url = String("https://www.azurestandard.com/shop/category/food/baking-pantry/26644")

    var category = extract_breadcrumb_category(html)
    check(category == "Baking & Pantry", "breadcrumb category extracted from the rendered page")

    var products = extract_heuristic_products(html, seed_url, category)
    check(len(products) == 2, "both real ProductGridItem cards are extracted, not the wrapping grid div")

    var first = products[0].copy()
    check(first.name == "All Purpose Flour Unbleached, Organic, 30 oz", "first product name is correct")
    check(Bool(first.price) and first.price.value() == 4.98, "first product price is parsed correctly")
    check(first.currency == "$", "first product currency is parsed correctly")
    check(
        first.url == "/shop/product/all-purpose-flour-unbleached-organic/11444?package=FL080",
        "first product URL (relative -- resolved to absolute by crawler.mojo, not extraction) is correct",
    )
    check(
        "img.azurestandard.com" in first.image_url,
        "first product image URL is populated from ng-src (no plain src attribute exists on this element)",
    )

    var second = products[1].copy()
    check(second.name == "Cane Sugar, Organic, 5 lb", "second product name is correct")
    check(Bool(second.price) and second.price.value() == 10.02, "second product price is parsed correctly")


def test_ng_src_fallback_only_used_when_src_absent() raises:
    var with_src = extract_attr(String('<img src="a.jpg" ng-src="b.jpg" alt="x">'), "src")
    check(Bool(with_src) and with_src.value() == "a.jpg", "plain src is preferred over ng-src when both are present")

    var img_tag = extract_first_void_tag(String('<img ng-src="only-this.jpg" alt="x">'), "img")
    check(Bool(img_tag), "img tag is found")
    var no_src = extract_attr(img_tag.value(), "src")
    check(not no_src, "no plain src attribute exists on an ng-src-only image")


def main() raises:
    test_rendered_azure_listing_extracts_real_products()
    test_ng_src_fallback_only_used_when_src_absent()
    print("All js-rendered-extraction tests passed.")
