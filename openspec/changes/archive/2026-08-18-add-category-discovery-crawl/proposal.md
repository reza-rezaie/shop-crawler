## Why

There is currently no way to see a site's category structure before
running a product crawl. Categories only exist today as a side effect of
extraction: `list_categories` derives a flat, distinct list from
`products.category` after products have already been crawled. To find a
specific category to crawl, an operator has to already know (or guess and
paste) an exact URL, and every product crawl that lands on a hub page
re-discovers that hub's subcategories live, from scratch, every time.
A dedicated discovery pass lets a site's category tree be mapped once,
ahead of any product extraction, and browsed/reused afterward.

## What Changes

- New page in the frontend: enter a seed URL, run category discovery
  against it, and browse the resulting tree for that site.
- New backend capability: a category-discovery crawl that walks same-host
  "child" links (reusing product-extraction's existing path-nesting
  heuristic — same-host, URL path nested under the parent page's path) in
  breadth-first order, recording each discovered link as a category node
  (name taken from its anchor text, plus its parent and host) — without
  persisting product rows or fetching product descriptions on any page it
  visits. **Revised after live-testing against azurestandard.com** (the
  SPA reference site this project's drill-down work was built and
  verified against): its category navigation doesn't exist in raw HTML at
  all, so discovery does fall back to rendering a page with a headless
  browser when it looks like an SPA shell and yields zero candidate
  links — the same trigger shape product-extraction already uses for
  zero products, just keyed off zero links instead. This is still
  deliberately lighter than a product crawl (no product/description
  extraction, no per-product detail fetches), just not unconditionally
  cheaper on every page the way originally scoped.
- Each node discovery fetches also records a cheap, best-effort signal —
  whether that page's own HTML shows any product-card markup — captured
  from the same fetch discovery already makes for finding child links (no
  extra request). This is stored for future use by product crawls;
  actually changing how a product crawl consumes it is out of scope here
  (see Non-goals in design.md).
- Discovery is bounded by its own page and per-hub breadth budgets,
  separate from a product crawl's `max_pages`. Results are upserted by
  URL, so re-running discovery on a site already in the table fills in
  more of the tree (or refreshes existing nodes) instead of duplicating
  rows — a single discovery run is not expected to necessarily reach
  every category on a large site in one pass.
- New `site_categories` table, distinct from the existing
  `products.category` text column — this captures site structure
  (discovered ahead of time, tree-shaped), not the per-product label
  already produced by extraction.
- New read API to list a discovered tree by host, new API to trigger a
  discovery crawl. Existing `/api/categories` (the flat, product-derived
  list used by the product browse filters) is unchanged.

## Capabilities

### New Capabilities
- `category-discovery`: crawling a site to discover and persist its
  category tree (URL, name, parent, host, product-presence signal) ahead
  of product extraction, and viewing that tree.

### Modified Capabilities
(none — this reuses product-extraction's path-nesting heuristic as-is
and does not change product crawl or product browsing behavior)

## Impact

- `backend/mojo_src/`: new module for the discovery crawl loop (reusing
  `textutil.is_child_path`, `html_extract.find_all_anchor_hrefs`-style
  link scanning, `http_client.fetch`/`can_fetch`); new `db.mojo`
  table/queries for `site_categories`; new `api.mojo` exports.
- `backend/server.py`: new `/api/site-categories` (GET) and
  `/api/site-categories/discover` (POST) routes.
- `frontend/src/`: new page/tab for triggering discovery and browsing a
  site's category tree; minimal client-side navigation between it and
  the existing product-browsing page (no router dependency added).
- No changes to `crawler.mojo`, the product-extraction spec, or the
  existing `/api/crawl` / `/api/categories` / `/api/products` behavior.
