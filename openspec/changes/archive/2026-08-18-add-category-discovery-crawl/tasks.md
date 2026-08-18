## 1. textutil: anchor text alongside hrefs

- [x] 1.1 Add `find_all_anchor_hrefs_with_text(html) -> List[(String, String)]` in `textutil.mojo`, returning each `<a>`'s resolved-later href and its `clean_text`-ed inner text, without changing the existing `find_all_anchor_hrefs`.
- [x] 1.2 Unit tests in `tests/test_textutil.mojo` (or a new test file): anchor with text, anchor with no text (nested image only), multiple anchors on one page.

## 2. Storage: `site_categories` table

- [x] 2.1 Extend `db.mojo`'s `SCHEMA` string with the `site_categories` table and its `host`/`parent_url` indexes (see design.md).
- [x] 2.2 Add `upsert_site_category(conn, url, name, parent_url, host, has_own_products) -> outcome` (upsert by `url`, matching the existing `upsert_product` shape: update `name`/`parent_url`/`has_own_products`/`last_seen_at` on conflict, set `first_seen_at` only on insert). `has_own_products` argument accepts unknown/true/false.
- [x] 2.3 Add `list_site_categories(conn, host) -> PythonObject` returning every node for a host (id, url, name, parent_url, has_own_products) for the tree view.
- [x] 2.4 Tests in `tests/test_db.mojo`: insert new node, upsert existing node updates fields without duplicating, `has_own_products` transitions from unknown to known on a later upsert, `list_site_categories` scopes to one host.

## 3. Discovery crawl loop

- [x] 3.1 New `category_discovery.mojo`: BFS queue over one seed URL, `visited` set, own budget constants (`MAX_DISCOVERY_PAGES_DEFAULT`, `MAX_DISCOVERY_PAGES_HARD_CAP`, `MAX_DISCOVERY_CHILDREN_PER_HUB`), reusing `can_fetch`/`fetch` (robots.txt + not-found handling via `looks_like_not_found_page`) and `is_child_path` (via the new anchor-text helper) for child-link discovery.
- [x] 3.2 On each fetched page: run `extract_json_ld_products`/`extract_heuristic_products` against that page's own HTML to get its own `has_own_products` signal (true/false), and collect its child links (name from anchor text, falling back to a name derived from the URL path when anchor text is empty) as pending queue entries, not yet upserted. **Refinement made while implementing** (see note below): a child link is only upserted once *its own* page is fetched and confirmed real, not eagerly the moment it's seen as a link — see 3.3.
- [x] 3.3 Skip recording and skip further traversal for pages that `looks_like_not_found_page` flags.
- [x] 3.4 Upsert every confirmed-real node via `upsert_site_category` as discovery proceeds (not batched at the end); anything still queued when the page budget runs out is flushed at the very end with `has_own_products` left unknown, so a budget-truncated run still persists everything it reached.
- [x] 3.5 Return a summary (`seed_url`, `pages_visited`, `categories_found`, `categories_updated`, `errors`) matching the shape `crawler.mojo`'s `_summary` uses.
- [x] 3.6 Tests in `tests/test_category_discovery.mojo`: nested tree discovered breadth-first with correct parents; unrelated same-host links excluded (reuse of `is_child_path` semantics); not-found page excluded and not traversed further; a hub page with its own products gets `has_own_products = true`, one without gets `false`; `pending_after_budget` (the budget-cutoff flush) leaves unvisited entries pending with an unknown signal; a page's own pagination link and a fragment-only variant of an already-seen link are excluded. Upsert-not-duplicate semantics are covered at the storage layer (2.4) since every discovery write goes through `upsert_site_category`; the full BFS loop itself is network-driven like `crawler.mojo`'s own loop and is verified live instead (6.2/6.3).

  **Note on 3.2/3.3**: the tasks as originally written implied recording a child node the instant it's seen as a link (with an unknown signal), which conflicts with the spec's "not-found pages are never recorded" requirement -- a link can only be confirmed as not-found *after* its own page is fetched, which happens after it was already seen as a link on its parent. Resolved by deferring the actual upsert until either (a) the child's own page is fetched and confirmed not a 404, or (b) the run's budget ends with it still unfetched, in which case it's flushed as unknown. Both spec requirements and all their scenarios hold under this ordering; see `decide_discovery_page`/`pending_after_budget` in `category_discovery.mojo`.

  **Revision made after live-testing (see design.md's updated Decisions/Risks)**: live runs against azurestandard.com and books.toscrape.com surfaced two gaps not visible from fixtures alone, both fixed and covered by tests: (1) a JS-rendering fallback was added -- discovery found *zero* children anywhere on the real SPA reference site without it; (2) same-listing pagination links (`page-2.html` next to `index.html`) and `#fragment` variants of an already-seen link were being recorded as bogus child nodes, now filtered (pagination filtering is explicitly best-effort, not complete -- see design.md). A related, unfixed limitation was also found and documented rather than chased further: shallow hub pages (e.g. `/shop/clearance`) can still record their own item links as pseudo-subcategories, since the path-nesting rule can't distinguish that case from a real subcategory. Confirmed by the user before implementing (JS rendering: "add it"; pagination noise: "best-effort filter").

## 4. API layer

- [x] 4.1 `api.mojo`: add `discover_categories(db_path, request)` (parses `url`, optional `max_pages`, calls the module 3 crawl, returns its summary or a `{"error": ...}` dict for a missing url -- an unreachable/robots-blocked seed reports through the summary's own `errors` list instead, matching `/api/crawl`'s existing behavior for the same case) and `site_categories(db_path, params)` (parses `host`, calls `list_site_categories`).
- [x] 4.2 Register both in `PyInit_api` alongside the existing exports. Verified end-to-end (Python interop, real sqlite db) via ad hoc script, not just compiled.
- [x] 4.3 `server.py`: add `POST /api/site-categories/discover` and `GET /api/site-categories` routes, following the existing `_handle_api` dispatch pattern; leave `/api/categories`, `/api/crawl`, `/api/products` untouched. Verified over real HTTP (ran the actual server, curled both routes).

## 5. Frontend: Categories page

- [x] 5.1 Add a small top-level tab switch in `App.jsx` (local state, no router) between the existing product-browsing view and a new categories view.
- [x] 5.2 New categories view: URL input + "Discover" button calling `POST /api/site-categories/discover`, showing a status message (pages visited / categories found/updated, or an error) matching the existing crawl panel's status pattern.
- [x] 5.3 Tree rendering of `GET /api/site-categories?host=...` (indent by `parent_url` relationship), each node showing name, a link to its URL, and a product-presence badge (yes / no / unknown) per design.md.
- [x] 5.4 Empty state when the selected host has no discovered categories yet. `npm run build` and `npm run lint` (oxlint) both pass clean.

## 6. Verification

- [x] 6.1 `pixi run test` green (new + existing test files). All 7 test files pass, no regressions.
- [x] 6.2 Manual: run discovery against a real multi-level category site. Against `https://www.azurestandard.com/shop/category` with `max_pages=15`: 150 real category nodes recorded across Food, Health & Beauty, Household & Family, Nutritional Supplements, and Outdoor & Garden, each with correct parents and their own real subcategories (e.g. Food → Baking & Pantry, Beans & Peas, Beverages, ...); multiple hub nodes correctly flagged `has_own_products = true` (Food, Health & Beauty, New Products, Sales, Bonus Azure Cash, Clearance). Required adding the JS-rendering fallback (see design.md) -- without it this site's raw HTML has no category links anywhere.
- [x] 6.3 Manual: confirmed via curl against the real running server (built frontend + real `data/products.db`) that `/api/crawl`, `/api/categories`, `/api/products` behavior and data are unchanged (pre-existing 15 products, same shapes) after adding the new routes/table.

  **Note**: running these manual checks against the real `data/products.db` (the server's hardcoded path, no test-db override exists) added the new, empty `site_categories` table to that file via the existing `CREATE TABLE IF NOT EXISTS` schema pattern -- the same additive, zero-data-loss change every real user gets on their next server start. No existing rows were read, written, or altered.
