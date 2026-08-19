## Context

All storage lives in one file, `backend/mojo_src/db.mojo`: a `SCHEMA` string, `connect()`, and every query (`upsert_product`, `upsert_site_category`, `query_products`, `list_categories`, `list_sources`, `list_site_categories`, `count_products`). It reaches SQLite through Python interop (`Python.import_module("sqlite3")`) since Mojo has no native driver — the same interop pattern will be used for Postgres via `psycopg2`. `db.mojo` is called from `api.mojo`, which opens a fresh connection per request (`connect(db_path)` in each of `health`, `crawl`, `discover_categories`, `site_categories`, `list_products`, `categories`, `sources`); `server.py` owns the single `DB_PATH` constant that flows into all of them. See `proposal.md` - Why for the motivation.

## Goals / Non-Goals

**Goals:**
- Preserve every existing requirement/behavior exactly (case-insensitive search, upsert dedup, `has_own_products` COALESCE semantics, host scoping) while swapping the engine.
- Keep local dev/test friction close to today's zero-setup story via a pixi-managed Postgres (no Docker, no manual install step).
- Make upserts atomic (`ON CONFLICT DO UPDATE`), removing the current SELECT-then-INSERT/UPDATE race window.
- Migrate the existing 601 products / 166 categories once, without data loss.

**Non-Goals:**
- Supporting both SQLite and Postgres side by side. This is a full switch; no dual-driver abstraction.
- Connection pooling or performance tuning beyond "open a connection per request" (matches today's pattern; revisit only if it becomes a measured problem).
- Deploying to a managed/hosted Postgres (Azure Database for Postgres, RDS, etc.). Env-var-based config leaves that door open for a future change, but provisioning one is out of scope here.
- Any schema redesign beyond what the Postgres dialect requires (no new tables/columns, no normalization changes).

## Decisions

**Driver: `psycopg2` over `psycopg` (v3).** `psycopg2` is the long-established, conda-forge-packaged option and is a closer drop-in for the current `sqlite3`-via-interop pattern (synchronous, simple `connect()`/`cursor()`/`execute()` API). `psycopg` (v3) adds async support and a few modern conveniences the project has no use for. Stick with `psycopg2`.

**Row access: `psycopg2.extras.RealDictCursor`.** The current code relies on `sqlite3.Row`'s dict-style `row["col"]` access throughout `db.mojo`. Setting the cursor factory to `RealDictCursor` at `connect()` time keeps every `row["..."]` call in the file unchanged — the only touch point is inside `connect()` itself.

**Local Postgres via pixi, not Docker.** Add conda-forge's `postgresql` package as a pixi dependency (gives `initdb`, `pg_ctl`, `psql`) and a small `scripts/pg_local.sh` (mirroring the existing `scripts/dev_server.sh` / `scripts/activate.sh` pattern) that idempotently initializes a data directory under `data/pgdata/` (gitignored) and starts/stops a local instance on a fixed, non-default port (avoiding clashes with any system-wide Postgres, same reasoning as `pixi run dev`'s fixed port 8934). `pixi run dev`, `pixi run serve`, and `pixi run test` each ensure the local instance is running before doing their own work, so the one-command story survives.

**Connection config via standard libpq env vars.** Use `PGHOST` / `PGPORT` / `PGDATABASE` / `PGUSER` / `PGPASSWORD` — `psycopg2.connect()` picks these up with no arguments needed, and they're the same names `psql`/`pg_ctl` already understand. Defaults point at the pixi-managed local instance so `pixi run dev` works with no `.env` file required; overriding them is how a future change would point at a managed instance.

**Schema: native types over SQLite workarounds.** `id` columns become `GENERATED ALWAYS AS IDENTITY PRIMARY KEY` (replacing `INTEGER PRIMARY KEY AUTOINCREMENT`). `has_own_products` becomes a native nullable `BOOLEAN` (replacing the `INTEGER`-as-tristate representation `_none_or_bool_as_int` existed only to work around) — Postgres has real nullable booleans, so the workaround and its comment go away; call sites that currently do `Int(String(row["has_own_products"])) == 1` compare against the boolean directly instead. `CREATE INDEX IF NOT EXISTS` is unchanged (Postgres supports it too).

**Upserts: `INSERT ... ON CONFLICT DO UPDATE`, with the insert/update outcome read from `xmax`.** Replaces the current SELECT-then-INSERT-or-UPDATE with one atomic statement per upsert, keyed on `product_url` / `url` respectively (both already `UNIQUE`). To keep returning `UpsertOutcome.created` (used by callers to report "N new, M updated") without a second round-trip, use the standard Postgres idiom `RETURNING (xmax = 0) AS inserted` — `xmax = 0` on the returned row means the statement inserted a fresh row rather than updating an existing one. This is a lesser-known idiom, so it gets a clear comment at the call site, same doc-density as the rest of `db.mojo`. `COALESCE(EXCLUDED.col, target.col)` reproduces the existing "don't blank out a field we already had" and "don't downgrade a known `has_own_products` back to unknown" semantics.

**Search: `ILIKE` instead of `LIKE`.** SQLite's `LIKE` is case-insensitive by default for ASCII; Postgres's is case-sensitive. `product-browsing`'s "Search and filter" requirement is explicitly case-insensitive, so `query_products`'s name search switches to `ILIKE` to keep that requirement true without changing the requirement itself.

**Migration: one-off script, fresh IDs, via two new `api.mojo` entrypoints.** A plain Python script can't construct a native Mojo `Product` struct directly — only a function exposed through `PythonModuleBuilder` (the same mechanism `api.mojo` already uses for `crawl` et al.) can accept Python-level data and build one. So `api.mojo` gains `migrate_products` / `migrate_site_categories`, each taking a plain list of Python dicts and calling `upsert_product` / `upsert_site_category` per row — the actual, real upsert code, not a reimplementation. `scripts/migrate_sqlite_to_postgres.py` opens the existing `data/products.db` read-only via stdlib `sqlite3`, reads `products` and `site_categories` in `id ASC` order as dicts, and hands them to those two entrypoints (imported the same way `server.py` imports `api`, via `mojo.importer`) — so migration exercises the exact same dedup/COALESCE code the app uses, and reruns are safe/idempotent. Postgres assigns fresh identity values rather than preserving the original SQLite `id`s — checked against the frontend (`App.jsx` uses `product.id` / `node.id` only as a React list `key`, never persisted or linked externally), so renumbering is safe. `upsert_product`/`upsert_site_category` always stamp `first_seen_at`/`last_seen_at` with "now" (correct for a live crawl); the migration script restores the original SQLite timestamps afterward with one direct `UPDATE ... WHERE product_url = %s` pass per table, keyed by URL. The original `data/products.db` file is left untouched on disk afterward, serving as a backup. Verified against the real data: 601 products / 166 categories in, exact match, timestamps and NULL fields intact.

**Tests: dedicated Postgres test database, not a temp file.** `test_db.mojo` (and any other DB-touching test) currently creates an isolated SQLite file per run via `tempfile.mkstemp()` and deletes it after. With Postgres, tests instead connect to a separate database (e.g. `products_test`, created by the same local-instance init step) and `TRUNCATE` the tables at the start of the run instead of deleting a file at the end — same isolation guarantee (each run starts empty), different mechanism.

## Risks / Trade-offs

- [Risk] Losing the "just a file, zero setup" story raises the bar for running the project locally → [Mitigation] pixi tasks make Postgres init/start automatic and idempotent, so `pixi run dev` / `pixi run test` remain one command; document the change in README.
- [Risk] `xmax = 0` is a non-obvious Postgres idiom, easy to trip over in review or future edits → [Mitigation] comment it clearly at both call sites; covered by `test_db.mojo`'s existing "re-upserting doesn't duplicate" assertions.
- [Risk] `ILIKE`'s Unicode case-folding rules can differ subtly from SQLite's ASCII-only default casing in exotic non-ASCII names → [Mitigation] accepted deviation; the documented requirement (case-insensitive ASCII substring search) stays verified by tests, exotic Unicode casing was never a tested guarantee.
- [Risk] Migration run against a `data/products.db` that's mid-write (server still running a crawl) could copy a partial state → [Mitigation] migration is a one-time, manual step documented as "stop the server first"; it's also safely rerunnable since it goes through the same idempotent upsert path.
- **[Discovered during implementation]** conda-forge's `postgresql`/`libpq` 18.x build links `liburing` (Postgres 18 added io_uring-based AIO support). `liburing`'s mere presence in the pixi environment — even completely unused — segfaults Mojo's compiled Python-extension-module loading (`import mojo.importer; import api`, the exact mechanism `server.py` and the migration script both depend on), reproducible on the fully unmodified pre-change codebase with only `postgresql`/`psycopg2` added as dependencies. Confirmed by bisecting the dependency tree (`postgresql`/`libpq` 18.x → crash; `postgresql`/`libpq` 17.x → no crash, no `liburing`) in an isolated worktree. → **Resolution**: `pixi.toml` pins `postgresql = ">=17,<18"`. Revisit this pin — and re-run this same bisection — if a future `postgresql`/`libpq` build drops `liburing` or makes it opt-in.

## Migration Plan

1. Add `psycopg2` + `postgresql` to `pixi.toml`; add `scripts/pg_local.sh` and wire it into `pixi run dev` / `serve` / `test`.
2. Rewrite `db.mojo`: schema, `connect()`, both upserts (`ON CONFLICT` + `xmax` trick), `query_products`'s `ILIKE`, and the `has_own_products` boolean call sites.
3. Update `server.py`: replace `DB_PATH` with env-var-sourced Postgres connection config (with local-dev defaults).
4. Update `test_db.mojo` to run against the local test database (truncate-based setup/teardown); run the full `pixi run test` suite and confirm all existing checks still pass unmodified in intent.
5. Write `scripts/migrate_sqlite_to_postgres.py`; run it once against `data/products.db`; verify migrated counts match source (601 products, 166 categories) and spot-check a few rows (including a `has_own_products = NULL` row and a re-crawled/updated row) via the running app.
6. Update `README.md` / `SPEC.md`'s storage section to describe Postgres instead of SQLite.
7. **Rollback**: this is a local dev tool with no production deployment; rollback is reverting the branch/PR. `data/products.db` is left untouched throughout, so no data is at risk even if the migration or rollout is abandoned partway.

Resolved during implementation: local instance listens on `127.0.0.1:5544` (TCP only, no unix socket — sidesteps its path-length limit inside a nested project directory), data directory `data/pgdata/` (gitignored), both hardcoded as matching defaults in `scripts/pg_local.sh` and `scripts/activate.sh` so they can never drift apart.
