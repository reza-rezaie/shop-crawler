## Context

See `proposal.md` - Why/What Changes for motivation and scope (backend-only,
no behavior change, `db.mojo` stays a single shared module — both confirmed
with the user).

Original `backend/mojo_src/` was flat, one file per technical concern, with
a dependency graph traced directly from the source (`from <module> import
...` lines):

```
models.mojo        (no internal deps)
pricing.mojo        (no internal deps)                    -- used only by html_extract.mojo
textutil.mojo        (no internal deps)                    -- used by html_extract, category_discovery, db
http_client.mojo      (no internal deps)                    -- used by browser_client, crawler, category_discovery, db, html_extract
browser_client.mojo    (-> http_client)                       -- used by crawler, category_discovery
db.mojo                (-> models, http_client, textutil)      -- used by api, crawler, category_discovery
html_extract.mojo        (-> models, pricing, http_client, textutil) -- used by crawler AND category_discovery
crawler.mojo               (-> models, http_client, browser_client, html_extract, db)
category_discovery.mojo      (-> http_client, browser_client, html_extract, textutil, db)
api.mojo                       (-> db, models, crawler, category_discovery)  -- PyInit_api, single Python-extension entry point
```

Three things fall out of this graph that shape the design:

1. `models`, `http_client`, `browser_client`, `textutil`, `db` are already
   used by more than one feature — they're the real shared kernel, not
   slice-owned code.
2. `html_extract.mojo` is **not** purely product-extraction logic. Of its
   nine public functions, `crawler.mojo` uses all nine but
   `category_discovery.mojo` also uses four of them
   (`extract_json_ld_products`, `extract_heuristic_products`,
   `looks_like_not_found_page`, `looks_like_client_rendered_app`,
   `find_next_page_url` — page-level signals: "does this page have
   products / look client-rendered / look like a 404 / have a next page"),
   not because category discovery extracts products, but because it needs
   the same "is this a real, rendered listing page" signals crawling does.
   Moving the whole file into a `product_extraction` module as-is would
   make `category_discovery` import from `product_extraction`'s internals —
   a module-to-module dependency, exactly what vertical-slice structuring
   is meant to avoid.
3. `db.mojo` and `textutil.mojo` are the two files whose names don't
   describe what they contain once read outside their original flat
   directory (an abbreviation, and a squashed compound word inconsistent
   with the project's own `html_extract.mojo`/`http_client.mojo` naming) —
   flagged directly by the user, see Decision 1.

Mojo v1.0 GA has no `mojo test`; `scripts/run_tests.sh` shell-loops
`mojo run -I <src-root> <src-root>/tests/test_*.mojo` over every test file,
and `mojo.importer` (invoked from `backend/server.py`) compiles `api.mojo`
and everything it transitively imports into one native Python extension at
process start. Both are single-root, `-I`-flag-based module resolution —
confirmed live in this migration (see task 1, the spike) that Mojo resolves
subdirectories as packages via an `__init__.mojo` marker file per directory
(same convention as Python), including multi-level nesting (`from
modules.product_extraction.crawler import crawl` resolves the same way
`from core.models import Product` does), so one `-I <src-root>` flag covers
the whole tree regardless of nesting depth.

## Goals / Non-Goals

**Goals:**
- A target module layout where each `openspec/specs/` capability
  (`product-extraction`, `category-discovery`, `product-browsing`) maps to
  exactly one directory it owns, containing its own request handling,
  business logic, and (where genuinely slice-local) data shaping.
- A `core/` kernel holding only code more than one slice actually imports
  today, verified from the dependency graph above — not a guess.
- The modular-monolith structure is visible in the directory tree itself:
  the three vertical-slice modules live under one `modules/` parent
  (distinct from `core/`, which is shared kernel, not a module), and the
  two most-abbreviated/inconsistent filenames are spelled out — confirmed
  with the user (see Decision 1).
- Zero behavior change: same HTTP contract, same DB schema/queries, same
  crawl/discovery/browsing semantics.
- A migration that can be committed and reverted slice-by-slice, so a
  compilation break narrows to one commit.

**Non-Goals:**
- Splitting `db.mojo`/`database.mojo` per slice (explicitly declined by the
  user — single shared Postgres access module in `core/`).
- Any frontend restructuring, or renaming `scripts/`, `pixi.toml` task
  names, or any top-level directory other than `backend/mojo_src/` itself
  — explicitly out of scope, confirmed with the user.
- Changing `backend/server.py`'s routing, the `/api/*` contract, or the DB
  schema.
- Introducing a plugin/DI framework, a new build system, or per-module
  compiled artifacts — this is a directory/import/naming reorganization
  within the existing single `PyInit_api` extension module, not a new
  architecture runtime.

## Decisions

**1. Rename the Mojo source root `backend/mojo_src/` → `backend/src/`, and
group the three vertical-slice modules under `backend/src/modules/`, with
`core/` as a sibling (shared kernel, explicitly not itself a "module").**
Confirmed with the user in two rounds: first that `mojo_src` reads as an
unconventional root name next to `backend/server.py` and `frontend/`
(`src/` is the idiomatic choice), then — separately — that a "modular
monolith" should make its modules visible in the tree rather than have
slice directories sit flush next to the shared kernel, indistinguishable
from it. Target root layout:

```
backend/src/
├── api.mojo                  # PyInit_api wiring only
├── core/                      # shared kernel (not a module)
│   ├── models.mojo
│   ├── http_client.mojo
│   ├── browser_client.mojo
│   ├── text_utils.mojo
│   ├── database.mojo
│   ├── page_signals.mojo
│   └── request.mojo
├── modules/
│   ├── product_extraction/
│   │   ├── crawler.mojo
│   │   ├── extraction.mojo
│   │   └── pricing.mojo
│   ├── category_discovery/
│   │   └── discovery.mojo
│   └── product_browsing/
│       └── browsing.mojo
└── tests/
    ├── core/
    └── modules/
        ├── product_extraction/
        ├── category_discovery/
        └── product_browsing/
```

Alternative considered: leave the root named `mojo_src` and/or leave the
three slice directories flush under it (no `modules/` parent). Rejected on
direct user feedback both times — the whole point of this change is that
the directory tree should read as a modular monolith at a glance, not just
be one internally.

**2. `core/` holds exactly the seven modules the dependency graph (plus
Decisions 3 and 7) shows are multi-slice or otherwise not owned by one
feature: `models.mojo`, `http_client.mojo`, `browser_client.mojo`,
`text_utils.mojo` (renamed from `textutil.mojo`), `database.mojo` (renamed
from `db.mojo`), `page_signals.mojo` (new, Decision 4), `request.mojo`
(new, Decision 8).** `database.mojo`/`text_utils.mojo` are the two renames
confirmed with the user — abbreviation spelled out, and underscore-joined
to match the project's other multi-word filenames (`html_extract.mojo`,
`http_client.mojo`) — every other `core/` filename already read clearly
enough on their own to leave alone. Alternative considered: put
`text_utils.mojo` inside `modules/product_extraction/` (its biggest caller,
`extraction.mojo`, lives there) and re-export what `category_discovery`/
`database` need. Rejected — that recreates the module-to-module import
problem the `html_extract` split (Decision 4) is meant to fix, for a module
that's already generic string/HTML utilities with no product-specific
content.

**3. `product_extraction`, `category_discovery`, `product_browsing`
directory *names* stay exactly as already chosen** (matching the
`openspec/specs/` capability names — see the original Decision 1
rationale, unchanged); only their location moves one level deeper, under
`modules/` (Decision 1).

**4. Split `html_extract.mojo` into two files along its real seam:**
   - `modules/product_extraction/extraction.mojo` — product-specific
     extraction: `extract_json_ld_products`, `extract_heuristic_products`,
     `extract_breadcrumb_category`, `extract_last_breadcrumb_items`,
     `extract_product_description`, plus their private helpers
     (`_collect_products_from_jsonld`, `_product_from_block`,
     `_find_price_text`, `_candidate_tags`).
   - `core/page_signals.mojo` — generic listing-page signals used by both
     `crawler.mojo` and `category_discovery`: `looks_like_client_rendered_app`,
     `looks_like_not_found_page`, `find_next_page_url`, `find_child_links`,
     plus `_spa_shell_markers`.

   Alternative considered: leave `html_extract.mojo` intact under
   `modules/product_extraction/` and let `category_discovery` import it
   directly. Rejected per the Context above — it's the one place a naive
   move would silently create a module-to-module dependency instead of a
   shared-kernel one; splitting it now keeps every module's imports
   pointing only at `core/` or its own files, never at a sibling module.

**5. Verify the package-import mechanism with a one-file spike before the
full migration** — done (task 1, completed): `from core.models import
Product` resolved correctly under the existing `-I backend/mojo_src` flag
(pre-root-rename) with a `core/__init__.mojo` marker, confirming
`__init__.mojo`-based subdirectory packages work in this Mojo v1.0 GA
toolchain, including the deeper `modules/<name>/` nesting added by
Decision 1.

**6. `product_browsing` gets a real module file
(`modules/product_browsing/browsing.mojo`)** even though today its logic
lives inline in `api.mojo` as thin wrappers (`list_products`, `categories`,
`sources`, `site_categories`) around `database.mojo` query functions.
Moving them out of `api.mojo` and into the module is what makes
`product_browsing` a real, visible module instead of an implicit one —
otherwise two of three capabilities would have owned code and one would
exist only as spec + DB queries.

**7. `health`, `migrate_products`, `migrate_site_categories` stay in
`api.mojo`** (not moved into any module). They aren't feature request
handling — `health` is generic liveness/row-count, and `migrate_*` is a
one-time SQLite→Postgres migration utility (`scripts/migrate_sqlite_to_postgres.py`)
that calls `core/database.mojo`'s upsert functions directly. Forcing them
into a module would misrepresent what they are; `api.mojo` keeping a
handful of non-module admin handlers alongside pure wiring is consistent
with it being the Python-extension boundary, not a module itself.

**8. Request-parsing helpers (`_get_str`, `_get_int`, `_get_bool`,
`_get_obj`, `_get_optional_float`) move to `core/request.mojo`.** Every
module's handler needs them once handlers move out of `api.mojo`, so
they're shared-kernel by the same test as Decision 2, not something to
duplicate per module.

## Risks / Trade-offs

- **[Risk] Mojo subdirectory/package import resolution behaves differently
  than assumed (Decision 5), breaking `mojo.importer` compilation or
  `scripts/run_tests.sh`'s `-I` flag.** → Resolved: the spike (task 1)
  confirmed it works; the deeper `modules/<name>/` nesting from Decision 1
  uses the identical mechanism, re-verified when `pixi run test` is run
  after the first module lands under `modules/` (task group 4).
- **[Risk] Splitting `html_extract.mojo` (Decision 4) touches the file with
  the most callers in the codebase — highest chance of an import path typo
  breaking compilation.** → Mitigation: do this split as its own commit
  with `pixi run test` run immediately after, before touching `crawler.mojo`
  or `category_discovery.mojo`'s own locations (see tasks.md ordering).
- **[Trade-off] `core/` ends up moderately large relative to each module**
  (7 of roughly 14 files) because this is a small POC where HTTP
  fetch/render/DB access genuinely are shared by every feature. Accepted —
  right-sized for this codebase; not a sign the module split is wrong, just
  that the "vertical" part of each module here is business logic, not
  infrastructure.
- **[Risk] `pixi.toml` task definitions or other scripts reference
  `backend/mojo_src/<file>.mojo` paths that this change moves/renames —
  now a larger set of references since the root itself is renamed.** →
  Mitigation: `grep -rn 'mojo_src' --include='*.toml' --include='*.sh'
  --include='*.py' --include='*.md'` across the repo as an explicit task
  (tasks.md), not just updating the files whose moves are obvious from the
  design. Since `pixi.toml` task *names* stay unchanged (only the paths
  inside their command strings change), the renamed root cannot be missed
  by grepping for the literal string `mojo_src`.

## Migration Plan

Incremental, one module (or shared-file group) per commit, `pixi run test`
green after every commit — see `tasks.md` for the concrete step list.
Updated order (root/file renames pulled forward, before the modules that
would otherwise need touching twice):

1. Spike: prove subdirectory package imports work (Decision 5) — done.
2. Move the (then five, now seven counting later additions) shared modules
   into `core/`, including the `database.mojo`/`text_utils.mojo` renames
   (Decision 2) — done for the five original modules; renames still
   pending.
3. Rename the source root `backend/mojo_src/` → `backend/src/` (Decision
   1) and sweep every reference (Mojo imports already point at `core.*`/
   future `modules.*`, which don't encode the root name — the sweep is for
   `pixi.toml`, `scripts/run_tests.sh`, `README.md`, `SPEC.md`, and
   `mojo.importer`'s call site if it hardcodes a path).
4. Split `html_extract.mojo` (Decision 4) into `core/page_signals.mojo` +
   `modules/product_extraction/extraction.mojo`; update `crawler.mojo` and
   `category_discovery.mojo` imports.
5. Move `crawler.mojo` + `pricing.mojo` into `modules/product_extraction/`.
6. Move `category_discovery.mojo` into
   `modules/category_discovery/discovery.mojo`.
7. Extract `modules/product_browsing/browsing.mojo` out of `api.mojo`
   (Decision 6); add `core/request.mojo` (Decision 8) and update every
   handler to import it instead of using `api.mojo`'s private helpers.
8. Slim `api.mojo` down to `PyInit_api` wiring + the admin handlers
   (Decision 7); mirror `backend/src/tests/` into per-module test
   directories under `tests/modules/`; final repo-wide path sweep.

No rollback strategy beyond standard git revert is needed — this is a
same-behavior internal refactor with no data migration, no deployed state,
and no external contract change; reverting a commit at any step restores a
working, tested state.

## Open Questions

None — Decision 5 covers the one real technical unknown (package-import
mechanics) with a spike that has already run and confirmed the approach,
including for the deeper `modules/` nesting added by Decision 1.
