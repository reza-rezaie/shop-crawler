## Handoff — shop-crawler (Mojo Product Crawler)

**Repo:** github.com/reza-rezaie/shop-crawler | local: `/home/reza2/repo/azure-crawler2`
**Branch:** `main` (merged: **PR #5**)

### Active files
- `backend/mojo_src/db.mojo` — rewritten for Postgres: `psycopg2` + `RealDictCursor`, atomic `INSERT ... ON CONFLICT DO UPDATE` upserts (`xmax = 0` trick for insert/update detection), native nullable `BOOLEAN` for `has_own_products` (dropped the old int-as-tristate workaround), `ILIKE` for case-insensitive name search
- `backend/mojo_src/api.mojo` — new `migrate_products`/`migrate_site_categories` entrypoints (bulk-upsert from a list of Python dicts), used once by the SQLite→Postgres migration script
- `backend/server.py` — `DB_PATH` (SQLite file path) → `DB_NAME` (Postgres database name; connection host/port/user/password come from standard libpq env vars)
- `scripts/pg_local.sh` — new: manages the pixi-local Postgres instance (idempotent init/start/stop, no Docker)
- `scripts/migrate_sqlite_to_postgres.py` — new: one-time migration, reuses the real `upsert_product`/`upsert_site_category` code via the two new `api.mojo` entrypoints, then restores original timestamps
- `scripts/activate.sh` — now also exports `PGHOST`/`PGPORT`/`PGDATABASE`/`PGUSER`/`PG_TEST_DATABASE` defaults pointing at the pixi-managed local instance
- `scripts/dev_server.sh` — now also ensures the local Postgres instance is running before starting the backend
- `backend/mojo_src/tests/test_db.mojo` — runs against a truncated Postgres test database instead of a disposable SQLite temp file
- `pixi.toml` — adds `psycopg2` and `postgresql` (pinned `>=17,<18` — see below) deps; new `pg-start`/`pg-stop`/`db-migrate` tasks; `dev`/`serve`/`test` now ensure Postgres is up first
- `data/products.db` — old SQLite file, no longer used by the app, kept in place as a migration backup
- `data/pgdata/` — new: pixi-managed local Postgres data directory (gitignored)

### Current state
- PR #4 (category-discovery) merged to `main`.
- **PR #5 switches the catalog store from SQLite to Postgres** (`openspec/changes/archive/2026-08-19-switch-to-postgres/`) — a pure storage-engine swap, no capability spec touched (`product-extraction`/`category-discovery`/`product-browsing` requirements are all unchanged; the change declared `skip_specs: true`). One behavioral wrinkle handled explicitly: Postgres's `LIKE` is case-sensitive (SQLite's isn't), so name search switched to `ILIKE` to keep the existing case-insensitive-search requirement true.
- Local dev/test now depend on a **pixi-managed local Postgres instance** (no Docker, no manual install) — `scripts/pg_local.sh`, auto-started by `pixi run dev`/`serve`/`test`. Listens on `127.0.0.1:5544` only (TCP, no unix socket — sidesteps its path-length limit inside a nested project directory).
- **Real environment bug found and fixed**: conda-forge's `postgresql`/`libpq` **18.x** build links `liburing`; its mere presence in the pixi environment segfaults Mojo's compiled Python-extension-module loading (`import mojo.importer; import api` — the exact mechanism `server.py` runs on). Bisected to that one dependency; reproduced on the unmodified pre-change codebase too, so it's an environment/toolchain conflict, not something this change introduced. Fixed by pinning `postgresql = ">=17,<18"` in `pixi.toml`. Documented in the archived change's `design.md` and in `SPEC.md` — revisit (and re-run that bisection) only if a future `postgresql`/`libpq` build drops `liburing` or makes it opt-in.
- Existing data migrated for real: 601 products, 166 categories copied from `data/products.db` into Postgres via `pixi run db-migrate`, verified against the live HTTP API (correct NULL handling, correct `has_own_products` tri-state, original timestamps restored). `data/products.db` left untouched on disk afterward.
- `pixi run test`: 7 files, 108+ checks, all green (same suite as before, now running against real Postgres).
- Also live-smoke-tested the actual running server (`/api/health`, `/api/products`, `/api/categories`, `/api/sources`, `/api/site-categories`) against the migrated data.
- PR #5 merged to `main`; branch `feat/switch-to-postgres` deleted (local + remote). Change archived via `/opsx:archive`.
- Prior PRs #1–#4 merged; release `v0.1.0` tagged.
- Known limitations carried over unchanged from PR #4 (see prior handoff entries in git history): shallow-hub pseudo-subcategory absorption, exhaustive full-tree crawl of very large categories not feasible in one request, pagination-vs-child-link filtering is best-effort.

### Immediate next step
No PR currently in flight.

Candidate follow-ups (not started):
- Make product crawl actually *use* the discovered `site_categories` tree — e.g. let a crawl target a known leaf category directly (skip live hub rediscovery), or seed a "crawl this whole subtree" operation from known leaf URLs while still visiting any hub node flagged `has_own_products = true` (so hub-level products aren't silently skipped). Carried over from PR #4 — Postgres switch didn't touch this.
- If/when a real deployment target comes up (not just local dev), Postgres connection config is already env-var-driven (`PGHOST`/`PGPORT`/`PGDATABASE`/`PGUSER`/`PGPASSWORD`) — pointing at a managed instance instead of the pixi-local one is just overriding those vars, no code change needed.
