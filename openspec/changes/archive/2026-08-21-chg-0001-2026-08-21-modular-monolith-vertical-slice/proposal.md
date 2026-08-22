## Why

The backend (`backend/mojo_src/`) is organized by technical layer, not by
feature: `db.mojo` holds every table's queries in one file, `api.mojo` is a
single `PyInit_api` entry point that wires up every endpoint across all
three features (crawling, category discovery, browsing), and
`crawler.mojo`/`category_discovery.mojo`/`html_extract.mojo` share no clear
ownership boundary with the `openspec/specs/` capabilities that already
describe the system (`category-discovery`, `product-extraction`,
`product-browsing`). As the project has grown (Postgres migration, JS
rendering, category drill-down), every one of those features has required
touching the same handful of shared files, making it hard to see which code
belongs to which capability and increasing the chance an unrelated feature
regresses when only one is touched. Restructuring into a modular monolith
with vertical slices — one module grouping per capability, each owning its
own model/logic/data-access code — aligns the code layout with the specs
that already exist and makes each capability's blast radius visible.

## What Changes

- Reorganize `backend/mojo_src/` from a flat, layer-based file list into
  per-capability slice directories, one per existing `openspec/specs/`
  capability: `product_extraction/` (crawling + HTML extraction + pricing),
  `category_discovery/`, `product_browsing/`.
- Introduce a `core/` (shared kernel) directory for genuinely cross-cutting
  code used by more than one slice: the Postgres connection/query module
  (`db.mojo`), shared domain types (`models.mojo`), and low-level HTTP
  fetch (`http_client.mojo`, `browser_client.mojo`), and generic text
  utilities (`textutil.mojo`) if more than one slice needs them.
- `db.mojo` stays a single shared module in `core/` (not split per slice) —
  confirmed with the user: all slices hit the same Postgres instance/tables,
  and splitting DB access per slice was judged higher risk for no benefit
  at this project's size.
- Keep `api.mojo`'s single `PyInit_api` export (Mojo's Python-extension
  entry point is necessarily one compiled module) but slim it down to pure
  wiring: each `m.def_function[...]` registration delegates to a function
  that now lives in its owning slice, instead of `api.mojo` containing or
  duplicating slice logic itself.
- `backend/server.py`'s HTTP routing table is unchanged (still routes
  `/api/*` to `api.<function>`); only the Mojo-side module layout changes.
- Pure internal refactor: **no behavior change**, **no API contract
  change**, **no DB schema change**, **no new features**. Frontend
  (`frontend/src/`) is explicitly out of scope for this change — confirmed
  with the user.
- Every existing test (`pixi run test`) must pass unmodified in behavior
  (test files may move/be renamed to mirror the new slice layout, but no
  test assertion changes).

## Capabilities

This is a pure internal restructuring with no spec-level (externally
observable) behavior change — `skip_specs: true` is set in this change's
`.openspec.yaml` and no `specs/` delta is included. The existing capability
specs (`category-discovery`, `product-extraction`, `product-browsing`)
remain accurate as-is; only the code layout implementing them changes. See
`design.md` for the target module structure and migration plan.

### New Capabilities
(none — no behavior change)

### Modified Capabilities
(none — no requirement changes)

## Impact

- **Code**: every file under `backend/mojo_src/` moves and/or is split;
  `backend/mojo_src/tests/` moves/renames to mirror the new layout.
  `backend/server.py` is unaffected (same `import api` / `api.<function>`
  surface). `pixi.toml` task definitions referencing `backend/mojo_src/`
  paths (e.g. the `test` task) are updated for new paths as needed.
- **APIs**: none — `/api/*` HTTP contract is unchanged.
- **Database**: none — schema, connection handling, and queries in
  `db.mojo` are relocated (to `core/`), not altered.
- **Dependencies**: none.
- **Risk**: Mojo's `mojo.importer` compiles `api.mojo` and everything it
  transitively imports into one native extension module at process start;
  moving files means updating every `from <module> import ...` path across
  the tree, so the main risk is import-path/compilation breakage, not
  runtime logic breakage. Mitigated by an incremental, slice-by-slice
  migration with `pixi run test` (and a manual smoke crawl against
  books.toscrape.com) run after each slice moves — see `design.md` and
  `tasks.md`.
