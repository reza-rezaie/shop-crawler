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

For any fetched page that is not a not-found page, the system SHALL also
look for "child" links on that page — same-host links whose URL path is
nested one or more segments under the current page's own URL path — and
enqueue a bounded number of them as further pages to crawl, regardless of
whether that page also yielded products of its own. This lets a crawl
started on a category page that shows some products directly *and* links
to narrower subcategories (common on department/top-level category pages)
still reach everything beneath it, not just what's shown at that level.
Child pages discovered this way SHALL count against the same overall page
limit as pagination pages, and SHALL go through the same extraction
pipeline (including further drill-down if a child page is itself a hub).

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
- **WHEN** a fetched page has products of its own and no links whose path
  is nested under its own path (a genuine leaf listing, with no real
  subcategories to find)
- **THEN** the system SHALL NOT enqueue any child pages for it — there
  are none to find, so behavior is unchanged from before child-link
  discovery existed

#### Scenario: A page with both its own products and child links gets both
- **WHEN** a fetched page yields products of its own (e.g. a
  department-level page like `/shop/category/food/21244` showing a
  handful of featured products) and also contains links whose path is
  nested under its own path (its subcategories)
- **THEN** the system SHALL both store the products found on that page
  AND enqueue a bounded number of its child links as further pages to
  crawl

#### Scenario: Unrelated same-host links are not treated as children
- **WHEN** a page contains same-host links whose path is not nested under
  the current page's own path (e.g. a footer or global nav link)
- **THEN** the system SHALL NOT enqueue those links as child pages
