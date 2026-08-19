"""One-time migration: copy data/products.db's existing rows into the
Postgres catalog (see openspec/changes/switch-to-postgres).

Reuses db.mojo's actual upsert_product/upsert_site_category, via the same
`api` module server.py imports (api.migrate_products / api.migrate_site_
categories) -- so migration exercises the exact same dedup/COALESCE code
path a live crawl uses, and reruns are safe (idempotent, matched by URL).

Those upserts always stamp first_seen_at/last_seen_at with "now" -- correct
for a live crawl, not for a historical import -- so this script restores
the original SQLite timestamps with a direct SQL pass afterward.

The source data/products.db is only ever read, never modified or deleted;
it's left in place as a backup after migration.

Run via `pixi run db-migrate` (ensures the local Postgres instance is
running first; see scripts/pg_local.sh).
"""

import os
import sqlite3
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
MOJO_SRC_DIR = PROJECT_ROOT / "backend" / "mojo_src"
SQLITE_PATH = PROJECT_ROOT / "data" / "products.db"
DB_NAME = os.environ.get("PGDATABASE", "products")

sys.path.insert(0, str(MOJO_SRC_DIR))
import mojo.importer  # noqa: E402  (enables `import api` below to load api.mojo)
import api  # noqa: E402  -- the native Mojo backend


def _read_rows(conn: sqlite3.Connection, table: str) -> list[dict]:
    conn.row_factory = sqlite3.Row
    cur = conn.execute(f"SELECT * FROM {table} ORDER BY id ASC")
    return [dict(row) for row in cur.fetchall()]


def _restore_timestamps(products: list[dict], categories: list[dict]) -> None:
    """See module docstring: the upsert path always stamps "now", so put
    the original first_seen_at/last_seen_at back for this one-time import."""
    import psycopg2

    conn = psycopg2.connect(
        host=os.environ.get("PGHOST", "127.0.0.1"),
        port=os.environ.get("PGPORT", "5544"),
        dbname=DB_NAME,
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD", ""),
    )
    cur = conn.cursor()
    for row in products:
        cur.execute(
            "UPDATE products SET first_seen_at = %s, last_seen_at = %s WHERE product_url = %s",
            (row["first_seen_at"], row["last_seen_at"], row["product_url"]),
        )
    for row in categories:
        cur.execute(
            "UPDATE site_categories SET first_seen_at = %s, last_seen_at = %s WHERE url = %s",
            (row["first_seen_at"], row["last_seen_at"], row["url"]),
        )
    conn.commit()
    conn.close()


def main() -> None:
    if not SQLITE_PATH.exists():
        print(f"No SQLite database found at {SQLITE_PATH} -- nothing to migrate.")
        return

    sqlite_conn = sqlite3.connect(f"file:{SQLITE_PATH}?mode=ro", uri=True)
    products = _read_rows(sqlite_conn, "products")
    categories = _read_rows(sqlite_conn, "site_categories")
    sqlite_conn.close()

    print(f"Read {len(products)} products and {len(categories)} categories from {SQLITE_PATH}")

    product_result = api.migrate_products(DB_NAME, products)
    print(f"Products:   {product_result['created']} created, {product_result['updated']} updated")

    category_result = api.migrate_site_categories(DB_NAME, categories)
    print(f"Categories: {category_result['created']} created, {category_result['updated']} updated")

    _restore_timestamps(products, categories)

    print(f"Migration complete. {SQLITE_PATH} was left untouched (kept as a backup).")


if __name__ == "__main__":
    main()
