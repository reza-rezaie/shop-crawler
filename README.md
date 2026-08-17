# Mojo Product Crawler — POC

A proof-of-concept product crawler + local browser. The backend and all
crawling/business logic are native **Mojo v1.0 GA**; Python is only a thin
HTTP transport shim plus a handful of standard-library calls Mojo doesn't
natively cover yet (sqlite3, urllib, json, html, http.server), plus one
third-party package (Playwright, for a JS-rendering crawl fallback — see
below). See [SPEC.md](SPEC.md) for the full design and the exact
Mojo/Python split.

```
pixi.toml            # Mojo + task definitions (one third-party Python dep: playwright-python)
scripts/activate.sh   # pixi activation hook (see "Gotcha" below)
backend/
  mojo_src/            # native Mojo: crawler, HTML extraction, pricing, SQLite, API
  server.py             # thin Python HTTP shim + static file server
frontend/              # React (Vite) UI
data/products.db       # SQLite database (created on first run)
```

## Prerequisites

- [Pixi](https://pixi.sh) (already used to provision Mojo v1.0 GA here)
- Node.js/npm (for the React frontend build)

Everything else — the Mojo compiler, and the Python interpreter the backend
uses for interop — is installed by Pixi from `pixi.toml`.

## Run it

```bash
pixi run frontend-install   # once
pixi run frontend-build     # rebuild after any frontend change
pixi run playwright-install # once — downloads the Chromium binary used by the JS-rendering fallback
pixi run serve              # starts the backend at http://localhost:8000
```

Then open **http://localhost:8000**. If port 8000 is already taken on your
machine, run `PORT=8010 pixi run serve` instead (or `pixi run python
backend/server.py --port 8010`).

1. Paste a shop/category page URL into the box at the top — the app was
   built and tested against **https://books.toscrape.com** (a public
   sandbox site made for scraping practice), e.g.
   `https://books.toscrape.com/` or
   `https://books.toscrape.com/catalogue/category/books/mystery_3/index.html`.
2. Click **Crawl**. It fetches up to "Max pages" listing pages (following
   pagination), optionally visits each product's detail page for a
   description, and stores everything in `data/products.db`.
3. Browse, search by name, and filter by category/price/**source site**
   below (crawling more than one site keeps their products distinguishable
   instead of blending together — each card shows the site it came from).
   Click a card to open the real product page.
4. Crawl the same URL again any time — existing products are updated
   in place (by product URL), never duplicated.
5. If a crawl finds zero products and the page looks like a client-rendered
   app shell (React/Angular/Vue/Next.js), it automatically retries that
   page by actually rendering it in headless Chromium and re-extracting
   from the rendered HTML — no toggle needed, and pages that don't need
   this pay no extra cost. Confirmed working end-to-end on a real
   AngularJS SPA (`https://www.azurestandard.com`); if it still finds
   nothing even after rendering, the crawl result says so.
6. If a page has no products of its own but links to narrower category
   pages (a "hub"/"browse" page on a site with a category tree — common
   on larger stores), the crawl automatically follows a bounded number of
   those links too, so pointing it at a high-level category can still
   reach the real listings underneath it — all within the same "Max
   pages" budget. If a crawled URL turns out not to be a real page on the
   site at all (e.g. a typo'd or incomplete category URL), the crawl
   result says that specifically, instead of a generic "found nothing."

### One-shot crawl without the UI

```bash
pixi run crawl -- https://books.toscrape.com/
```

### Tests

```bash
pixi run test
```

Runs the native-Mojo test suite under `backend/mojo_src/tests/` (string/
HTML extraction correctness, SPA-shell detection, JS-rendered-DOM
extraction, SQLite storage/filtering — see `openspec/specs/` and
`openspec/changes/archive/` for what prompted several of these).

## Notes / POC limitations

- The crawl endpoint runs synchronously and is capped (default 3 pages,
  hard cap 20; detail-page fetches capped too) with a rate-limited request
  pace — reasonable for a small test site, not meant for large stores.
- Extraction is generic (schema.org JSON-LD, then a heuristic scan for
  "product-ish" container elements) but was only verified end-to-end
  against books.toscrape.com; other sites' markup may need small tweaks.
- Sites that render their catalog client-side (single-page apps) are now
  handled via a headless-Chromium rendering fallback (see above), verified
  end-to-end on a real AngularJS SPA
  (`https://www.azurestandard.com/shop/category/food/baking-pantry/26644`).
  That fallback still has real limits: it renders once and waits a fixed,
  short amount of time (no infinite-scroll/"load more" interaction, no
  adaptive wait), and only listing pages get it — product *detail* pages
  (for descriptions) remain raw-HTTP-only. A site whose listing needs
  scrolling/clicking to reveal products, or renders unusually slowly, may
  still come back with fewer or zero products.
- Category drill-down (point 6 above) is a generic URL-path heuristic
  ("same host, path nested under the current page's own path"), not tied
  to any one site's markup — but it only ever follows links, so a site
  whose category tree is driven by client-side filters/dropdowns with no
  real per-category URL won't be reachable this way. Bounded by a
  per-hub-page cap on how many child links get enqueued at once, plus the
  existing overall page budget.
- Development/testing crawled real-world sites in two cases, both kept
  minimal and robots.txt-permitted: `https://books.toscrape.com` (a public
  sandbox site built specifically for scraping practice) as the primary
  target, and a modest number of requests against
  `https://www.azurestandard.com` while investigating and verifying two
  reported bugs, the JS-rendering fallback, and category drill-down above.
