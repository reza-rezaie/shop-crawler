## Why

Reported: crawling `https://www.azurestandard.com/shop/category/food/`
found nothing. Investigated live (Playwright, network trace) and found two
distinct things, not one "cascade limitation" bug:

1. That exact URL doesn't exist on the site — the Angular app itself
   loads its own 404 template (`app.404/...htm`) for it; the real
   top-level path needs a numeric category ID (e.g.
   `/shop/category/food/flour/22474`), which `/shop/category/food/` is
   missing. This is not a crawler bug, but the crawler currently can't
   tell the difference between "this page is a real 404" and "this page
   legitimately has no products," so it reported the same generic
   "found nothing" note either way — leaving the actual cause invisible.
2. The user's underlying report is still correct as a real gap: this
   site's real, working category pages are themselves organized as a
   tree — a "hub" page like `/shop/category/food/flour/22474` doesn't
   list products at all, it links to child category pages
   (`/shop/category/food/flour/whole-wheat/22513`,
   `/shop/category/food/flour/gluten-free-blends/22529`, ...), which
   either list products directly or link to further children. The
   crawler only ever follows same-page pagination (`<link rel="next">`
   style) within one listing; given a hub page instead of a leaf listing,
   it has no path to the actual products underneath it. This isn't
   specific to this one site — nested category trees are a common
   e-commerce pattern.

## What Changes

- Detect when a fetched/rendered page is an actual not-found page
  (common markers: an `<h1>`-ish heading containing "not found" or "404"
  paired with a very small amount of other content) and report that
  distinctly from "page looks client-rendered but legitimately has no
  products."
- Generalize the crawl loop from a linear "fetch → maybe next page"
  walk into a small bounded queue over two kinds of discovered links:
  same-listing pagination (unchanged) and, **only for a page that itself
  yielded zero products**, "child" links — same-host links whose URL
  path is nested one or more segments under the current page's own path
  (generic path-structure heuristic, no site-specific markup/class
  assumptions). Both kinds of discovered pages are crawled through the
  existing extraction pipeline (including the JS-rendering fallback) and
  count against the same overall page budget (`max_pages`) already
  exposed in the API/UI — no new request parameters.
- Per-hub-page cap on how many child links get enqueued at once (bounded
  breadth), independent of the overall page budget (bounded total work).

## Capabilities

### Modified Capabilities
- `product-extraction`: the crawl loop's page-discovery requirement
  changes from "pagination only" to "pagination plus bounded child-category
  drill-down when a page has no products of its own," and a new
  not-found-page detection requirement is added.

## Impact

- `backend/mojo_src/textutil.mojo`: generic URL path helpers (path
  extraction, path "stem", child-link matching) and a generic "find all
  anchor hrefs on a page" scan (used for discovering candidate child
  links; not tied to any class/hint).
- `backend/mojo_src/html_extract.mojo`: not-found-page detection; a
  function to find candidate child-category links given a page's HTML
  and its own URL.
- `backend/mojo_src/crawler.mojo`: replace the linear pagination `while`
  loop with a small work queue (pagination links + child links), reusing
  existing page-budget/dedup/rate-limit/robots machinery unchanged; note
  wording for the not-found case.
- Tests: URL path-stem/child-link matching (offline, table-driven), a
  fixture-based test for not-found-page detection, and an offline test
  proving a hub page's child links get enqueued and a leaf page's
  products still work exactly as before (regression).
- `SPEC.md`/`README.md`: document the drill-down behavior and its bounds.
