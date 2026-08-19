## Why

The catalog store (`data/products.db`) is SQLite today, written to via a single-writer file. As crawls and browsing grow (more sources, concurrent crawl + browse traffic, live progress polling alongside writes), a real client/server database removes SQLite's single-writer contention and gives the project atomic, race-free upserts (`INSERT ... ON CONFLICT DO UPDATE`) instead of the current SELECT-then-INSERT/UPDATE pattern. Now is a good time — the schema is still small (2 tables) and the entire storage surface is contained in one file (`db.mojo`).

## What Changes

- Replace `sqlite3` (stdlib) with Postgres (`psycopg2`, added as a pixi/conda-forge dependency) as the product/category catalog store.
- Rewrite `db.mojo`'s schema for Postgres dialect: `GENERATED ALWAYS AS IDENTITY` instead of `INTEGER PRIMARY KEY AUTOINCREMENT`; `has_own_products` becomes a native nullable `BOOLEAN` instead of the `INTEGER`-as-tristate workaround SQLite required.
- **BREAKING**: `connect()` takes Postgres connection parameters (host/port/dbname/user/password, sourced from environment variables with local-dev defaults) instead of a SQLite file path. `DB_PATH` in `server.py` is replaced accordingly.
- Rewrite `upsert_product` / `upsert_site_category` to use `INSERT ... ON CONFLICT (...) DO UPDATE` instead of the current SELECT-then-branch pattern (idiomatic Postgres, atomic, removes a small check-then-act race).
- Preserve every existing behavior/requirement as-is, in particular:
  - Case-insensitive name search (`product-browsing`'s "Search and filter" requirement) — SQLite's `LIKE` is case-insensitive by default, Postgres's is not, so the query switches to `ILIKE` to keep matching that requirement.
  - Idempotent upsert-by-URL dedup, and `has_own_products`'s COALESCE-never-downgrades-to-unknown behavior.
  - Per-host category scoping, source-host filtering, and paginated/filtered product queries — same query results, same API responses.
- Add a pixi-managed local Postgres for dev/test: `postgresql` as a pixi (conda-forge) dependency, plus pixi tasks to init/start a local instance so `pixi run dev` and `pixi run test` keep working with no external service to install by hand (no Docker).
- One-time data migration: a script that copies existing rows from `data/products.db` (601 products, 166 categories as of this change) into the new Postgres database, run once during rollout.
- Update `test_db.mojo` (and any other DB-touching tests) to run against the pixi-managed local Postgres instead of a disposable `tempfile.mkstemp()` SQLite file — tests use a dedicated test database/schema that's truncated between runs instead of a deleted temp file.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None — this is a storage-engine swap. Every existing requirement in `product-extraction`, `category-discovery`, and `product-browsing` is preserved unchanged (verified by the existing Mojo test suite passing against Postgres, plus the `ILIKE` adjustment called out above to keep the case-insensitive search requirement true). No spec file references SQLite or any storage technology, so no delta spec is needed; `skip_specs: true` is set on this change.

## Impact

- **Code**: `backend/mojo_src/db.mojo` (full rewrite of `connect`, `SCHEMA`, both upsert functions, all placeholder styles); `backend/server.py` (`DB_PATH` → Postgres connection config); `backend/mojo_src/tests/test_db.mojo` (setup/teardown against Postgres).
- **Dependencies**: adds `psycopg2` (or `psycopg`) and `postgresql` to `pixi.toml` — the project's first third-party Python dependency for storage, and its first dependency requiring a running service rather than a stdlib call.
- **Dev workflow**: `pixi run dev` / `pixi run serve` / `pixi run test` now depend on a local Postgres instance being initialized and running (new pixi task(s) handle this); no more zero-setup single-file database.
- **Data**: existing `data/products.db` is migrated once via a new script, then left in place untouched (not deleted) as a backup.
- **Config**: new environment variables for Postgres connection (host/port/dbname/user/password), with sensible local-dev defaults so `pixi run dev` works out of the box against the pixi-managed instance.
