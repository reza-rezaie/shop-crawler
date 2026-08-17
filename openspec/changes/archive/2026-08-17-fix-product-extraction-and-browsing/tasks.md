## 1. Extraction correctness fixes (native Mojo)

- [x] 1.1 In `textutil.mojo`, change the class-hint matching used by
      `extract_blocks_by_class_hint` to split the `class` attribute value on
      whitespace and match the hint against individual tokens, accepting
      only tokens made of `[A-Za-z0-9_-]` characters.
- [x] 1.2 In `textutil.mojo`, harden `extract_attr` so a match on
      `<name>="` requires the preceding character to be a word boundary
      (start of tag, whitespace, or quote), so `class` can't match inside
      `ng-class`.
- [x] 1.3 Add/update unit-style test coverage (see section 5) proving the
      Angular `class="{ ... product.something }"` case no longer matches
      and a real `product_pod`/`product-item` class still does.
- [x] 1.4 (found during implementation, see design.md) In `http_client.mojo`,
      fix `can_fetch` to retrieve `robots.txt` with the crawler's own
      User-Agent (via `fetch()`) and feed it to `RobotFileParser.parse()`,
      instead of `RobotFileParser.read()` -- azurestandard.com's edge
      403s `read()`'s unconfigurable default UA on `/robots.txt` itself,
      which was silently blocking the entire crawl before extraction ever
      ran.

## 2. SPA-shell detection and crawl reporting

- [x] 2.1 In `html_extract.mojo`, add a function that checks fetched HTML
      for common client-rendered app-shell markers (`ng-app=`,
      `data-reactroot`, `id="root"`, `id="__next"`, `data-v-app`).
- [x] 2.2 In `crawler.mojo`, when a page's extraction yields zero products
      and the SPA-shell check matches, record a note for that page.
- [x] 2.3 Include collected per-page notes in the crawl summary returned by
      `crawler.crawl` / `api.crawl` (additive field, no breaking change to
      existing summary fields).
- [x] 2.4 Update `frontend/src/App.jsx` to display any crawl notes/warnings
      returned alongside the existing success/error status.

## 3. Source attribution (storage + API)

- [x] 3.1 In `db.mojo`, derive a `source_host` value from the stored
      `source_listing_url` in `query_products` (query-time, no schema
      change) and include it in each returned item.
- [x] 3.2 In `db.mojo`, accept an optional `source_host` filter in
      `query_products` and apply it alongside the existing filters.
- [x] 3.3 Add a `list_sources` function to `db.mojo` returning the distinct
      source hosts currently in the catalog (mirrors `list_categories`).
- [x] 3.4 Wire `source_host` filter and `list_sources` through
      `api.mojo` (`list_products`, new `sources` export) and
      `backend/server.py` (`/api/products` query param, new
      `/api/sources` route).

## 4. Frontend: browse-all view with source attribution

- [x] 4.1 In `App.jsx`, display each product's source site on its card.
- [x] 4.2 In `App.jsx`, add a source-site filter control populated from
      `/api/sources`, combinable with the existing search/category/price
      filters.
- [x] 4.3 Update `App.css` for the new card element and filter control.

## 5. Tests

- [x] 5.1 Add a Mojo test script exercising `textutil`/`html_extract`
      against saved sample HTML fixtures: the real azurestandard.com
      SPA-shell page (false-positive class match must now be absent, and
      the SPA-shell note must fire) and the existing books.toscrape.com
      fixtures (extraction must still work unchanged).
- [x] 5.2 Add a small script/test exercising `db.query_products`'s new
      `source_host` filter and `list_sources` against a temp SQLite DB with
      multi-site fixture data.
- [x] 5.3 Run the full `pixi run mojo run` / API smoke test suite and
      record results in the PR/commit description.

## 6. Verification

- [x] 6.1 Re-crawl `https://www.azurestandard.com/shop/category/` and
      confirm the crawl summary reports zero products with the SPA note,
      and no bogus product is created.
- [x] 6.2 Re-crawl `https://books.toscrape.com/` (existing verified target)
      and confirm extraction results are unchanged (no regression).
- [x] 6.3 Verify in the running UI that products from both crawls (if any
      stored data exists from earlier sessions) are visibly attributed to
      their source site and the source filter works end-to-end.
