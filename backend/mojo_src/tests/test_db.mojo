# Tests for db.mojo's source-site attribution: upsert dedup, the
# source_host derived per item, the source_host filter, and list_sources
# -- added so a catalog spanning multiple crawled sites can be told apart
# in the browse view (see openspec/changes/fix-product-extraction-and-browsing/).
#
# Run with: pixi run mojo run -I backend/mojo_src backend/mojo_src/tests/test_db.mojo

from std.python import Python
from testing import check
from db import connect, upsert_product, query_products, list_sources
from models import Product


def main() raises:
    var pyio = Python.import_module("builtins")
    var tempfile = Python.import_module("tempfile")
    var os_mod = Python.import_module("os")

    var tmp = tempfile.mkstemp(".db")
    var db_path = String(tmp[1])

    var conn = connect(db_path)

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

    conn.close()
    os_mod.remove(db_path)

    print("All db tests passed.")
