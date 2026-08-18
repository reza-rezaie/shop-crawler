## Handoff — shop-crawler (Mojo Product Crawler)

**Repo:** github.com/reza-rezaie/shop-crawler | local: `/home/reza2/repo/azure carwler 2`
**Branch:** `feat/category-discovery-crawl` → **PR #4**

### Active files
- `backend/mojo_src/crawler.mojo` — queue-based product crawl loop (pagination + drill-down), now also reports live progress into an optional `progress` dict param
- `backend/mojo_src/category_discovery.mojo` — new: category-tree discovery crawl (BFS over `is_child_path`-nested links, JS-rendering fallback when raw HTML has no links, best-effort pagination/fragment filtering, `has_own_products` tri-state signal)
- `backend/mojo_src/db.mojo` — `site_categories` table + `upsert_site_category`/`list_site_categories`
- `backend/mojo_src/html_extract.mojo` — `looks_like_not_found_page`, `find_child_links`, `looks_like_client_rendered_app`, `find_next_page_url`
- `backend/mojo_src/textutil.mojo` — `url_path`, `url_path_stem`, `is_child_path`, `find_all_anchor_hrefs`, `find_all_anchor_hrefs_with_text`
- `backend/mojo_src/browser_client.mojo` — Playwright JS-render fallback (shared by product crawl and discovery)
- `backend/server.py` — `/api/site-categories`, `/api/site-categories/discover`, `/api/progress` (live crawl/discovery progress, polled by the frontend)
- `frontend/src/App.jsx` — "Categories" tab (discover + browse tree) alongside the existing product-browsing view; live progress bar on both the crawl and discovery panels
- `scripts/dev_server.sh` (`pixi run dev`) — launches the app on a fixed port (8934) with the URL printed, builds the frontend first if needed
- `openspec/specs/category-discovery/spec.md` — new capability spec
- `openspec/specs/product-extraction/spec.md` — unchanged this round (product crawl behavior itself wasn't touched, only its `max_pages` hard cap and progress reporting)

### Current state
- PR #3 (category hub drill-down) merged to `main`.
- PR #4 adds: category-discovery as a first-class feature — map a site's category tree (URL/name/parent/host + whether a node shows its own products) *before* running a product crawl, browsable in a new UI tab. Discovery is deliberately lighter than a product crawl (no product/description extraction), reuses product-extraction's `is_child_path` heuristic as-is.
- Also in this PR (found/requested while building the above, bundled in rather than split out):
  - Product crawl's `max_pages` ceiling raised 20 → 500 (UI + `crawler.mojo`'s `MAX_PAGES_HARD_CAP`).
  - Live progress bars for both the product crawl and category discovery panels, via a new `GET /api/progress` polling endpoint backed by a shared mutable dict the Mojo crawl loops write into as they run.
  - `pixi run dev` convenience launcher (fixed port, avoids clashing with other local dev servers).
- Live-verified against real sites (not just fixtures) — this surfaced and fixed two real gaps before merging:
  - azurestandard.com's category nav is 100% client-rendered; discovery initially found *zero* children there. Fixed by adding a JS-rendering fallback to discovery (same mechanism product-extraction already uses), keyed off "zero links" instead of "zero products". Verified: 150 real category nodes discovered across Food, Health & Beauty, Household & Family, etc., each with correct parents.
  - Same-listing pagination links (`page-2.html` next to `index.html`) and `#fragment` variants of an already-seen link were showing up as bogus child-category nodes on server-rendered sites (books.toscrape.com). Filtered via `find_next_page_url` exclusion + fragment-stripping — the pagination filter is explicitly best-effort, not complete (documented in the archived change's design.md).
- **Known limitation (documented, not fixed):** shallow hub pages (e.g. `/shop/clearance`, one path segment deep) can still have their own item/product links absorbed as pseudo-subcategories — `is_child_path`'s path-nesting rule can't tell that apart from a real subcategory. Same root cause as the pre-existing product-extraction limitations below; no clean fix without site-specific rules.
- Also diagnosed (not a bug): the product-browsing category filter dropdown can appear empty even with products crawled — happens when every crawled product came from a page with no breadcrumb trail (e.g. azurestandard's `/shop/tag/new`, `/shop/tag/on-sale`). A real category page (e.g. anything under `/shop/category/...`) populates it correctly.
- `pixi run test`: 7 files, 108 checks, all green. No known regressions in existing crawl/browse behavior (re-verified via curl against the real running server after adding the new routes/table).
- **Explicitly out of scope for this PR** (see the archived change's design.md Non-Goals): product crawl does not yet *consume* the discovered category tree (e.g. seeding its queue from known leaf URLs, or skipping live rediscovery on pages already in `site_categories`). Discovery only produces and exposes the data today.
- Prior PRs #1, #2, #3 merged to `main`; release `v0.1.0` tagged.
- Known limitation carried over from product-extraction (unchanged): exhaustive full-tree crawl of large categories (~9.5k pages on azurestandard "Food") not feasible in one sync request — bounded by `max_pages` only (now up to 500, was 20).

### Immediate next step
Awaiting user review/merge of **PR #4**. After merge: `git fetch --prune`, fast-forward local `main`, delete merged branch — same cleanup pattern as after PR #1/#2/#3.

Candidate follow-up (not started): make product crawl actually use the discovered `site_categories` tree — e.g. let a crawl target a known leaf category directly (skip live hub rediscovery), or seed a "crawl this whole subtree" operation from known leaf URLs while still visiting any hub node flagged `has_own_products = true` (so hub-level products aren't silently skipped).
