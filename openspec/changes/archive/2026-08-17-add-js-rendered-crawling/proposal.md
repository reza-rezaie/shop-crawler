## Why

The previous change made this crawler correctly *detect and report* pages
that render their product listings client-side (e.g.
`https://www.azurestandard.com/shop/category/...`, an AngularJS SPA with no
product markup in the raw fetched HTML) instead of silently returning
nothing or misreading unrelated markup as a product. It did not make those
pages actually crawlable — this change closes that gap using Playwright,
per this project's own stated stack ("Playwright only if JavaScript
rendering is required" — this is that case).

Investigated live against the real site
(`https://www.azurestandard.com/shop/category/food/baking-pantry/26644`):
once rendered, the page's product cards (`class="ProductGridItem ..."`)
already match this crawler's existing class-token heuristic unchanged —
only two small extraction robustness gaps stand in the way (Angular's
`ng-src` instead of a plain `src` on lazy images, and a price wrapped in a
`<div>` instead of a `<p>`/`<span>`). No site-specific hardcoding needed.

## What Changes

- Add a headless-Chromium rendering fallback (via Playwright's Python
  bindings — the one Python package added in this change; no other new
  dependency) used **only** when a fetched page yields zero products from
  the existing (fast, no-browser) extraction strategies **and** looks like
  a client-rendered app shell. Ordinary/static pages are unaffected and
  pay no extra cost.
- Re-run the existing extraction strategies (JSON-LD, then the heuristic
  class-token scan) against the rendered HTML — no new extraction
  strategy, just a new HTML source to run the same one over.
- Fix two extraction gaps found live on the real target site: fall back to
  an element's `ng-src` attribute when `src` is absent (lazy-loaded
  images, common in Angular apps), and include `<div>` among the tags
  searched for a price-hinted element (not just `<p>`/`<span>`).
- Crawl summary notes now distinguish "found nothing, and JS rendering
  didn't help either" from the prior "found nothing" case, so it's clear
  rendering was attempted.
- **BREAKING (setup only, not API)**: this project no longer needs *zero*
  third-party Python packages — running JS-rendered fallback crawls
  requires the `playwright-python` Pixi dependency (added) and a one-time
  `playwright install chromium` step (new Pixi task). Sites that don't
  need rendering are unaffected either way.

## Capabilities

### Modified Capabilities
- `product-extraction`: adds a JS-rendering fallback path and the two
  extraction-robustness fixes above; the crawl-notes requirement is
  updated to reflect the new "tried rendering, still nothing" case.

### New Capabilities
None — this extends the existing extraction capability rather than adding
a new user-facing one.

## Impact

- `pixi.toml`: add `playwright-python` dependency, add a
  `playwright-install` task, update the "no third-party Python packages"
  claim in comments/docs.
- `backend/mojo_src/browser_client.mojo` (new): the one file with
  Playwright Python interop — launches headless Chromium, navigates,
  waits, returns rendered HTML in the same `FetchResult` shape
  `http_client.fetch` already returns, so callers don't need to
  special-case it.
- `backend/mojo_src/crawler.mojo`: trigger the fallback when a page's
  extraction finds zero products and the SPA-shell heuristic matches;
  re-run extraction on the rendered HTML; update notes wording.
- `backend/mojo_src/html_extract.mojo` / `textutil.mojo`: `ng-src`
  fallback, `<div>` added to price-tag candidates.
- Tests: fixture-based extraction tests using a trimmed real sample of
  azurestandard.com's *rendered* DOM (no live Playwright/network needed
  in the automated suite); live verification (real Playwright run against
  the real site) done manually and recorded in the PR, same as the
  previous change.
- `README.md` / `SPEC.md`: document the new setup step and the
  render-fallback behavior; update/remove the "zero third-party Python
  packages" claim.
