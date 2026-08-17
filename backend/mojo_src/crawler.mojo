# Native Mojo crawl orchestration: fetch -> extract -> paginate -> (optionally)
# fetch descriptions -> upsert. This is the one place that ties together
# http_client.mojo, html_extract.mojo, pricing.mojo (via html_extract) and
# db.mojo. The only Python interop used directly here is building the
# summary as a Python dict (so api.mojo can hand it straight back to the
# HTTP layer).

from std.python import Python, PythonObject
from models import Product
from http_client import fetch, can_fetch, resolve_url, rate_limit_sleep
from html_extract import (
    extract_json_ld_products,
    extract_heuristic_products,
    find_next_page_url,
    extract_breadcrumb_category,
    extract_last_breadcrumb_items,
    extract_product_description,
    looks_like_client_rendered_app,
)
from db import upsert_product

comptime MAX_PAGES_DEFAULT = 3
comptime MAX_PAGES_HARD_CAP = 20
comptime MAX_DETAIL_FETCHES_DEFAULT = 60


def crawl(
    conn: PythonObject,
    seed_url: String,
    max_pages: Int,
    max_detail_fetches: Int,
    fetch_descriptions: Bool,
) raises -> PythonObject:
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

    if not can_fetch(seed_url):
        errors.append("Crawling this URL is disallowed by the site's robots.txt")
        return _summary(seed_url, 0, 0, 0, 0, errors, notes)

    var seen_product_urls = Dict[String, Bool]()
    var visited_pages = Dict[String, Bool]()
    var pending_products = List[Product]()

    var current_url = seed_url
    var pages_crawled = 0

    while pages_crawled < capped_pages:
        if current_url in visited_pages:
            break
        visited_pages[current_url] = True

        var result = fetch(current_url)
        pages_crawled += 1
        if not result.ok:
            errors.append("Failed to fetch " + current_url + ": " + result.error)
            break

        var page_category = extract_breadcrumb_category(result.body)

        var products = extract_json_ld_products(result.body, current_url)
        if len(products) == 0:
            products = extract_heuristic_products(result.body, current_url, page_category)

        if looks_like_client_rendered_app(result.body, len(products)):
            notes.append(
                current_url
                + " found no product markup and looks like it renders its content"
                + " with client-side JavaScript (an app-shell marker was found in the"
                + " raw HTML). This crawler only fetches raw HTML, so it can't see"
                + " content that page renders client-side."
            )

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

        var next_url_opt = find_next_page_url(result.body, current_url)

        if pages_crawled < capped_pages:
            rate_limit_sleep()

        if next_url_opt:
            var next_url = next_url_opt.value()
            if next_url == current_url:
                break
            current_url = next_url
        else:
            break

    var created = 0
    var updated = 0
    var detail_fetches = 0

    var i = 0
    while i < len(pending_products):
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
