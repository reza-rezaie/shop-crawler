# Request-handling for the product_browsing capability (see
# openspec/specs/product-browsing/spec.md): parses each endpoint's
# PythonObject params dict and calls straight into core/database.mojo's
# query functions. Moved out of api.mojo -- see
# openspec/changes/chg-0001-2026-08-21-modular-monolith-vertical-slice/
# design.md, Decision 6 (this is what makes product_browsing a real,
# visible module instead of an implicit one).

from std.python import PythonObject
from core.database import (
    query_products,
    list_categories,
    list_sources,
    list_site_categories,
)
from core.request import get_str, get_int, get_optional_float


def list_products(conn: PythonObject, params: PythonObject) raises -> PythonObject:
    var search = get_str(params, "search")
    var category = get_str(params, "category")
    var min_price = get_optional_float(params, "min_price")
    var max_price = get_optional_float(params, "max_price")
    var source_host = get_str(params, "source_host")
    var page = get_int(params, "page", 1)
    var page_size = get_int(params, "page_size", 20)

    return query_products(conn, search, category, min_price, max_price, source_host, page, page_size)


def categories(conn: PythonObject) raises -> PythonObject:
    return list_categories(conn)


def sources(conn: PythonObject) raises -> PythonObject:
    return list_sources(conn)


def site_categories(conn: PythonObject, params: PythonObject) raises -> PythonObject:
    var host = get_str(params, "host")
    return list_site_categories(conn, host)
