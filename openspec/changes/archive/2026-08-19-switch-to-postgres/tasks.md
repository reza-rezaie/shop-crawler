## 1. Local Postgres via pixi

- [x] 1.1 Add `postgresql` (conda-forge) and `psycopg2` to `pixi.toml` dependencies
- [x] 1.2 Write `scripts/pg_local.sh`: idempotent init (`initdb` into `data/pgdata/` if not already initialized) + start/stop of a local instance on a fixed, non-default port
- [x] 1.3 Add `data/pgdata/` to `.gitignore`
- [x] 1.4 Wire `pixi run dev`, `pixi run serve`, and `pixi run test` to ensure the local instance is running before doing their own work
- [x] 1.5 Create the app database and a separate test database (e.g. `products`, `products_test`) as part of the init step

## 2. Schema and connection layer (`db.mojo`)

- [x] 2.1 Rewrite `SCHEMA` for Postgres dialect: `GENERATED ALWAYS AS IDENTITY PRIMARY KEY` for both `id` columns; `has_own_products` as native nullable `BOOLEAN`
- [x] 2.2 Rewrite `connect()` to use `psycopg2.connect()` with libpq env vars (`PGHOST`/`PGPORT`/`PGDATABASE`/`PGUSER`/`PGPASSWORD`), `RealDictCursor` as the cursor factory, and run `SCHEMA` on connect
- [x] 2.3 Remove `_none_or_bool_as_int`; update `has_own_products` call sites to pass/read a native `Optional[Bool]` instead of an int-as-tristate
- [x] 2.4 Swap every `?` placeholder in `db.mojo` for `%s`

## 3. Upserts

- [x] 3.1 Rewrite `upsert_product` as `INSERT ... ON CONFLICT (product_url) DO UPDATE SET ... RETURNING (xmax = 0) AS inserted`, with `COALESCE(EXCLUDED.col, products.col)` preserving "don't blank out a field we already had"
- [x] 3.2 Rewrite `upsert_site_category` the same way, keyed on `url`, preserving "an unknown `has_own_products` signal never downgrades an already-known one"
- [x] 3.3 Update `UpsertOutcome` construction in both functions to read the `inserted` flag from the `RETURNING` row instead of the old SELECT-then-branch

## 4. Queries

- [x] 4.1 `query_products`: switch the name-search clause from `LIKE` to `ILIKE`; swap all placeholders to `%s`
- [x] 4.2 Update `list_categories`, `list_sources`, `list_site_categories`, `count_products` placeholders and any `row["..."]` access affected by the `has_own_products` type change

## 5. Server wiring

- [x] 5.1 Replace `DB_PATH` in `backend/server.py` with Postgres connection config sourced from env vars, with local-dev defaults matching the pixi-managed instance
- [x] 5.2 Update the startup log line (`print(f"Database: {DB_PATH}")`) to reflect the new connection info

## 6. Tests

- [x] 6.1 Update `test_db.mojo` setup/teardown: connect to the test database, `TRUNCATE products, site_categories` at the start of the run instead of `tempfile.mkstemp()` + `os.remove`
- [x] 6.2 Update any assertions that relied on `has_own_products` being read back as `0`/`1`/`None` to expect `True`/`False`/`None`
- [x] 6.3 Run the full `pixi run test` suite and confirm every existing check still passes

## 7. Data migration

- [x] 7.1 Write `scripts/migrate_sqlite_to_postgres.py`: read `products` and `site_categories` from `data/products.db` in `id ASC` order via stdlib `sqlite3`, and re-insert each row through `db.mojo`'s `upsert_product` / `upsert_site_category`
- [x] 7.2 Run the migration once against the real `data/products.db`; verify migrated row counts match the source (601 products, 166 categories)
- [x] 7.3 Spot-check via the running app: a product with a `NULL`/unknown-derived field, and a `has_own_products = NULL` category node, render correctly
- [x] 7.4 Confirm `data/products.db` is left untouched on disk after migration (backup)

## 8. Docs

- [x] 8.1 Update `SPEC.md`'s storage section (§2, §6, the architecture diagram, and the `sqlite3`/`psycopg2` dependency table row) to describe Postgres instead of SQLite
- [x] 8.2 Update `README.md` if it references SQLite or `data/products.db` setup
- [x] 8.3 Note the new local Postgres setup step (or its automatic handling via `pixi run dev`) wherever the project documents "how to run this locally"
