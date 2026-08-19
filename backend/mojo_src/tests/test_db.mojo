# Tests for db.mojo's source-site attribution: upsert dedup, the
# source_host derived per item, the source_host filter, and list_sources
# -- added so a catalog spanning multiple crawled sites can be told apart
# in the browse view (see openspec/changes/fix-product-extraction-and-browsing/).
#
# Run with: pixi run mojo run -I backend/mojo_src backend/mojo_src/tests/test_db.mojo
# Needs the pixi-managed local Postgres instance running (`pixi run test`
# starts it automatically; see scripts/pg_local.sh).

from std.python import Python
from testing import check
from db import (
    connect,
    upsert_product,
    query_products,
    list_sources,
    upsert_site_category,
    list_site_categories,
)
from models import Product


def main() raises:
    var os_mod = Python.import_module("os")

    # A dedicated test database (see scripts/pg_local.sh), truncated at the
    # start of every run instead of a deleted temp file -- same "each run
    # starts empty" isolation SQLite's tempfile.mkstemp() gave us.
    var test_db_name = String(os_mod.environ.get("PG_TEST_DATABASE", "products_test"))
    var conn = connect(test_db_name)
    var setup_cur = conn.cursor()
    setup_cur.execute("TRUNCATE products, site_categories RESTART IDENTITY")
    conn.commit()

    # Two products from one site, one from another.
    _ = upsert_product(
        conn,
        Product(
            url="https://books.toscrape.com/catalogue/a/index.html",
            name="Book A",
            price=Optional[Float64](10.0),
            source_listing_url="https://books.toscrape.com/catalogue/category/books/mystery_3/index.html",
        ),
    )
    _ = upsert_product(
        conn,
        Product(
            url="https://books.toscrape.com/catalogue/b/index.html",
            name="Book B",
            price=Optional[Float64](20.0),
            source_listing_url="https://books.toscrape.com/",
        ),
    )
    _ = upsert_product(
        conn,
        Product(
            url="https://www.azurestandard.com/shop/product/1",
            name="Azure Widget",
            price=Optional[Float64](30.0),
            source_listing_url="https://www.azurestandard.com/shop/category/",
        ),
    )

    var sources = list_sources(conn)
    check(len(sources) == 2, "two distinct source hosts are listed")

    var all_results = query_products(conn, String(""), String(""), None, None, String(""), 1, 20)
    check(Int(String(all_results["total"])) == 3, "all three products are visible with no source filter")
    for item in all_results["items"]:
        check(
            String(item["source_host"]).byte_length() > 0,
            "every item carries a non-empty source_host",
        )

    var books_only = query_products(
        conn, String(""), String(""), None, None, String("books.toscrape.com"), 1, 20
    )
    check(Int(String(books_only["total"])) == 2, "filtering by books.toscrape.com returns only its 2 products")

    var azure_only = query_products(
        conn, String(""), String(""), None, None, String("www.azurestandard.com"), 1, 20
    )
    check(Int(String(azure_only["total"])) == 1, "filtering by www.azurestandard.com returns only its 1 product")
    var azure_item = azure_only["items"][0]
    check(String(azure_item["name"]) == "Azure Widget", "the azure-filtered item is the azure product")

    # Re-upsert the same URL from a different listing page: still 3 total,
    # not 4 -- the dedup/upsert behavior this project depends on must keep
    # working with the new source_host machinery layered on top.
    _ = upsert_product(
        conn,
        Product(
            url="https://books.toscrape.com/catalogue/a/index.html",
            name="Book A",
            price=Optional[Float64](11.5),
            source_listing_url="https://books.toscrape.com/catalogue/category/books/mystery_3/index.html",
        ),
    )
    var after_recrawl = query_products(conn, String(""), String(""), None, None, String(""), 1, 20)
    check(Int(String(after_recrawl["total"])) == 3, "re-upserting an existing product_url does not create a duplicate")

    # site_categories: insert, upsert-by-url, has_own_products tri-state,
    # and per-host scoping -- see add-category-discovery-crawl.
    var hub_url = String("https://www.azurestandard.com/shop/category/food/flour/22474")
    var child_url = String("https://www.azurestandard.com/shop/category/food/flour/whole-wheat/22513")

    var hub_outcome = upsert_site_category(
        conn, hub_url, String("Flour"), String(""), String("www.azurestandard.com"), None
    )
    check(hub_outcome.created, "a new category node is created")

    var child_outcome = upsert_site_category(
        conn,
        child_url,
        String("Whole Wheat Flour"),
        hub_url,
        String("www.azurestandard.com"),
        None,
    )
    check(child_outcome.created, "a second new category node is created")

    var azure_categories = list_site_categories(conn, String("www.azurestandard.com"))
    check(len(azure_categories) == 2, "both nodes are listed for their host")

    var other_host_categories = list_site_categories(conn, String("example.com"))
    check(len(other_host_categories) == 0, "an unrelated host has no listed categories")

    var first_node = azure_categories[0]
    check(first_node["has_own_products"] is None, "a freshly-discovered, not-yet-fetched node has an unknown signal")

    # Re-upsert the hub with a known has_own_products signal (as if its own
    # page was just fetched) -- must update in place, not duplicate.
    var hub_reupsert = upsert_site_category(
        conn, hub_url, String("Flour"), String(""), String("www.azurestandard.com"), Optional[Bool](True)
    )
    check(not hub_reupsert.created, "re-upserting an existing url updates it instead of duplicating")

    var after_signal_known = list_site_categories(conn, String("www.azurestandard.com"))
    check(len(after_signal_known) == 2, "still only two nodes after the re-upsert")
    check(
        Bool(after_signal_known[0]["has_own_products"]),
        "has_own_products transitions from unknown to true once the page is actually fetched",
    )

    # A later upsert that doesn't yet know the signal (e.g. discovered again
    # as a link before its own page is re-fetched) must not downgrade an
    # already-known signal back to unknown.
    var hub_reupsert_unknown = upsert_site_category(
        conn, hub_url, String("Flour"), String(""), String("www.azurestandard.com"), None
    )
    check(not hub_reupsert_unknown.created, "upserting again still updates the same row")
    var after_unknown_reupsert = list_site_categories(conn, String("www.azurestandard.com"))
    check(
        Bool(after_unknown_reupsert[0]["has_own_products"]),
        "an unknown signal on upsert never overwrites an already-known has_own_products value",
    )

    conn.close()

    print("All db tests passed.")
