# The only file in this project that exports a Python extension module
# (`PyInit_api`). `backend/server.py` imports this (via `mojo.importer`,
# Mojo's official Python<->Mojo bridge) and calls the functions registered
# in PyInit_api below; each one connects and immediately delegates to its
# owning module (modules/product_extraction, modules/category_discovery,
# modules/product_browsing) -- everything crawling/extraction/filtering/
# storage actually does is native Mojo from there down. `health` and the
# two `migrate_*` functions are the exceptions: generic liveness and a
# one-time migration utility, not feature request handling, so they stay
# here rather than in any module -- see
# openspec/changes/chg-0001-2026-08-21-modular-monolith-vertical-slice/
# design.md, Decision 7. See SPEC.md ss5/ss6 for the full breakdown.

from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder
from std.os import abort
from core.database import connect, count_products, upsert_product, upsert_site_category
from core.models import Product
from core.request import get_str, get_int, get_bool, get_obj, get_optional_float
from modules.product_extraction.crawler import crawl as run_crawl
from modules.category_discovery.discovery import discover_categories as run_discover_categories
from modules.product_browsing.browsing import (
    list_products as browse_list_products,
    categories as browse_categories,
    sources as browse_sources,
    site_categories as browse_site_categories,
)

comptime DEFAULT_MAX_PAGES = 3
comptime DEFAULT_MAX_DETAIL_FETCHES = 60


@export
def PyInit_api() -> PythonObject:
    try:
        var m = PythonModuleBuilder("api")
        m.def_function[health]("health")
        m.def_function[crawl]("crawl")
        m.def_function[list_products]("list_products")
        m.def_function[categories]("categories")
        m.def_function[sources]("sources")
        m.def_function[discover_categories]("discover_categories")
        m.def_function[site_categories]("site_categories")
        m.def_function[migrate_products]("migrate_products")
        m.def_function[migrate_site_categories]("migrate_site_categories")
        return m.finalize()
    except e:
        abort(String("error creating api module: ", e))


def health(db_path: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))
    var result = Python.dict()
    result["status"] = "ok"
    result["product_count"] = count_products(conn)
    return result


def crawl(db_path: PythonObject, request: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))

    var url = get_str(request, "url")
    if url.byte_length() == 0:
        var err = Python.dict()
        err["error"] = "Missing required field: url"
        return err

    var max_pages = get_int(request, "max_pages", DEFAULT_MAX_PAGES)
    var max_detail_fetches = get_int(request, "max_detail_fetches", DEFAULT_MAX_DETAIL_FETCHES)
    var fetch_descriptions = get_bool(request, "fetch_descriptions", True)
    var progress = get_obj(request, "_progress")

    return run_crawl(conn, url, max_pages, max_detail_fetches, fetch_descriptions, progress)


def discover_categories(db_path: PythonObject, request: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))

    var url = get_str(request, "url")
    if url.byte_length() == 0:
        var err = Python.dict()
        err["error"] = "Missing required field: url"
        return err

    # 0 (the default when the field is absent) is below category_discovery's
    # own "unset" threshold, so its own MAX_DISCOVERY_PAGES_DEFAULT applies --
    # avoids duplicating that default's actual value here too.
    var max_pages = get_int(request, "max_pages", 0)
    var progress = get_obj(request, "_progress")

    return run_discover_categories(conn, url, max_pages, progress)


def site_categories(db_path: PythonObject, params: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))
    return browse_site_categories(conn, params)


def list_products(db_path: PythonObject, params: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))
    return browse_list_products(conn, params)


def categories(db_path: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))
    return browse_categories(conn)


def sources(db_path: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))
    return browse_sources(conn)


def migrate_products(db_path: PythonObject, rows: PythonObject) raises -> PythonObject:
    """Bulk-upsert products from a list of Python dicts (rows read from the
    retired SQLite database by scripts/migrate_sqlite_to_postgres.py)
    through the exact same upsert_product path a live crawl uses -- so the
    one-time migration never drifts from the app's own dedup/COALESCE
    semantics, and is safe to rerun. Row keys match the old SQLite column
    names (product_url, name, price, ...)."""
    var conn = connect(String(db_path))
    var created = 0
    var updated = 0
    for row in rows:
        var product = Product(
            url=get_str(row, "product_url"),
            name=get_str(row, "name"),
            price=get_optional_float(row, "price"),
            currency=get_str(row, "currency"),
            image_url=get_str(row, "image_url"),
            category=get_str(row, "category"),
            description=get_str(row, "description"),
            source_listing_url=get_str(row, "source_listing_url"),
        )
        var outcome = upsert_product(conn, product)
        if outcome.created:
            created += 1
        else:
            updated += 1
    var result = Python.dict()
    result["created"] = created
    result["updated"] = updated
    return result


def migrate_site_categories(db_path: PythonObject, rows: PythonObject) raises -> PythonObject:
    """Bulk-upsert site_categories rows the same way -- see migrate_products.
    `has_own_products` in the source rows is SQLite's 0/1/None; Bool(...) on
    a Python int gives the right True/False, and None stays unknown."""
    var conn = connect(String(db_path))
    var created = 0
    var updated = 0
    for row in rows:
        var raw_has_own = row.get("has_own_products")
        var has_own_products: Optional[Bool] = None
        if raw_has_own is not None:
            has_own_products = Optional[Bool](Bool(raw_has_own))
        var outcome = upsert_site_category(
            conn,
            get_str(row, "url"),
            get_str(row, "name"),
            get_str(row, "parent_url"),
            get_str(row, "host"),
            has_own_products,
        )
        if outcome.created:
            created += 1
        else:
            updated += 1
    var result = Python.dict()
    result["created"] = created
    result["updated"] = updated
    return result
