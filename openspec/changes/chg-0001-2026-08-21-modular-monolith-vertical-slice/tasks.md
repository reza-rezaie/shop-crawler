## 1. Spike: verify package-import mechanics (Decision 5)

- [x] 1.1 On a throwaway branch/dir, create one `__init__.mojo`-marked
      subdirectory under `backend/mojo_src/` (e.g. move only
      `models.mojo` into `core/models.mojo`) and update its one importer
      (`db.mojo`'s `from models import Product`) to `from core.models import Product`.
- [x] 1.2 Run `mojo run -I backend/mojo_src backend/mojo_src/tests/test_db.mojo`
      (or the smallest affected test file) to confirm the dotted
      subdirectory import resolves under the existing `-I` flag.
      Confirmed working — all test_db.mojo assertions passed with
      `core.models` import.
- [x] 1.3 If it does not resolve as expected, fall back to flat prefixed
      filenames instead of subdirectories for the rest of this migration.
      N/A — subdirectory packages work as designed.
- [x] 1.4 Revert the throwaway move (or keep it — it's step 2.1 either way)
      once the mechanism is confirmed. Kept — folds into step 2.1.

## 2. Move shared kernel into `core/` (Decision 2)

- [x] 2.1 Create `backend/mojo_src/core/__init__.mojo` and move
      `models.mojo`, `http_client.mojo`, `browser_client.mojo`,
      `textutil.mojo`, `db.mojo` into it, unchanged apart from their new
      path. Done (renames to `database.mojo`/`text_utils.mojo` are 2.5/2.6
      below, added after the naming pass was confirmed with the user).
- [x] 2.2 Update every `from <module> import ...` across the tree
      (`api.mojo`, `crawler.mojo`, `category_discovery.mojo`,
      `html_extract.mojo`) to the new `core.<module>` paths.
- [x] 2.3 Update `backend/mojo_src/tests/test_db.mojo`,
      `test_textutil.mojo`, `test_url_paths.mojo`,
      `test_js_rendered_extraction.mojo` imports to match.
- [x] 2.4 Run `pixi run test`; fix any import-path breakage before
      continuing. All suites passed (exit code 0).
- [x] 2.5 Rename `core/db.mojo` → `core/database.mojo`; update every
      importer (`api.mojo`, `crawler.mojo`, `category_discovery.mojo`,
      `tests/test_db.mojo`) from `core.db` to `core.database`.
- [x] 2.6 Rename `core/textutil.mojo` → `core/text_utils.mojo`; update
      every importer (`core/database.mojo`, `html_extract.mojo`,
      `category_discovery.mojo`, `tests/test_textutil.mojo`,
      `tests/test_url_paths.mojo`, `tests/test_js_rendered_extraction.mojo`)
      from `core.textutil` to `core.text_utils`.
- [x] 2.7 Run `pixi run test`; fix any breakage before continuing. Full
      suite passed (exit code 0).

## 3. Rename source root `backend/mojo_src/` → `backend/src/` (Decision 1)

- [x] 3.1 `git mv backend/mojo_src backend/src`.
- [x] 3.2 Update `scripts/run_tests.sh`'s `-I backend/mojo_src` /
      `backend/mojo_src/tests/test_*.mojo` references to `backend/src/...`.
- [x] 3.3 Update `pixi.toml` for any `backend/mojo_src` path reference
      (task command strings only — task *names* stay unchanged, e.g. the
      `test` task keeps its name).
- [x] 3.4 Update `backend/server.py`'s `mojo.importer` invocation if it
      hardcodes `mojo_src` anywhere (e.g. an `-I`-equivalent import path
      or `sys.path` entry), and any other `.py` reference. Also updated
      `scripts/migrate_sqlite_to_postgres.py`'s equivalent path.
- [x] 3.5 `grep -rn 'mojo_src'` across the repo to catch anything else
      (README.md, SPEC.md, comments) — note stragglers for task 8.4's full
      sweep rather than fixing docs prose here. Found and fixed a real bug
      this surfaced: 7 test files under `tests/` hardcoded
      `"backend/mojo_src/tests/fixtures/..."` as a runtime file-open path
      string (not a Mojo import), which `pixi run test` caught failing at
      runtime — fixed by sweeping `mojo_src` → `src` across
      `backend/src/tests/*.mojo`. README.md/SPEC.md prose left for 8.7.
- [x] 3.6 Run `pixi run test`; fix any breakage before continuing. Full
      suite passed, 108/108 assertions, 0 errors.

## 4. Split `html_extract.mojo` (Decision 4)

- [x] 4.1 Create `backend/src/core/page_signals.mojo` containing
      `looks_like_client_rendered_app`, `looks_like_not_found_page`,
      `find_next_page_url`, `find_child_links`, `_spa_shell_markers`
      (moved verbatim, imports updated to `core.` paths).
- [x] 4.2 Rename the remainder of `html_extract.mojo` to
      `backend/src/modules/product_extraction/extraction.mojo` (created
      `modules/__init__.mojo` and `modules/product_extraction/__init__.mojo`
      early, pulled forward from task 5.1, since extraction.mojo needed a
      home): `extract_json_ld_products`, `extract_heuristic_products`,
      `extract_breadcrumb_category`, `extract_last_breadcrumb_items`,
      `extract_product_description`, `_collect_products_from_jsonld`,
      `_product_from_block`, `_find_price_text`, `_candidate_tags`. Also
      moved `pricing.mojo` → `modules/product_extraction/pricing.mojo`
      (pulled forward from 5.2) since extraction.mojo imports it.
- [x] 4.3 Update `crawler.mojo` and `category_discovery.mojo` imports to
      pull page-signal functions from `core.page_signals` and
      product-extraction functions from
      `modules.product_extraction.extraction`. Also fixed stale
      `textutil.`/`html_extract.` prose references in both files' own
      comments (predating this session's renames) while touching them.
- [x] 4.4 Split `backend/src/tests/test_html_extract.mojo` into the tests
      that belong with each half (or duplicate the file temporarily and
      prune) so assertions still map 1:1 to the functions they test. Its
      one test (`looks_like_client_rendered_app`) is 100% page_signals
      content, so renamed the whole file to `test_page_signals.mojo`
      rather than splitting; also renamed `test_textutil.mojo` →
      `test_text_utils.mojo` and `test_db.mojo` → `test_database.mojo` to
      track their renamed modules, and repointed
      `test_js_rendered_extraction.mojo`/`test_category_drill_down.mojo`
      imports to their functions' new homes.
- [x] 4.5 Run `pixi run test`; fix any breakage before continuing. Full
      suite passed, 108/108 assertions, 0 errors.

## 5. Relocate `product_extraction` module

- [x] 5.1 Create `backend/src/modules/__init__.mojo` and
      `backend/src/modules/product_extraction/__init__.mojo`. Done early
      in group 4 (task 4.2) since `extraction.mojo` needed a home then.
- [x] 5.2 Move `pricing.mojo` into
      `modules/product_extraction/pricing.mojo`. Done early in group 4
      (task 4.2) since `extraction.mojo` imports it.
- [x] 5.3 Move `crawler.mojo` into `modules/product_extraction/crawler.mojo`;
      update its imports (`core.*`,
      `modules.product_extraction.extraction`,
      `modules.product_extraction.pricing` via `extraction.mojo`'s own
      import). crawler.mojo's own imports already pointed at `core.*`/
      `modules.product_extraction.extraction` from group 4, so the move
      itself needed no import changes.
- [x] 5.4 Update `api.mojo`'s `from crawler import crawl as run_crawl` to
      `from modules.product_extraction.crawler import crawl as run_crawl`.
- [x] 5.5 Move/update `backend/src/tests/test_js_rendered_extraction.mojo`
      and any other crawler-focused test file's imports. No test imports
      `crawler.mojo` directly (it tests the extraction functions, already
      repointed in group 4) — confirmed via grep, nothing to change.
- [x] 5.6 Run `pixi run test`; fix any breakage before continuing. Full
      suite passed, 108/108 assertions, 0 errors.

## 6. Relocate `category_discovery` module

- [x] 6.1 Create `backend/src/modules/category_discovery/__init__.mojo`.
- [x] 6.2 Move `category_discovery.mojo` into
      `modules/category_discovery/discovery.mojo`; update its imports
      (`core.*`, `modules.product_extraction.extraction` for the
      product-specific functions it uses). Already pointed at those from
      group 4 — the move itself needed no import changes; also fixed two
      stale `textutil.` comment references predating this session while
      touching the file.
- [x] 6.3 Update `api.mojo`'s `from category_discovery import
      discover_categories as run_discover_categories` to `from
      modules.category_discovery.discovery import discover_categories as
      run_discover_categories`.
- [x] 6.4 Update `backend/src/tests/test_category_discovery.mojo` and
      `test_category_drill_down.mojo` imports.
      `test_category_drill_down.mojo` had no `category_discovery` import
      (only `core.page_signals`, from group 4) — nothing to change there.
- [x] 6.5 Run `pixi run test`; fix any breakage before continuing. Full
      suite passed, 108/108 assertions, 0 errors.

## 7. Extract `product_browsing` module + `core/request.mojo` (Decisions 6, 8)

- [ ] 7.1 Create `backend/src/core/request.mojo` containing `_get_str`,
      `_get_int`, `_get_bool`, `_get_obj`, `_get_optional_float` (moved
      verbatim from `api.mojo`, made non-private if needed for cross-module
      use).
- [ ] 7.2 Create `backend/src/modules/product_browsing/__init__.mojo` and
      `modules/product_browsing/browsing.mojo` containing the
      request-handling logic currently inline in `api.mojo`'s
      `list_products`, `categories`, `sources`, `site_categories`
      functions (parsing params via `core.request`, calling
      `core.database`'s
      `query_products`/`list_categories`/`list_sources`/`list_site_categories`).
- [ ] 7.3 Update `api.mojo`'s `PyInit_api` registrations for
      `list_products`, `categories`, `sources`, `site_categories` to point
      at the new `modules.product_browsing.browsing` functions; remove the
      old inline bodies.
- [ ] 7.4 Update `crawl` and `discover_categories` handlers in `api.mojo`
      to use `core.request`'s helpers instead of the local private ones
      removed in 7.1.
- [ ] 7.5 Run `pixi run test`; fix any breakage before continuing.

## 8. Finish `api.mojo`, tests layout, and repo-wide path/naming sweep

- [ ] 8.1 Confirm `api.mojo` now contains only `PyInit_api` wiring plus
      `health`, `migrate_products`, `migrate_site_categories` (Decision 7)
      — no module business logic left inline.
- [ ] 8.2 Reorganize `backend/src/tests/` into `tests/core/` and
      `tests/modules/<name>/` mirroring `backend/src/core/` and
      `backend/src/modules/*` (keep `testing.mojo` and `fixtures/` shared
      at the top of `tests/`).
- [ ] 8.3 Update `scripts/run_tests.sh`'s test-file glob if the
      reorganization in 8.2 changes how `test_*.mojo` files are
      discovered (e.g. switch to a recursive find if tests now live in
      subdirectories).
- [ ] 8.4 `grep -rn 'mojo_src\|core\.db\b\|core\.textutil\b'
      --include='*.toml' --include='*.sh' --include='*.py'
      --include='*.md'` across the repo (pixi.toml, scripts/,
      backend/server.py, README.md, SPEC.md) and update any leftover path
      or naming reference broken by the moves/renames.
- [ ] 8.5 Run `pixi run test` (full suite) one final time.
- [ ] 8.6 Manual smoke check: `pixi run serve`, then crawl
      `https://books.toscrape.com/` from the UI (or `pixi run crawl --
      https://books.toscrape.com/`) and confirm products are
      created/updated, browsing/filtering still works, and a category
      discovery run still populates `site_categories` — matching
      pre-refactor behavior with no code-level comparison needed since
      the DB/HTTP contract didn't change.
- [ ] 8.7 Update `SPEC.md` §1 (architecture diagram / file list) and
      `README.md`'s directory listing to reflect the new `backend/src/`
      layout (including the `modules/` grouping and renamed files).
