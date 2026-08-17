## 1. Dependency setup

- [ ] 1.1 Add `playwright-python` (not `playwright` — that's the Node.js
      package on conda-forge) as a Pixi dependency.
- [ ] 1.2 Add a `playwright-install` Pixi task (`playwright install
      chromium`) and confirm it works from a clean cache.
- [ ] 1.3 Update `pixi.toml` comments and `SPEC.md`/`README.md`'s "no
      third-party Python packages" claims to reflect this addition.

## 2. Rendering fallback (native Mojo + isolated Playwright interop)

- [ ] 2.1 Create `backend/mojo_src/browser_client.mojo` with
      `render_fetch(url: String) raises -> FetchResult` (same struct
      `http_client.mojo` uses) wrapping Playwright: launch headless
      Chromium, navigate with `domcontentloaded`, fixed settle wait,
      `page.content()`, close browser.
- [ ] 2.2 In `crawler.mojo`, when a page's extraction finds zero products
      and `looks_like_client_rendered_app` matches the raw HTML, call
      `render_fetch` on the same URL and re-run both extraction
      strategies against the rendered HTML.
- [ ] 2.3 Update the crawl-notes wording to distinguish "found N products
      by rendering" vs "still nothing after rendering" vs the unchanged
      "no SPA markers, no note" case.

## 3. Extraction robustness fixes

- [ ] 3.1 In `html_extract.mojo`'s image extraction, fall back to
      `ng-src` when `src` is absent.
- [ ] 3.2 In `html_extract.mojo`'s `_find_price_text`, add `<div>` to the
      tags searched for a price-hinted class token.

## 4. Tests

- [ ] 4.1 Add a trimmed fixture of azurestandard.com's *rendered* DOM
      (representative `ProductGridItem` cards, `ng-src` image, div-wrapped
      price, breadcrumb) under `backend/mojo_src/tests/fixtures/` and a
      test proving `extract_heuristic_products` correctly extracts
      name/price/image/URL from it — offline, no live Playwright/network
      needed for the automated suite.
- [ ] 4.2 Add a regression test confirming `ng-src` fallback and
      `<div>`-price search don't change extraction on the existing
      books.toscrape.com fixture.
- [ ] 4.3 Run the full `pixi run test` suite and record results.

## 5. Live verification

- [ ] 5.1 Run `pixi run playwright-install` from this environment and
      confirm it succeeds (or is a no-op if already cached).
- [ ] 5.2 Crawl `https://www.azurestandard.com/shop/category/food/baking-pantry/26644`
      through the real running app and confirm real products (name,
      price, image, URL) are extracted and stored — not zero, not a
      bogus product.
- [ ] 5.3 Re-crawl `https://books.toscrape.com/...` (existing verified
      target) and confirm no regression: same extraction results as
      before, and no rendering fallback triggered (it has real static
      markup, zero products from raw HTML never happens there).
- [ ] 5.4 Verify in the running UI that the newly-crawled azurestandard.com
      products display correctly (name/price/image, source-site
      attribution from the earlier change) and the crawl summary's note
      reflects that rendering found them.
