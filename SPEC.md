# SPEC — Mojo Product Crawler POC

A proof-of-concept web app that crawls product listings from a shop/category
page, stores them in Postgres, and lets you browse/search/filter them
locally. Primary backend logic — crawling, HTML extraction, price parsing,
filtering, and SQL access — is written in **native Mojo v1.0 GA**. Python is
used only as a thin transport shim and for facilities Mojo does not yet
provide — almost entirely its standard library, plus two third-party
packages (Playwright, for a JS-rendering fallback — see §6; and `psycopg2`,
the Postgres client driver).

Primary test target: **https://books.toscrape.com** — a public sandbox site
built specifically for scraping practice (fictional bookstore, no robots.txt
restrictions, no login/anti-bot). The extractor is generic (see §4) but was
tuned and verified end-to-end against this site, per the instruction to
prioritize a working app over universal site support. The class-token
heuristic and JS-rendering fallback (§4) were additionally verified live
against a real production site, **https://www.azurestandard.com** — a
minimal, robots.txt-permitted set of requests made while investigating and
fixing a reported bug.

## 1. Architecture

```
┌─────────────────────┐      HTTP (localhost)      ┌───────────────────────────────┐
│  React frontend      │ ─────────────────────────▶ │  backend/server.py             │
│  (Vite, static build)│ ◀───────────────────────── │  Thin Python HTTP shim         │
└─────────────────────┘        JSON / static files   │  (http.server, stdlib only)    │
                                                       │                                 │
                                                       │  routes /api/* to ──────┐       │
                                                       └──────────────────────────┼───────┘
                                                                                  ▼
                                                       ┌───────────────────────────────┐
                                                       │  backend/src/api.mojo          │
                                                       │  Python-callable Mojo module    │
                                                       │  (built via `mojo.importer`)    │
                                                       ├───────────────────────────────┤
                                                       │  modules/  — one dir per         │
                                                       │    capability (vertical slice):  │
                                                       │    product_extraction/           │
                                                       │    category_discovery/           │
                                                       │    product_browsing/             │
                                                       │  core/  — shared kernel:          │
                                                       │    database.mojo  http_client.mojo│
                                                       │    text_utils.mojo  page_signals  │
                                                       │  — all native Mojo control flow — │
                                                       └──────────────┬────────────────┘
                                                                      │ Python interop
                                                                      │ (psycopg2, urllib,
                                                                      │  json, html, time)
                                                                      ▼
                                                       ┌───────────────────────────────┐
                                                       │  Postgres (pixi-managed local   │
                                                       │  instance, or PGHOST/PGPORT/…)  │
                                                       └───────────────────────────────┘
```

Two processes only: the static-built React app served as files, and a single
Python process whose job is to (a) speak raw HTTP and (b) call into Mojo. All
routing decisions still happen in Python (it owns the socket), but every
request handler immediately delegates to a Mojo function that does the actual
work and returns a plain dict/list, which the shim JSON-encodes. No
FastAPI/Flask/Django — `http.server.ThreadingHTTPServer` from the standard
library is the entire "framework".

Mojo → Python direction (`from std.python import Python`) is used *inside*
Mojo code to reach stdlib facilities (sqlite3, urllib). Python → Mojo
direction is used once, at process start, when `server.py` does
`import mojo.importer; import api` — this compiles `api.mojo` (and everything
it imports) into a native Python extension module on the fly, backed by
Mojo's official `PythonModuleBuilder`. From that point on, `api.<function>()`
calls are calls into compiled Mojo code, not a subprocess or RPC.

## 2. Database model

Postgres, one table (plus `site_categories` — see
`openspec/specs/category-discovery/spec.md`):

```sql
CREATE TABLE products (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_url     TEXT NOT NULL UNIQUE,   -- de-dup key
    name            TEXT NOT NULL,
    price           DOUBLE PRECISION,       -- normalized numeric price, nullable
    currency        TEXT,                   -- symbol/code found near the price, e.g. "£"
    image_url       TEXT,
    category        TEXT,                   -- from breadcrumb, when available
    description     TEXT,                   -- from product detail page, when available
    source_listing_url TEXT NOT NULL,       -- the shop/category page this was crawled from
    first_seen_at   TEXT NOT NULL,          -- ISO timestamp, set once
    last_seen_at    TEXT NOT NULL           -- ISO timestamp, updated every re-crawl
);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_products_price ON products(price);
```

Re-crawling the same listing does an **upsert keyed on `product_url`**
(`INSERT ... ON CONFLICT (product_url) DO UPDATE`), so existing products are
refreshed in place (price/name/image/description/last_seen_at) instead of
duplicated — one atomic statement, not a separate SELECT-then-branch.

Local dev/CI run against a **pixi-managed local Postgres instance** (no
Docker, no manual install) — see `scripts/pg_local.sh`, started automatically
by `pixi run dev`/`serve`/`test`. Connection settings come from the standard
libpq env vars (`PGHOST`/`PGPORT`/`PGDATABASE`/`PGUSER`/`PGPASSWORD`), which
`scripts/activate.sh` defaults to that local instance. Pinned to Postgres
17.x (`pixi.toml`): conda-forge's 18.x `postgresql`/`libpq` build links
`liburing`, whose mere presence in the pixi environment crashes Mojo's
compiled Python-extension-module loading (`import mojo.importer; import
api`) — confirmed by bisecting the exact dependency that introduces it.

## 3. API endpoints

All under `http://localhost:8000`, served by `backend/server.py`:

| Method | Path                | Description |
|--------|----------------------|-------------|
| GET    | `/api/health`        | `{status, product_count}` — liveness + row count |
| POST   | `/api/crawl`         | Body: `{"url": "...", "max_pages": 3, "fetch_descriptions": true}`. Runs a crawl synchronously and upserts results. Returns a summary: pages crawled, products created/updated, errors, and `notes` (e.g. a page that looks client-rendered and yielded no products — see `openspec/changes/fix-product-extraction-and-browsing/`). |
| GET    | `/api/products`      | Query params: `search`, `category`, `source_host`, `min_price`, `max_price`, `page`, `page_size`. Returns `{items, total, page, page_size}`; each item includes `source_host` (the site it was crawled from, derived from `source_listing_url`). |
| GET    | `/api/categories`    | Distinct non-null categories currently in the DB, for the filter dropdown. |
| GET    | `/api/sources`       | Distinct source-site hosts currently in the DB, for the site filter dropdown. |
| GET    | `/` and static paths | Serves the built React app from `frontend/dist`. |

The crawl endpoint is intentionally synchronous (simple architecture for a
POC): it blocks until the crawl finishes, capped at `max_pages` (default 3,
hard cap 20) and a rate-limited request pace, so it returns in a few seconds
for the test site.

## 4. Crawler approach

1. **Input**: any shop/category/listing page URL (e.g. the site homepage or
   a category page like `.../category/books/mystery_3/index.html`).
2. **Politeness**: check `urllib.robotparser` against the seed host before
   fetching anything; fixed descriptive User-Agent
   (`MojoCrawlerPOC/1.0 (+educational, single-host, rate-limited)`); ~0.5s
   delay between requests; 10s request timeout; hard caps on pages and on
   product-detail fetches per crawl run.
3. **Per listing page**:
   - Fetch HTML.
   - **Extraction, tried in order** (native Mojo string scanning over the
     raw HTML — no DOM library):
     a. **JSON-LD** — scan for `<script type="application/ld+json">` blocks,
        parse with Python's `json` module, use entries whose `@type` is
        `Product` (schema.org). Most robust when present (common on
        Shopify/WooCommerce stores) but not exercised by books.toscrape.com,
        which has none — included for generality and documented as
        implemented-but-not-live-tested.
     b. **Heuristic block scan** (the path actually exercised against
        books.toscrape.com) — find repeated container tags
        (`<article>`/`<li>`/`<div>`) whose `class` attribute has a token
        matching "product" (whole-token match, not a raw substring — a
        JS-framework binding expression like
        `class="{ 'x': product.y }"` isn't a real class and doesn't
        count), depth-match to the closing tag, then within each block
        pull the first `<a href>` (product URL), the `<img alt/src>` or
        `ng-src` fallback (name/image fallback), an `<h1>`–`<h6><a>`
        (name), and the first `<p>`/`<span>`/`<div>` with a price-hinted
        class or currency-looking substring (price text).
     c. **JS-rendering fallback** — if both strategies above find zero
        products on a page AND its raw HTML carries a common client-side
        app-shell marker (`ng-app`, `data-reactroot`, `id="root"`,
        `id="__next"`, `data-v-app`), fetch the same URL again by actually
        rendering it in headless Chromium (Playwright), and re-run
        strategies (a)/(b) against the *rendered* HTML instead. Verified
        end-to-end against `https://www.azurestandard.com` (an AngularJS
        SPA with no product markup in its raw HTML at all): the real
        product cards' rendered markup (`class="ProductGridItem ..."`)
        matches the same class-token heuristic unchanged. Only triggered
        for pages that need it — a page whose raw HTML already has
        products never pays this cost.
   - **Category**: breadcrumb `<ul class="breadcrumb">` last item, when
     present on the listing page.
   - **Not-found detection**: if a page yields zero products, check
     whether its content is itself a "not found"/404 page (a short
     heading mentioning "not found" or "404") before anything else below
     — reported distinctly, so an invalid/mistyped URL isn't confused
     with a real page that legitimately has no products.
   - **Pagination**: look for `<link rel="next">`, then any element whose
     `class` contains "next" with a nested `href`; resolve relative to
     absolute via `urllib.parse.urljoin`; stop on no next link, repeated
     URL, or `max_pages`.
   - **Category drill-down**: if a page (not a 404) yields zero products
     of its own, look for same-host links whose URL path is nested under
     the page's own path (e.g. `/shop/category/food/flour/22474` →
     `/shop/category/food/flour/whole-wheat/22513`) and crawl a bounded
     number of them the same way — lets a crawl started on a category
     "hub" page (one that only links to narrower categories, common on
     large e-commerce sites) reach the real listings underneath it.
     Pagination pages and drill-down pages share one page-budget/dedup
     queue (`max_pages` covers both). Verified end-to-end against a real
     hub page on `https://www.azurestandard.com`: a category with zero
     products of its own correctly drilled into several of its real
     child categories and found real products in each.
4. **Per product** (dedup'd by URL within the run): optionally fetch the
   detail page (`fetch_descriptions`, capped) to pull `description` and a
   more precise `category` from its breadcrumb.
5. **Price normalization** (native Mojo): strip currency symbols/whitespace,
   drop thousands separators, parse the remaining digits/`.` as `Float64`;
   the leading non-digit run is kept separately as `currency`.
6. **Store**: upsert each product into Postgres (§2).

## 5. Native Mojo

Everything under `backend/src/`, organized as a **modular monolith with
vertical slices**: one `modules/<capability>/` directory per
`openspec/specs/` capability, each owning its own request handling and
business logic, plus a `core/` shared kernel for what's genuinely used by
more than one capability (all in one Postgres instance, one HTTP-fetch
layer). See `openspec/changes/chg-0001-2026-08-21-modular-monolith-vertical-slice/`
for the restructuring rationale — this was originally one flat directory of
files organized by technical layer.

```
backend/src/
├── api.mojo                          # only file exporting PyInit_api(); pure wiring +
│                                        health/migrate_* (not feature-owned, see below)
├── core/                              # shared kernel, not a module
│   ├── models.mojo                     # Product struct and related value types
│   ├── http_client.mojo                 # urllib/robotparser wrappers, rate-limited fetch loop
│   ├── browser_client.mojo               # JS-rendering fallback (headless Chromium/Playwright)
│   ├── text_utils.mojo                    # byte-level string/HTML scanning helpers
│   ├── database.mojo                       # schema init, upsert, filtered query building (psycopg2 via interop)
│   ├── page_signals.mojo                    # SPA-shell/not-found/pagination/child-link detection
│   └── request.mojo                          # PythonObject request/param-dict parsing helpers
└── modules/
    ├── product_extraction/                # crawl orchestration + HTML→Product extraction
    │   ├── crawler.mojo                      # orchestrates one crawl run
    │   ├── extraction.mojo                    # JSON-LD + heuristic product extraction, breadcrumb, description
    │   └── pricing.mojo                        # price-string -> (Float64, currency) normalization
    ├── category_discovery/                # site category-tree crawl, independent of product crawling
    │   └── discovery.mojo
    └── product_browsing/                  # query/filter/list already-stored products
        └── browsing.mojo
```

`page_signals.mojo` lives in `core/` rather than under `product_extraction/`
because `category_discovery` needs the same "is this page really rendered /
a 404 / does it have more pages" signals crawling does, even though it
extracts no products of its own — putting it in `core/` avoids one module
importing another module's internals.

This is essentially the entire backend: request handling logic, HTML
parsing/extraction, price parsing, pagination, dedup/upsert decisions,
filtering/search query construction, and response shaping are all Mojo code.

## 6. Where Python interoperability is necessary

Mojo v1.0 GA has no stable stdlib modules for sockets/HTTP serving, an HTTP
client, HTML/JSON parsing, or a database driver, so the following are Python
standard library calls made *from inside Mojo* via `from std.python import
Python; Python.import_module(...)`:

| Need | Python module used | Why not native Mojo |
|---|---|---|
| HTTP client requests | `urllib.request` (stdlib) | No stable Mojo HTTP client |
| robots.txt check | `urllib.robotparser` (stdlib) | Reuse a correct, well-tested parser rather than reimplement |
| URL joining | `urllib.parse` (stdlib) | No stable Mojo URL library |
| JSON-LD parsing | `json` (stdlib) | No native Mojo JSON parser yet |
| HTML entity unescaping | `html` (`html.unescape`, stdlib) | Small stdlib convenience, avoids reimplementing entity tables |
| Storage | `psycopg2` (**third-party Python package**, via Pixi) | No native Mojo Postgres driver |
| Rate-limit delay | `time.sleep` (stdlib) | No stable Mojo sleep primitive exposed for this use |
| JS-rendering fallback | `playwright.sync_api` (**third-party Python package**, `playwright-python` via Pixi) | No Mojo (or pure-HTTP) way to execute a page's client-side JavaScript; isolated entirely to `browser_client.mojo`, only invoked as a fallback for pages that need it |

Separately, `backend/server.py` is a **plain Python file**, not Mojo calling
out — it exists because Mojo 1.0 GA has no mature HTTP *server* library
(the one community option, `lightbug_http`, does not yet build against the
1.0 GA compiler — verified during setup). It is intentionally minimal: parse
the request line/query string/body, call one `api.*` Mojo function, JSON-encode
the result, and (for non-`/api` paths) serve static files from
`frontend/dist`. It contains no product/crawling/filtering logic — that all
lives in Mojo and is reached via `import mojo.importer`, which compiles
`api.mojo` into a real Python extension module (Mojo's official
`PythonModuleBuilder` mechanism) rather than shelling out or reimplementing
the app in Python.

No pip/Poetry/venv is used anywhere; Pixi manages the whole toolchain as
Conda packages — the Python interpreter that ships as part of the
`mojo`/`mojo-python` packages, the two third-party Python packages above
(`playwright-python`, `psycopg2`), and the Postgres server itself
(`postgresql`, providing `initdb`/`pg_ctl`/`psql` for `scripts/pg_local.sh`).

## 7. Implementation steps

1. ~~Provision Mojo v1.0 GA + Python via Pixi; confirm `Python.import_module`,
   SQLite upserts, `urllib` fetches, and the `mojo.importer` Python↔Mojo
   bridge all work in this environment (a directory-with-spaces path issue
   required pinning `MOJO_PYTHON_LIBRARY` in a Pixi activation script).~~
2. `mojo_src/textutil.mojo` + `pricing.mojo` — string/price primitives, unit-
   tested against saved sample HTML from books.toscrape.com.
3. `mojo_src/html_extract.mojo` — listing/detail extraction + pagination,
   verified against the same samples.
4. `mojo_src/http_client.mojo` + `db.mojo` — networking and storage layers.
5. `mojo_src/crawler.mojo` + `api.mojo` — orchestration and the Python-facing
   surface.
6. `backend/server.py` — HTTP routing shim + static file serving.
7. `frontend/` — Vite + React app: URL input + crawl button, product grid,
   search box, category/price filters, click-through to original product
   page.
8. End-to-end run against `https://books.toscrape.com`, re-crawl to verify
   upsert (no duplicates), README with run instructions.

### Assumptions made without asking
- **React via Vite**, not Next.js: this POC has no server-side rendering or
  routing needs — it's one page talking to a local JSON API — so plain
  React keeps the stack simpler while still matching "React" in the
  preferred stack. Vite's static `dist/` build is served directly by the
  Python shim, avoiding a second server/CORS setup.
- **Synchronous crawl endpoint** with page/detail-fetch caps, rather than a
  background job queue — simplest thing that works for a POC against a
  small test site.
- Only the standard library was needed on the Python side at first; the
  JS-rendering fallback later added the one third-party dependency this
  project has (`playwright-python`, via Pixi's regular `[dependencies]` —
  it's a Conda package, not a `[pypi-dependencies]` one).
