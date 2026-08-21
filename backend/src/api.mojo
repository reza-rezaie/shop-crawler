# The only file in this project that exports a Python extension module
# (`PyInit_api`). `backend/server.py` imports this (via `mojo.importer`,
# Mojo's official Python<->Mojo bridge) and calls the four functions below;
# everything they do -- crawling, extraction, filtering, storage -- is
# native Mojo from here down. See SPEC.md ss5/ss6 for the full breakdown.

from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder
from std.os import abort
from core.database import (
    connect,
    count_products,
    query_products,
    list_categories,
    list_sources,
    list_site_categories,
    upsert_product,
    upsert_site_category,
)
from core.models import Product
from modules.product_extraction.crawler import crawl as run_crawl
from category_discovery import discover_categories as run_discover_categories

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


def _get_str(d: PythonObject, key: String, default: String = String("")) raises -> String:
    var val = d.get(key)
    if val is None:
        return default
    return String(val)


def _get_int(d: PythonObject, key: String, default: Int) raises -> Int:
    var val = d.get(key)
    if val is None:
        return default
    try:
        return Int(String(val))
    except e:
        return default


def _get_bool(d: PythonObject, key: String, default: Bool) raises -> Bool:
    var val = d.get(key)
    if val is None:
        return default
    return Bool(val)


def _get_obj(d: PythonObject, key: String) raises -> PythonObject:
    """Raw value for `key`, or Python None if absent -- used for the
    internal `_progress` dict server.py smuggles into the request so a
    long-running crawl/discovery run can report live progress into a
    PythonObject the HTTP layer already holds a reference to (see
    crawler.crawl's own docstring for why a dict rather than a callback)."""
    return d.get(key)


def _get_optional_float(d: PythonObject, key: String) raises -> Optional[Float64]:
    var val = d.get(key)
    if val is None:
        return None
    var text = String(val).strip()
    if text.byte_length() == 0:
        return None
    try:
        return Optional[Float64](Float64(text))
    except e:
        return None


def health(db_path: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))
    var result = Python.dict()
    result["status"] = "ok"
    result["product_count"] = count_products(conn)
    return result


def crawl(db_path: PythonObject, request: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))

    var url = _get_str(request, "url")
    if url.byte_length() == 0:
        var err = Python.dict()
        err["error"] = "Missing required field: url"
        return err

    var max_pages = _get_int(request, "max_pages", DEFAULT_MAX_PAGES)
    var max_detail_fetches = _get_int(request, "max_detail_fetches", DEFAULT_MAX_DETAIL_FETCHES)
    var fetch_descriptions = _get_bool(request, "fetch_descriptions", True)
    var progress = _get_obj(request, "_progress")

    return run_crawl(conn, url, max_pages, max_detail_fetches, fetch_descriptions, progress)


def discover_categories(db_path: PythonObject, request: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))

    var url = _get_str(request, "url")
    if url.byte_length() == 0:
        var err = Python.dict()
        err["error"] = "Missing required field: url"
        return err

    # 0 (the default when the field is absent) is below category_discovery's
    # own "unset" threshold, so its own MAX_DISCOVERY_PAGES_DEFAULT applies --
    # avoids duplicating that default's actual value here too.
    var max_pages = _get_int(request, "max_pages", 0)
    var progress = _get_obj(request, "_progress")

    return run_discover_categories(conn, url, max_pages, progress)


def site_categories(db_path: PythonObject, params: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))
    var host = _get_str(params, "host")
    return list_site_categories(conn, host)


def list_products(db_path: PythonObject, params: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))

    var search = _get_str(params, "search")
    var category = _get_str(params, "category")
    var min_price = _get_optional_float(params, "min_price")
    var max_price = _get_optional_float(params, "max_price")
    var source_host = _get_str(params, "source_host")
    var page = _get_int(params, "page", 1)
    var page_size = _get_int(params, "page_size", 20)

    return query_products(conn, search, category, min_price, max_price, source_host, page, page_size)


def categories(db_path: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))
    return list_categories(conn)


def sources(db_path: PythonObject) raises -> PythonObject:
    var conn = connect(String(db_path))
    return list_sources(conn)


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
            url=_get_str(row, "product_url"),
            name=_get_str(row, "name"),
            price=_get_optional_float(row, "price"),
            currency=_get_str(row, "currency"),
            image_url=_get_str(row, "image_url"),
            category=_get_str(row, "category"),
            description=_get_str(row, "description"),
            source_listing_url=_get_str(row, "source_listing_url"),
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
            _get_str(row, "url"),
            _get_str(row, "name"),
            _get_str(row, "parent_url"),
            _get_str(row, "host"),
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
