## Context

See `proposal.md` - Why. Live investigation confirmed two separate things
for `https://www.azurestandard.com/shop/category/food/`:

- It's a genuine 404 in the Angular app itself — `page.goto` returns HTTP
  200 (SPA convention: the server always returns the shell), but the
  network trace shows the app loading `app.404/404.*.htm`, and the
  rendered `<h1>` reads "Not found (404)". Real category paths need a
  trailing numeric ID (`/shop/category/food/flour/22474`, discovered from
  the site's own homepage navigation).
- Real category pages on this site form a tree: some paths (marked with a
  `?subcategories=true` query param in this site's own links, though the
  crawler fix here does not rely on that being present) list child
  categories instead of products; a previously-verified leaf like
  `/shop/category/food/baking-pantry/26644` lists products directly.
  Sibling/child paths extend the parent's own path with one more segment
  before the ID, e.g. parent `/shop/category/food/flour/22474`'s children
  are `/shop/category/food/flour/whole-wheat/22513` and
  `/shop/category/food/flour/gluten-free-blends/22529` — each child's path
  has the parent's path-with-its-own-ID-segment-removed
  (`/shop/category/food/flour`) as a strict prefix.

## Goals / Non-Goals

**Goals:**
- Make a crawl started on a category hub page reach the real product
  listings nested underneath it, bounded by the same page-limit the API
  already exposes — no new request parameters.
- Tell a genuinely invalid URL apart from a legitimately-empty listing in
  the crawl result, rather than reporting both the same way.
- Keep the child-link heuristic generic (URL path structure only) so it
  isn't specific to this one site's markup or query-param conventions.

**Non-Goals:**
- Crawling multiple independent category trees or an entire site's
  catalog in one request — still bounded by `max_pages`, same as today;
  a broad crawl just needs a caller-supplied larger `max_pages`.
- A configurable drill-down depth or breadth separate from the existing
  page limit. One new bounded constant (children enqueued per hub page)
  is enough for a POC; total work is already bounded by `max_pages`.
- Detecting "not found" pages by HTTP status code. This site (and SPAs
  generally) return `200` for the app shell regardless of the client-side
  route, so the only signal available post-render is page content.

## Decisions

**Generalize the crawl loop to a work queue over (pagination-links ∪
child-links), not a separate "drill-down mode."**
`crawler.mojo`'s `while` loop currently walks a single pagination chain.
Replace the `current_url`/`next_url_opt` pair with a `List[String]` queue,
seeded with `seed_url`. Each iteration pops the next URL, fetches/extracts
it (same pipeline, including the JS-rendering fallback), and enqueues:
next-page link (if this page had products), or child links (if it had
none). This reuses every existing mechanism unchanged — `visited_pages`
dedup, `max_pages` budget, `rate_limit_sleep`, `can_fetch` (checked once
against the seed host, same as today; child links discovered during a
crawl are same-host by construction of the matching rule below, so no
additional robots.txt calls are needed per child). Alternative considered:
a separate recursive "drill down" function called only for hub pages,
kept structurally distinct from pagination — rejected because pagination
and drill-down are the same operation from the budget/dedup/rate-limiting
machinery's point of view (fetch one more page, extract, decide what's
next), and a second code path would double the surface for a subtle
budget or infinite-loop bug.

**Child-link matching: URL path-stem prefix, generic, no markup/class
assumptions.** A candidate link counts as a "child" of the current page
when: same host as the current page, and its path (query/fragment
stripped) starts with the current page's own path with its last
`/`-segment removed, followed by `/`. This is exactly the real
parent→child relationship observed on the real site (see Context) and
generalizes to any hierarchical `/category/.../<id-or-slug>` URL scheme
without needing to know anything about this site's specific class names,
`?subcategories=true` convention, or markup. Alternative considered:
matching on the `?subcategories=true` query parameter this site happens
to use — rejected as site-specific and not the kind of generic heuristic
this project's extraction logic otherwise commits to (see the existing
class-token rule's own reasoning).

**Candidate links are read from whichever HTML the page already produced
for extraction** (rendered HTML if the JS-rendering fallback fired,
otherwise raw HTML) — no second fetch. A generic "every anchor href on
the page" scan (new `textutil` helper) feeds the path-stem filter; this
is deliberately unfiltered by class/hint (unlike product-card matching)
since child-category links have no consistent markup convention to key
off, only their own resolved position in the URL hierarchy.

**Not-found detection: a small heading-text heuristic, checked before the
JS-rendering fallback's own note.** After a page yields zero products
(from raw HTML, then from rendered HTML if rendering was attempted), scan
for a short heading-like element whose text is exactly "not found" / "404"
/ contains "page not found" (case-insensitive) with little surrounding
content. This is a heuristic, not a guarantee (some genuinely-styled
"no products match this filter" pages might phrase things similarly) —
acceptable because, like the existing SPA-shell note, a false positive
only ever adds a (slightly less accurate) note where one already existed;
it never suppresses real product results, since it's only consulted after
extraction already found nothing.

## Risks / Trade-offs

- [Path-stem child matching could misfire on a site whose URL scheme
  doesn't follow "child path extends parent's path-minus-its-own-last-
  segment" — e.g. flat category IDs with no hierarchical path relationship
  at all] → Falls back to finding zero child links, which is exactly
  today's "hub page, no path forward" behavior — never worse than before
  this change, only sometimes not better.
- [A hub page could link to many children; enqueuing too many at once
  could exhaust the page budget on breadth before reaching any real leaf
  listing] → Bounded per-hub-page cap (comptime constant) independent of
  the overall page limit, tuned conservatively; documented as a POC
  trade-off, easy to retune.
- [Not-found detection is a text heuristic, not exact] → See Decisions;
  strictly additive (a note), never changes what gets extracted or stored.
- [Queue-based crawling changes `crawler.mojo`'s control flow
  meaningfully] → Every existing regression test (books.toscrape.com
  pagination, azurestandard.com single-page rendering fallback) is
  re-verified against the new loop structure as part of this change's
  tasks, specifically to catch a behavior change in the common cases.

## Migration Plan

No data/schema migration, no new request/response fields beyond the
crawl-notes additions already established by prior changes. Purely an
internal crawl-loop and extraction change.
