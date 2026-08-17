## Context

See `proposal.md` - Why. Live investigation against
`https://www.azurestandard.com/shop/category/food/baking-pantry/26644`
(rendered with Playwright, saved for reference): 21 real product cards
render as `<div class="ProductGridItem LoadingOverlay-container" ...>`,
which already matches the existing class-token heuristic
(`product-extraction`'s "class token" rule: `ProductGridItem` contains
"product" case-insensitively and is a valid alnum token) with zero changes
needed to the matching rule itself. The only extraction gaps found: the
lazy-loaded product image uses `ng-src` instead of `src` (no plain `src`
attribute present at all), and the price lives in
`<div class="ProductGridItem-price">` rather than a `<p>`/`<span>`. The
product link itself is a real, static `href` (Angular apps commonly keep a
real `href` alongside `ui-sref`/`ng-click` for SEO and right-click/open-in-
new-tab support), so no change was needed there. Breadcrumb category
extraction also already matches (`class="ShopBreadcrumbs-ul"` contains
"breadcrumb" case-insensitively).

Timing measured directly (headless Chromium via Playwright, this
environment): browser launch ~1.3s, navigate + 2.5s settle wait ~2.2s,
close ~0.15s — under 4s total per page fetch, and confirmed by direct
measurement that all 21 product cards are present in the DOM within
~2.5s after `domcontentloaded` fires (`networkidle` never fires on this
site — continuous background XHR/analytics traffic — so it's not a usable
wait condition here or, in general, for arbitrarily many other sites).

## Goals / Non-Goals

**Goals:**
- Make a real, previously-unreachable site's product listing actually
  extractable, using the existing extraction logic unchanged (proving the
  heuristic generalizes) plus two small, generically-justified robustness
  fixes.
- Keep zero added cost for the (common) case of a page that doesn't need
  rendering.

**Non-Goals:**
- Infinite-scroll / "load more" pagination driven by client-side state
  rather than a real link. azurestandard.com's category pages did not
  expose this during investigation (a fixed page of ~21 items rendered
  without further interaction), but a site that does would need scripted
  scrolling/clicking this change does not add. Documented as a limitation.
- A configurable/tunable rendering wait strategy, retry policy, or
  headed/visible-browser mode. Fixed constants, POC scope.
- Rendering for product *detail* pages (descriptions). Only listing-page
  extraction gets the fallback in this change; detail-page description
  fetches remain raw-HTTP-only, same as before at author's judgement of
  a proportionate scope for this change.

## Decisions

**One new Python dependency, isolated to one Mojo file.**
`playwright-python` (conda-forge; note the *Python* bindings are this
package — the plain `playwright` conda package is the Node.js CLI/library
and does not expose a Python-importable module, a real gotcha hit while
setting this up) is added as a Pixi dependency. All Playwright interop
lives in the new `backend/mojo_src/browser_client.mojo`, mirroring
`http_client.mojo`'s existing pattern (thin Mojo wrapper, Python only for
what Mojo can't do, documented inline) — every other file keeps working
with plain `FetchResult` values and doesn't know or care whether a given
page's HTML came from `urllib` or a rendered browser.

**Fallback trigger reuses the existing SPA-shell heuristic, not a new
classifier.** `looks_like_client_rendered_app` already exists
(`html_extract.mojo`, from the previous change) and is exactly "zero
products found + app-shell markers present" — the same signal that used
to only produce a note now also triggers one retry via
`browser_client.render_fetch`. No new detection logic; reusing this also
means false-shell-positives cost one extra render attempt (which still
correctly finds zero products and reports so), never a wrong answer.

**Launch a fresh headless Chromium per fallback page, not a
crawl-lifetime shared browser instance.** Alternative considered: launch
once per crawl and reuse across pages needing the fallback, saving the
~1.3s launch cost on subsequent pages. Rejected for this change: it would
mean threading a browser handle through `crawler.mojo`'s control flow (a
resource that must be closed on every exit path, including errors),
adding real complexity for a fallback path that — per the trigger rule
above — only ever runs on the minority of pages that need it, and within
Mojo's page-limit caps (default 3, hard cap 20) the worst case is still
low tens of seconds. Simpler and safer for a POC; revisit if profiling on
a real multi-page JS site shows it matters.

**Fixed navigate-then-wait timing, not an adaptive/content-based wait.**
`page.goto(url, wait_until="domcontentloaded")` then a fixed settle delay
(comptime constant, set from the measured timing above with headroom) then
`page.content()`. Alternatives considered and rejected: `networkidle` (has
no reliable "idle" state on sites with continuous background XHR/analytics
— confirmed it never fires on the real target site, so it degenerates to
"always wait the full timeout", which is strictly worse than a shorter
fixed wait for that site and no better on others); waiting for a specific
selector (would require site-specific knowledge, against this project's
"no site-specific hardcoding" approach — the whole point here is generic
class-token matching after rendering).

**Extraction robustness fixes are generic, not azurestandard.com-specific.**
`ng-src` is a documented, common AngularJS pattern for lazy/deferred image
sources (not unique to this site), and searching `<div>` for a
price-hinted class alongside `<p>`/`<span>` is a strict superset of the
existing behavior with no new false-positive risk (it's scoped to inside
an already-matched product block, not a page-wide search). Both are
justified independent of this one site.

## Risks / Trade-offs

- [Headless Chromium adds real weight: a new native dependency, a browser
  binary download step, and multi-second-per-page latency] → Scoped
  strictly to the already-existing "zero products + SPA shell" fallback
  path; every other crawl (the common case, including every site verified
  in earlier changes) is entirely unaffected in dependencies-at-runtime,
  behavior, or speed.
- [Fixed settle-wait timing is a heuristic tuned against one real site; a
  slower-rendering site could still yield an incomplete DOM] → Same
  failure mode as before this change for such a site (reports "still
  nothing after rendering" rather than a wrong answer), not a regression;
  the constant is isolated to one place to retune later.
- [Per-page browser launch cost could matter more on a JS-heavy paginated
  site than it did on the one investigated] → Accepted for this POC (see
  Decisions); page-limit caps already bound the worst case.
- [`playwright install chromium` is a manual, undocumented-until-now setup
  step outside Pixi's package management] → Added as an explicit Pixi task
  (`playwright-install`) and called out in README so it isn't a silent
  prerequisite.

## Migration Plan

No data migration. Existing crawls/behavior for non-JS-rendered sites are
unchanged. New setup step required once per environment:
`pixi run playwright-install` (downloads the Chromium binary Playwright
needs; not part of `pixi install` since browser binaries aren't Conda
packages).
