## Context

See `proposal.md` for motivation. Relevant existing building blocks this
reuses as-is (no changes to their behavior or signatures):

- `textutil.is_child_path` / `textutil.find_all_anchor_hrefs` — the
  path-nesting rule and raw anchor-scan that `html_extract.find_child_links`
  already uses for product-extraction's drill-down.
- `html_extract.looks_like_not_found_page` — not-found detection.
- `http_client.fetch` / `http_client.can_fetch` / `http_client.now_iso` —
  fetching, robots.txt evaluation, timestamps.
- `html_extract.extract_json_ld_products` / `extract_heuristic_products` —
  the same two extraction strategies product crawl uses, reused here only
  to answer "does this page show its own products," not to keep the
  extracted products.
- `db.mojo`'s pattern: one `SCHEMA` string with `CREATE TABLE IF NOT
  EXISTS` run on every `connect()`, plain `sqlite3` via Python interop, no
  separate migration mechanism.

## Goals / Non-Goals

**Goals:**
- Walk and persist a site's category tree independent of product
  extraction, cheaply enough to run well ahead of any product crawl.
- Make re-running discovery on a partially-mapped site additive
  (upsert), not duplicative.
- Capture the product-presence signal per node at no extra request cost.

**Non-Goals (deferred to a future change):**
- Changing how a product crawl (`crawler.mojo`, `/api/crawl`) uses the
  discovered tree — e.g. seeding a product crawl's queue from known
  category URLs, or skipping live `find_child_links` rediscovery on
  pages already in `site_categories`. This change only produces and
  exposes the data; consuming it in `crawler.mojo` is separate follow-up
  work.
- Pruning/removing category nodes whose live link has disappeared from
  the site. Discovery only adds/updates; staleness cleanup is future
  work.
- Background/async or scheduled discovery. This follows the existing
  `/api/crawl` shape: a synchronous request that runs to completion (or
  its own budget limit) and returns a summary.
- Deriving `products.category` from the discovered tree. Product
  extraction's existing breadcrumb-based category labeling is unchanged.
- **Revised during implementation**: "no JS-rendering fallback" was
  originally listed here. Live-testing against azurestandard.com showed
  its raw HTML has no category links at all (a 73KB Angular shell with
  26 unrelated hrefs) — discovery would find nothing on the exact site
  this whole feature was motivated by. A rendering fallback was added
  instead; see the Decisions section below. What's still a genuine
  non-goal: description fetches, per-product detail requests, and
  persisting anything to the `products` table — none of that happens in
  discovery regardless of whether a page needed rendering.

## Decisions

**Separate module (`category_discovery.mojo`), not an extension of
`crawler.mojo`.**
Discovery's loop shape is genuinely different (no product/description
extraction, no JS-rendering fallback, different budgets, different
persistence target) and the proposal's Impact explicitly keeps
`crawler.mojo` untouched. A separate module also keeps product-extraction
spec/behavior provably unaffected — nothing shared is modified, only
reused.
*Alternative considered*: add a "discovery mode" flag to the existing
crawl loop. Rejected — it would tangle two different budgets and two
different persistence paths into one function for no real code reuse
beyond what's already reusable as separate imports.

**New textutil helper for anchor text, additive only.**
`find_all_anchor_hrefs` returns `List[String]` (hrefs only) and is used
as-is by `find_child_links` today. Add a new function (e.g.
`find_all_anchor_hrefs_with_text`) returning `List[(String, String)]`
(href, cleaned inner text) for discovery's naming needs, rather than
changing the existing function's return type and updating its one
current caller for no benefit there.

**Reuse full extraction functions for the product-presence check, not a
new lightweight scanner.**
Call the same `extract_json_ld_products`/`extract_heuristic_products`
used by `crawler.mojo` and just check the returned count, discarding the
products. This duplicates no matching logic (one heuristic definition,
enforced in one place) at the cost of doing slightly more parsing work
per node than a minimal "does any card exist" scan would. Given the
per-page cost is already dominated by the network fetch, this is an
acceptable trade for not maintaining a second, subtly-different
product-detection code path.
*Alternative considered*: a boolean-only presence scanner. Rejected for
now — worth revisiting only if profiling ever shows extraction parsing,
not fetch latency, as the actual bottleneck.

**Schema: `has_own_products` stored as a tri-state; `has_children`
derived, not stored.**
`site_categories` stores one new signal that isn't derivable elsewhere
(`has_own_products`: `NULL` = not yet fetched/unknown, `0`/`1` once
known). Whether a node has children is always derivable by checking for
other rows with `parent_url` equal to its `url`, so no redundant column
for it — one less place for stored state to drift from reality.

```sql
CREATE TABLE IF NOT EXISTS site_categories (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    url               TEXT NOT NULL UNIQUE,
    name              TEXT NOT NULL,
    parent_url        TEXT,
    host              TEXT NOT NULL,
    has_own_products  INTEGER,   -- NULL = unknown, 0 = false, 1 = true
    first_seen_at     TEXT NOT NULL,
    last_seen_at      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_site_categories_host ON site_categories(host);
CREATE INDEX IF NOT EXISTS idx_site_categories_parent ON site_categories(parent_url);
```

Added to the same `SCHEMA` string in `db.mojo`, matching the existing
one-string/`IF NOT EXISTS` pattern — no new migration mechanism.

**Own budget constants, sized like `crawler.mojo`'s but separate.**
`MAX_DISCOVERY_PAGES_DEFAULT`, `MAX_DISCOVERY_PAGES_HARD_CAP`,
`MAX_DISCOVERY_CHILDREN_PER_HUB` in the new module, independent of
`crawler.mojo`'s `MAX_PAGES_*`/`MAX_CHILD_LINKS_PER_HUB_PAGE` — a
discovery run and a product crawl are separate operations with separate
cost profiles (no product/description fetches in discovery), so sharing
one constant would under- or over-bound one of them.

**API surface: new routes under `/api/site-categories`, existing
`/api/categories` untouched.**
`POST /api/site-categories/discover` (body: `{url, max_pages?}`, mirrors
`/api/crawl`'s shape) runs a discovery crawl and returns a summary
(`pages_visited`, `categories_found`, `categories_updated`, `errors`).
`GET /api/site-categories?host=...` returns that host's tree. Keeping
these under a distinctly-named path avoids any ambiguity with
`/api/categories` (the flat, product-derived list the existing product
filters use) — the two represent different things (discovered site
structure vs. observed product labels) and neither should be confused
with or silently change the other.

**Frontend: a second view via local tab state, no router dependency.**
The app is currently one component with no client-side routing. Add a
small top-level tab switch (e.g. "Products" / "Categories") in `App.jsx`
driven by local state, rather than introducing a routing library for two
views. The categories view: a URL input + "Discover" button (mirrors the
existing crawl panel's shape) and a tree rendering of `GET
/api/site-categories` for the discovered host (indented list grouped by
`parent_url`, each node showing name, link, and a product-presence
badge: yes / no / unknown).

**JS-rendering fallback, keyed off "zero links" instead of "zero
products" (added during implementation).**
Reuses `html_extract.looks_like_client_rendered_app` exactly as-is —
that function only ever checks "does this look like an SPA shell AND is
the given count zero," so passing it a link count instead of a product
count needed no change to the function itself. When it fires: render the
page once with `browser_client.render_fetch` (same as product
extraction) and re-run `decide_discovery_page` against the rendered HTML
instead, for both children and `has_own_products`. Live-verified against
azurestandard.com: a plain-HTML-only run found 1 node total (the seed);
with rendering, a `max_pages=15` run found 150 real category nodes
(Food, Health & Beauty, Household & Family, ... each with their real
subcategories). Same cost guard as product-extraction: a page whose raw
HTML already has usable links never triggers a render.
*Trade-off accepted*: discovery is no longer unconditionally cheaper
than a product crawl on every page — an SPA site pays a per-page browser
launch, same as product extraction already does. Still lighter overall
per rendered page (no product/description extraction on top of it).

**Child-link filtering: exclude the page's own next-page link and
fragment-only variants.**
Two link shapes were found, live, to satisfy the same path-nesting rule
a genuine subcategory does, and need excluding from child candidates:
1. Same-listing pagination (e.g. `page-2.html` next to `index.html`) —
   filtered via `find_next_page_url` (the same function product
   extraction already uses to follow pagination): whatever URL it
   identifies as the current page's own "next" link is skipped as a
   child candidate. **Explicitly best-effort, not complete** — verified
   against books.toscrape.com's real pagination. A page reached only via
   a "previous" link pointing at a URL distinct from the page currently
   pagination-forward from it (e.g. `page-1.html` when the actual first
   page's URL was `index.html`) can still slip through once, since
   `find_next_page_url` only ever identifies *this* page's own forward
   link, not every possible sibling.
2. A `#fragment` variant of an already-seen link (e.g.
   `/shop/product/x#reviews` next to a plain `/shop/product/x` link) —
   stripped before dedup/recording, since a fragment never causes a
   different page load. Unlike the pagination filter, this one is
   complete: `is_child_path`'s own path comparison already ignores
   fragments (via `textutil.url_path`), so treating them as identical for
   recording purposes just makes discovery's own child-link identity
   consistent with the rule that decides whether a link is a child at
   all, rather than a separate, narrower heuristic.

## Risks / Trade-offs

- **A single discovery run won't necessarily map a very large site's
  full tree** (same root cause as product-extraction's documented ~9.5k
  page limitation) → mitigated by upsert semantics: re-running discovery
  is additive, so the tree converges over multiple runs rather than
  needing to finish in one request.
- **Stale nodes**: if a site removes or moves a category, its old row
  persists with no signal that it's gone → accepted for this change;
  flagged as a Non-Goal, candidate for a later "last confirmed seen"
  pruning pass.
- **Shared SQLite file**: discovery and product crawls both write to
  `products.db` via the same plain-`sqlite3`-over-Python-interop pattern
  already used for products; no new concurrency behavior is introduced
  beyond what already exists between concurrent product crawls today.
- **Pagination filtering is best-effort, not complete** (see Decisions
  above): a "previous"-only link to a URL distinct from the page it
  paginates forward from can still be recorded as a spurious child.
- **Shallow hub pages can absorb their own item links as pseudo-children**:
  `is_child_path`'s path-nesting rule gets coarser the shallower a page's
  own path is. A one-segment page like `/shop/clearance` has almost its
  whole site (`/shop/*`) as its "path stem," so live-testing found it
  (and similar utility pages like `/shop/brands`) recording the
  individual product/brand pages it lists directly as if they were
  further subcategories, even though `has_own_products` already
  correctly flags such a page as a real leaf listing. This is the same
  underlying heuristic reused as-is from product-extraction's own
  drill-down (see Context) — harmless there (an extra page to crawl for
  products is not a correctness problem), but visibly wrong in a tree
  view here. No filter was added for this case in this change: unlike
  pagination (a single, nameable link `find_next_page_url` already
  identifies) or fragments (a mechanical, complete fix), there's no
  comparably narrow, reliable way to tell "this nested link is a real
  subcategory" from "this nested link is just one of this leaf page's
  own items" from URL shape alone. Documented as a known limitation,
  same as the pre-existing ~9.5k-page exhaustive-crawl limitation.

## Migration Plan

Additive only: a new table (created via the existing `IF NOT EXISTS`
schema pattern, so it applies automatically on next `connect()` with no
separate migration step), new API routes, new frontend view. No existing
table, route, or component is modified or removed, so there's nothing to
roll back beyond reverting the change itself.
