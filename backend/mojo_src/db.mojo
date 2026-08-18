# Native Mojo SQLite storage layer. SQL text assembly, upsert/query logic,
# and control flow all live here; only the actual statement execution goes
# through Python's `sqlite3` (see SPEC.md ss6 -- Mojo has no native SQLite
# driver yet).

from std.python import Python, PythonObject
from models import Product
from http_client import now_iso
from textutil import extract_host

comptime SCHEMA = """
CREATE TABLE IF NOT EXISTS products (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    product_url         TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    price               REAL,
    currency            TEXT,
    image_url           TEXT,
    category            TEXT,
    description         TEXT,
    source_listing_url  TEXT NOT NULL,
    first_seen_at       TEXT NOT NULL,
    last_seen_at        TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_price ON products(price);

CREATE TABLE IF NOT EXISTS site_categories (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    url               TEXT NOT NULL UNIQUE,
    name              TEXT NOT NULL,
    parent_url        TEXT,
    host              TEXT NOT NULL,
    has_own_products  INTEGER,
    first_seen_at     TEXT NOT NULL,
    last_seen_at      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_site_categories_host ON site_categories(host);
CREATE INDEX IF NOT EXISTS idx_site_categories_parent ON site_categories(parent_url);
"""


def connect(db_path: String) raises -> PythonObject:
    var sqlite3 = Python.import_module("sqlite3")
    var conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    conn.commit()
    return conn


def _none_or(value: Optional[Float64]) raises -> PythonObject:
    if value:
        return PythonObject(value.value())
    return Python.none()


def _none_or_str(value: String) raises -> PythonObject:
    if value.byte_length() == 0:
        return Python.none()
    return PythonObject(value)


def _none_or_bool_as_int(value: Optional[Bool]) raises -> PythonObject:
    """NULL for unknown, else 0/1 -- how has_own_products' tri-state is
    represented in SQLite (no native boolean/nullable-bool type)."""
    if value:
        if value.value():
            return PythonObject(1)
        return PythonObject(0)
    return Python.none()


struct UpsertOutcome(Copyable, Movable):
    var created: Bool

    def __init__(out self, created: Bool):
        self.created = created


def upsert_product(conn: PythonObject, product: Product) raises -> UpsertOutcome:
    """Insert a new product, or update an existing one (matched by
    product_url) in place -- this is what makes re-crawling idempotent
    instead of creating duplicates."""
    var existing = conn.execute(
        "SELECT id FROM products WHERE product_url = ?",
        Python.tuple(product.url),
    ).fetchone()

    var now = now_iso()

    if existing is None:
        conn.execute(
            """INSERT INTO products
                (product_url, name, price, currency, image_url, category,
                 description, source_listing_url, first_seen_at, last_seen_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            Python.tuple(
                product.url,
                product.name,
                _none_or(product.price),
                _none_or_str(product.currency),
                _none_or_str(product.image_url),
                _none_or_str(product.category),
                _none_or_str(product.description),
                product.source_listing_url,
                now,
                now,
            ),
        )
        conn.commit()
        return UpsertOutcome(True)

    # Update, but don't blank out a field we already had (e.g. a re-crawl
    # of the listing page alone shouldn't erase a description that was only
    # ever available from the detail page).
    conn.execute(
        """UPDATE products SET
            name = ?,
            price = COALESCE(?, price),
            currency = COALESCE(?, currency),
            image_url = COALESCE(?, image_url),
            category = COALESCE(?, category),
            description = COALESCE(?, description),
            source_listing_url = ?,
            last_seen_at = ?
           WHERE product_url = ?""",
        Python.tuple(
            product.name,
            _none_or(product.price),
            _none_or_str(product.currency),
            _none_or_str(product.image_url),
            _none_or_str(product.category),
            _none_or_str(product.description),
            product.source_listing_url,
            now,
            product.url,
        ),
    )
    conn.commit()
    return UpsertOutcome(False)


def upsert_site_category(
    conn: PythonObject,
    url: String,
    name: String,
    parent_url: String,
    host: String,
    has_own_products: Optional[Bool],
) raises -> UpsertOutcome:
    """Insert a new discovered category node, or update an existing one
    (matched by url) -- same idempotent-upsert shape as upsert_product, so
    re-running discovery against a site already in the table is additive
    rather than duplicative.

    `has_own_products` is COALESCEd on update, never overwritten with
    unknown (None): a node recorded as a bare link from its parent's page
    (unknown, because its own page hasn't been fetched yet) must not wipe
    out a true/false signal an earlier discovery run already established
    for that same URL."""
    var existing = conn.execute(
        "SELECT id FROM site_categories WHERE url = ?",
        Python.tuple(url),
    ).fetchone()

    var now = now_iso()

    if existing is None:
        conn.execute(
            """INSERT INTO site_categories
                (url, name, parent_url, host, has_own_products, first_seen_at, last_seen_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            Python.tuple(
                url,
                name,
                _none_or_str(parent_url),
                host,
                _none_or_bool_as_int(has_own_products),
                now,
                now,
            ),
        )
        conn.commit()
        return UpsertOutcome(True)

    conn.execute(
        """UPDATE site_categories SET
            name = ?,
            parent_url = ?,
            host = ?,
            has_own_products = COALESCE(?, has_own_products),
            last_seen_at = ?
           WHERE url = ?""",
        Python.tuple(
            name,
            _none_or_str(parent_url),
            host,
            _none_or_bool_as_int(has_own_products),
            now,
            url,
        ),
    )
    conn.commit()
    return UpsertOutcome(False)


def list_site_categories(conn: PythonObject, host: String) raises -> PythonObject:
    """Every category node discovered for one host, in discovery order --
    the tree view groups these by parent_url client-side."""
    var rows = conn.execute(
        "SELECT id, url, name, parent_url, has_own_products FROM site_categories WHERE host = ? ORDER BY id ASC",
        Python.tuple(host),
    ).fetchall()
    var out = Python.list()
    for row in rows:
        var item = Python.dict()
        item["id"] = row["id"]
        item["url"] = row["url"]
        item["name"] = row["name"]
        item["parent_url"] = row["parent_url"]
        item["has_own_products"] = row["has_own_products"]
        out.append(item)
    return out


def count_products(conn: PythonObject) raises -> Int:
    var row = conn.execute("SELECT COUNT(*) AS n FROM products").fetchone()
    return Int(String(row["n"]))


def list_categories(conn: PythonObject) raises -> PythonObject:
    var rows = conn.execute(
        "SELECT DISTINCT category FROM products WHERE category IS NOT NULL AND category != '' ORDER BY category"
    ).fetchall()
    var out = Python.list()
    for row in rows:
        out.append(row["category"])
    return out


def list_sources(conn: PythonObject) raises -> PythonObject:
    """Distinct site hosts currently represented in the catalog, derived
    from source_listing_url (there is no separate stored column) -- lets
    the browse view offer "which site is this from" as a filter, and lets
    a user visually confirm which products came from which crawl instead
    of everything blending into one undifferentiated list."""
    var rows = conn.execute("SELECT DISTINCT source_listing_url FROM products").fetchall()
    var seen = Dict[String, Bool]()
    var hosts = List[String]()
    for row in rows:
        var host = extract_host(String(row["source_listing_url"]))
        if host.byte_length() > 0 and host not in seen:
            seen[host] = True
            hosts.append(host)
    sort(hosts)

    var out = Python.list()
    for host in hosts:
        out.append(host)
    return out


def query_products(
    conn: PythonObject,
    search: String,
    category: String,
    min_price: Optional[Float64],
    max_price: Optional[Float64],
    source_host: String,
    page: Int,
    page_size: Int,
) raises -> PythonObject:
    """Build and run the filtered/paginated product listing query. Returns a
    Python dict {"items": [...], "total": N, "page": p, "page_size": s} --
    it's handed straight back to the HTTP layer, so it's built as a Python
    object here rather than a Mojo struct."""
    var where_clauses = List[String]()
    var params = Python.list()

    if search.byte_length() > 0:
        where_clauses.append(String("name LIKE ?"))
        params.append("%" + search + "%")

    if category.byte_length() > 0:
        where_clauses.append(String("category = ?"))
        params.append(category)

    if min_price:
        where_clauses.append(String("price >= ?"))
        params.append(min_price.value())

    if max_price:
        where_clauses.append(String("price <= ?"))
        params.append(max_price.value())

    if source_host.byte_length() > 0:
        # source_listing_url is stored as a full URL, not a bare host, so
        # match it as "<scheme>://<host>/..." or exactly "<scheme>://<host>".
        where_clauses.append(
            String("(source_listing_url LIKE ? OR source_listing_url = ? OR source_listing_url = ?)")
        )
        params.append("%://" + source_host + "/%")
        params.append("http://" + source_host)
        params.append("https://" + source_host)

    var where_sql = String("")
    if len(where_clauses) > 0:
        where_sql = " WHERE " + " AND ".join(where_clauses)

    var count_sql = "SELECT COUNT(*) AS n FROM products" + where_sql
    var total_row = conn.execute(count_sql, params).fetchone()
    var total = Int(String(total_row["n"]))

    var safe_page = page
    if safe_page < 1:
        safe_page = 1
    var safe_page_size = page_size
    if safe_page_size < 1:
        safe_page_size = 20
    if safe_page_size > 200:
        safe_page_size = 200
    var offset = (safe_page - 1) * safe_page_size

    var list_sql = (
        "SELECT * FROM products"
        + where_sql
        + " ORDER BY last_seen_at DESC, id DESC LIMIT ? OFFSET ?"
    )
    var list_params = params
    list_params.append(safe_page_size)
    list_params.append(offset)
    var rows = conn.execute(list_sql, list_params).fetchall()

    var items = Python.list()
    for row in rows:
        var item = Python.dict()
        item["id"] = row["id"]
        item["product_url"] = row["product_url"]
        item["name"] = row["name"]
        item["price"] = row["price"]
        item["currency"] = row["currency"]
        item["image_url"] = row["image_url"]
        item["category"] = row["category"]
        item["description"] = row["description"]
        item["source_listing_url"] = row["source_listing_url"]
        item["source_host"] = extract_host(String(row["source_listing_url"]))
        item["first_seen_at"] = row["first_seen_at"]
        item["last_seen_at"] = row["last_seen_at"]
        items.append(item)

    var result = Python.dict()
    result["items"] = items
    result["total"] = total
    result["page"] = safe_page
    result["page_size"] = safe_page_size
    return result
