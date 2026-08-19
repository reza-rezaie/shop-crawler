## Handoff — shop-crawler (Mojo Product Crawler)

**Repo:** github.com/reza-rezaie/shop-crawler | local: `/home/reza2/repo/azure-crawler2`
**Branch:** `main` (merged: **PR #6**)

### Active files
- `frontend/src/App.jsx` — `ProductCard` no longer renders an image thumbnail (dropped the `.product-thumb` block entirely); source/name/category/price unchanged
- `frontend/src/App.css` — `.product-grid`/`.product-card`/`.product-body` retuned for a denser, image-free layout (smaller `minmax` column width, tighter gaps/padding, cards size to content instead of stretching); `.product-thumb*` rules removed
- `openspec/config.yaml` — new `context`: change-numbering convention (`chg-NNNN-short-description`, or `NNN-` if no `chg-NNNN` changes exist yet)
- `.claude/settings.json` / `.claude/hooks/block-edit-on-main.sh` — new: a `PreToolUse` hook blocking `Write`/`Edit`/`NotebookEdit` on tracked, non-`openspec/` files while on `main`, so future work is forced onto a branch first (this repo's own convention, now enforced mechanically instead of relying on remembering)

### Current state
- PR #5 (Postgres switch) merged to `main`.
- **PR #6 removes the product-card image thumbnail from the browse view and densifies the grid** (`openspec/changes/archive/2026-08-18-001-declutter-product-grid/`) — crawled `image_url` is often missing/broken, wasting the card's most prominent space; dropping it let the grid pack more cards per row. `image_url` is unchanged in the API/catalog, only its use in the browse view's cards changed (**BREAKING** for anything that relied on it rendering there). `product-browsing`'s main spec gained one new requirement ("Product cards omit images"); no other capability touched.
- Verified by running the app end-to-end locally (pixi-managed Postgres + Mojo backend + rebuilt Vite frontend) and visually confirming via screenshot: no image/placeholder on any card (601 real products, most with `image_url` set), 6 cards/row vs. the old image-led layout.
- Also added, in the same PR, a repo-local safeguard: a `PreToolUse` hook that blocks code edits landing directly on `main` (openspec planning files and gitignored paths are exempt). Prompted by catching myself mid-session having skipped branching before implementing.
- PR #6 merged to `main`; branch `feat/declutter-product-grid` deleted (local + remote). Change archived via `/opsx:archive`, delta synced into `openspec/specs/product-browsing/spec.md`.
- Prior PRs #1–#5 merged; release `v0.1.0` tagged. See prior handoff entries in git history for Postgres-switch and category-discovery details.
- Known limitations carried over unchanged from PR #4 (see prior handoff entries): shallow-hub pseudo-subcategory absorption, exhaustive full-tree crawl of very large categories not feasible in one request, pagination-vs-child-link filtering is best-effort.

### Immediate next step
No PR currently in flight.

Candidate follow-ups (not started):
- Make product crawl actually *use* the discovered `site_categories` tree — e.g. let a crawl target a known leaf category directly (skip live hub rediscovery), or seed a "crawl this whole subtree" operation from known leaf URLs while still visiting any hub node flagged `has_own_products = true` (so hub-level products aren't silently skipped). Carried over from PR #4.
- The "result list can be better" ask that prompted PR #6 was scoped down to "denser grid cards" for that PR; a table/list view or sortable columns (price/name, more fields at a glance) were considered but deferred — revisit if denser cards alone aren't enough.
- If/when a real deployment target comes up (not just local dev), Postgres connection config is already env-var-driven (`PGHOST`/`PGPORT`/`PGDATABASE`/`PGUSER`/`PGPASSWORD`) — pointing at a managed instance instead of the pixi-local one is just overriding those vars, no code change needed.
