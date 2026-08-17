# Mojo Product Crawler — POC

A proof-of-concept product crawler + local browser. The backend and all
crawling/business logic are native **Mojo v1.0 GA**; Python is only a thin
HTTP transport shim plus a few standard-library calls Mojo doesn't natively
cover yet (sqlite3, urllib, json, html, http.server). See [SPEC.md](SPEC.md)
for the full design and the exact Mojo/Python split.

```
pixi.toml            # Mojo + task definitions (no third-party Python deps)
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
3. Browse, search by name, and filter by category/price below. Click a card
   to open the real product page.
4. Crawl the same URL again any time — existing products are updated
   in place (by product URL), never duplicated.

### One-shot crawl without the UI

```bash
pixi run crawl -- https://books.toscrape.com/
```

## Notes / POC limitations

- The crawl endpoint runs synchronously and is capped (default 3 pages,
  hard cap 20; detail-page fetches capped too) with a rate-limited request
  pace — reasonable for a small test site, not meant for large stores.
- Extraction is generic (schema.org JSON-LD, then a heuristic scan for
  "product-ish" container elements) but was only verified end-to-end
  against books.toscrape.com; other sites' markup may need small tweaks.
- Only books.toscrape.com was crawled during development/testing, in
  keeping with respecting robots.txt/rate limits on real stores.
