## MODIFIED Requirements

### Requirement: Extraction strategies and pagination
The system SHALL extract product entries from a listing page's HTML by (in
order) first attempting schema.org JSON-LD `Product` data embedded in
`<script type="application/ld+json">` blocks, then falling back to a
heuristic scan for repeated container elements matching the class-token
rule above. It SHALL follow pagination (a `<link rel="next">`, or an
element whose class token includes "next" containing a link) up to a
caller-specified page limit, resolving all discovered product and image
URLs to absolute URLs relative to the page they were found on.

When a fetched page yields zero products of its own (after the
not-found-page check and JS-rendering fallback), the system SHALL also
look for "child" links on that page — same-host links whose URL path is
nested one or more segments under the current page's own URL path — and
enqueue a bounded number of them as further pages to crawl, so a crawl
started on a category "hub" page (one that only links to narrower
category pages rather than listing products itself) can still reach the
real product listings beneath it. Child pages discovered this way SHALL
count against the same overall page limit as pagination pages, and SHALL
go through the same extraction pipeline (including further drill-down if
a child page is itself a hub).

#### Scenario: JSON-LD product is extracted when present
- **WHEN** a listing page embeds a schema.org `Product` in a JSON-LD script
  block with name, price, and image
- **THEN** the system SHALL extract a product with that name, numeric
  price, and image URL without needing the heuristic strategy

#### Scenario: Pagination is followed up to the page limit
- **WHEN** a listing page links to a next page and the crawl's page limit
  has not yet been reached
- **THEN** the system SHALL fetch the next page and continue extraction
  there, and SHALL stop once the page limit is reached or no further next
  link is found

#### Scenario: Relative image and product URLs are resolved to absolute
- **WHEN** an extracted product's URL or image URL is relative to the page
  it was found on
- **THEN** the stored URL SHALL be an absolute URL resolved against that
  page's URL

#### Scenario: A hub page with no products of its own is drilled into
- **WHEN** a fetched page yields zero products and contains links whose
  path is nested under the current page's own path (e.g. the page at
  `/shop/category/food/flour/22474` links to
  `/shop/category/food/flour/whole-wheat/22513`)
- **THEN** the system SHALL enqueue a bounded number of those child links
  as further pages to crawl, within the overall page limit

#### Scenario: A leaf listing page is unaffected
- **WHEN** a fetched page already yields products of its own
- **THEN** the system SHALL NOT look for or enqueue child links on that
  page

#### Scenario: Unrelated same-host links are not treated as children
- **WHEN** a page yields zero products and contains same-host links whose
  path is not nested under the current page's own path (e.g. a footer or
  global nav link)
- **THEN** the system SHALL NOT enqueue those links as child pages

## ADDED Requirements

### Requirement: Not-found pages are reported distinctly
When a fetched or rendered page's content is itself a "not found" page
(the requested URL does not correspond to a real page on the site, as
opposed to a real page that legitimately has no products), the crawl
result SHALL report that distinctly from the general "found nothing, even
after rendering" note, so a URL typo or invalid path is diagnosable
separately from a genuinely empty listing.

#### Scenario: A rendered not-found page is reported as such
- **WHEN** a crawled URL's rendered content is a not-found/404 page (e.g.
  a heading containing "not found" or "404" and little other content)
- **THEN** the crawl result SHALL include a note indicating that URL does
  not correspond to a real page on the site, distinct from the
  client-rendered-with-no-products note

#### Scenario: A genuinely empty listing is not reported as not-found
- **WHEN** a crawled page is a real listing page with zero products (e.g.
  an empty category) and is not a not-found page
- **THEN** the crawl result SHALL NOT include a not-found note
