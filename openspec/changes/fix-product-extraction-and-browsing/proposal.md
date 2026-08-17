## Why

Crawling `https://www.azurestandard.com/shop/category/` produced a product in
the catalog that doesn't match anything on that page. Root-caused (see
`design.md`) to two compounding issues: (1) the heuristic product extractor
matches on any substring of a `class` attribute's raw text, so it can be
fooled by JS-framework markup (Angular binding expressions, `ng-class`, etc.)
that happens to contain the word "product" without being a real product
card, extracting unrelated page furniture as if it were a product; and (2)
azurestandard.com renders its catalog client-side (no product markup exists
in the raw HTML at all), and a crawl that finds zero genuine products fails
silently — the browse view just keeps showing whichever products are
already in the shared SQLite catalog from earlier crawls of other sites,
with no indication of where they actually came from. That combination is
exactly what makes it look like "crawling site A shows a product from site
B": nothing shows which listing page or site each stored product was
actually crawled from, and there's no dedicated way to browse/audit the
full catalog by source to catch this.

## What Changes

- Tighten product-card detection so a `class` attribute only counts as a
  match when "product" appears in an actual class-name token (split on
  whitespace, alphanumeric/`-`/`_` only) — not anywhere in the attribute's
  raw text. This stops framework binding expressions (`class="{ ...
  product.something }"`) from being mistaken for product cards.
- Harden attribute-value lookup so searching for `class="..."` can no
  longer match inside a differently-named attribute that merely ends with
  "class=" (e.g. `ng-class=`), by requiring a proper boundary before the
  attribute name.
- Detect pages whose fetched HTML shows no extractable product markup and
  is dominated by a client-side app shell (common SPA markers: `ng-app`,
  `data-reactroot`, `id="root"`/`id="__next"`, etc. with no matches from
  either extraction strategy) and report that explicitly in the crawl
  result instead of silently returning zero with no explanation.
- Store and expose which host/listing page each product was crawled from,
  and surface it in the UI: a dedicated "browse all crawled products" view
  groups/filters by source site so stale or cross-site data is immediately
  visible and traceable instead of blending into the general catalog.

## Capabilities

### New Capabilities
- `product-browsing`: browsing the full local catalog with visibility into,
  and filtering by, which site/listing page each stored product came from.
- `product-extraction`: correctness requirements for what counts as a
  product-card match, and for reporting when a crawled page yields no
  extractable products (e.g. client-rendered pages). This capability
  already exists in code (this is the first OpenSpec change in this repo,
  so no capability has a baseline spec yet); this change establishes its
  spec baseline and fixes the bug in the same pass.

### Modified Capabilities
None.

## Impact

- `backend/mojo_src/textutil.mojo`: class-token matching, attribute-name
  boundary matching.
- `backend/mojo_src/html_extract.mojo`: SPA-shell detection.
- `backend/mojo_src/crawler.mojo`, `backend/mojo_src/api.mojo`: surface the
  new "no extractable products / likely JS-rendered" signal in the crawl
  summary.
- `backend/mojo_src/db.mojo`: no schema change needed (`source_listing_url`
  is already stored per product); query/filter support for browsing by
  source host.
- `backend/server.py`: no new routes needed beyond what `/api/products`
  already exposes, aside from passing through a new filter param.
- `frontend/src/App.jsx`, `frontend/src/App.css`: show source site per
  product card and add a source-site filter to the browse view.
- Tests: extraction unit tests covering the false-positive class-match
  case and the SPA-shell case.
