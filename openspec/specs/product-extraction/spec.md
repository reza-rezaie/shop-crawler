# product-extraction Specification

## Purpose

Extract product listings (name, price, image, URL, category/description
when available) from a fetched shop/category page's raw HTML, follow
pagination, and clearly report when a page contains no product data the
crawler can actually see.

## Requirements

### Requirement: robots.txt is evaluated using the crawler's own User-Agent
Before fetching any page on a host, the system SHALL retrieve that host's
`robots.txt` using the same descriptive User-Agent it uses for normal page
requests, and SHALL evaluate crawl permission from that response. It SHALL
NOT rely on a mechanism that fetches `robots.txt` with a different,
unconfigurable User-Agent, since a host that only blocks that other
User-Agent would then be incorrectly treated as disallowing the crawl
entirely.

#### Scenario: robots.txt reachable, no disallow for the target path
- **WHEN** a host's `robots.txt` (fetched with the crawler's own
  User-Agent) contains no rule disallowing the requested path for that
  User-Agent (or for `*`)
- **THEN** the crawl of that path SHALL proceed

#### Scenario: robots.txt disallows the target path
- **WHEN** a host's `robots.txt` disallows the requested path for the
  crawler's User-Agent (or for `*`)
- **THEN** the crawl SHALL be blocked and the crawl result SHALL report
  that it was blocked by robots.txt

#### Scenario: robots.txt unreachable
- **WHEN** a host has no `robots.txt` or it cannot be fetched at all
- **THEN** the crawl SHALL proceed, matching what a normal browser visit
  to that host would experience

### Requirement: Product-card class matching uses whole class tokens
When deciding whether an HTML element is a product-card candidate, the
system SHALL match a class hint (e.g. "product") against individual
whitespace-separated tokens of the element's `class` attribute value, and
SHALL only treat a token as a class name if it contains only letters,
digits, `-`, or `_`. The system SHALL NOT treat a match as valid merely
because the hint substring appears anywhere in the raw attribute text.

#### Scenario: Framework binding expression is not mistaken for a class
- **WHEN** an element's `class` attribute value is
  `{ 'Animate--heartPulse': product.favoriteProcessing }` (a client-side
  framework binding expression that contains the substring "product" but no
  valid class token equal to or containing "product")
- **THEN** the element SHALL NOT be treated as a product-card match

#### Scenario: Real class token still matches
- **WHEN** an element's `class` attribute value is `product_pod` or
  `product-item featured`
- **THEN** the element SHALL be treated as a product-card candidate

### Requirement: Attribute lookup respects attribute-name boundaries
When extracting an attribute's value by name (e.g. `class`), the system
SHALL only match an occurrence of `<name>="..."` whose start is preceded by
a word boundary (start of the tag's attribute list, or whitespace) so that
a different attribute whose name merely ends with the same characters
(e.g. `ng-class`) is never returned in place of the requested attribute.

#### Scenario: Differently-named attribute is not returned
- **WHEN** an element has `ng-class="..."` but no `class` attribute
- **THEN** looking up the `class` attribute on that element SHALL return no
  value, not the `ng-class` value

### Requirement: Crawl reports when a page yields no extractable products
When a fetched listing page produces zero products from every extraction
strategy AND the page's raw HTML matches common client-side application
shell markers (e.g. `ng-app`, `data-reactroot`, `id="root"`, `id="__next"`)
with little or no static content, the system SHALL attempt a JavaScript
rendering fallback (see "JavaScript rendering fallback" below) before
giving up on that page. The crawl result SHALL include a human-readable
note describing the outcome: that rendering found products, or that the
page still yielded no products even after rendering, distinct from a page
that legitimately has no matching markup for other reasons (no SPA-shell
markers detected, no note).

#### Scenario: Client-rendered page recovers products via JS rendering
- **WHEN** a listing page's fetched HTML contains an SPA shell marker,
  neither the JSON-LD nor heuristic extraction strategy finds any product
  candidates, and re-running extraction against a rendered version of the
  page finds products
- **THEN** the crawl summary SHALL include those products AND SHALL
  include a note indicating they were found by rendering the page

#### Scenario: Client-rendered page yields an explanatory note
- **WHEN** a listing page's fetched HTML contains an SPA shell marker,
  neither extraction strategy finds any products from the raw HTML, and
  none are found from the rendered HTML either (or rendering itself is
  unavailable/fails)
- **THEN** the crawl summary SHALL report zero products found for that
  page AND SHALL include a note indicating that JavaScript rendering was
  attempted and still found nothing

#### Scenario: Ordinary page with genuinely no products is unaffected
- **WHEN** a listing page's fetched HTML has no SPA shell markers and
  extraction finds zero products (e.g. an empty category)
- **THEN** the crawl summary SHALL report zero products found for that page
  with no SPA-related note, and SHALL NOT attempt JavaScript rendering

### Requirement: JavaScript rendering fallback
When triggered (see above), the system SHALL fetch the same URL using a
headless browser, allow it a bounded amount of time to finish executing
its client-side rendering, and re-run the same extraction strategies
(JSON-LD, then the class-token heuristic) against the resulting rendered
HTML instead of the original raw HTML. This SHALL only run for pages that
already produced zero products from the raw-HTML strategies; it SHALL NOT
run for every page, so pages that don't need it pay no extra cost.

#### Scenario: Rendering fallback is not used when raw HTML already has products
- **WHEN** a listing page's raw HTML already yields products from the
  JSON-LD or heuristic strategy
- **THEN** the system SHALL NOT fetch or render that page with a headless
  browser

#### Scenario: Rendered product cards are extracted the same way as static ones
- **WHEN** a rendered page's DOM contains container elements whose class
  token matches the product-card rule (e.g. a class token like
  `ProductGridItem`)
- **THEN** the system SHALL extract them using the same heuristic
  extraction logic used for static HTML, with no site-specific rules

### Requirement: Image and price extraction fall back to common dynamic-rendering patterns
When extracting a product's image, the system SHALL use an element's
`src` attribute if present, and SHALL fall back to its `ng-src` attribute
(a common Angular pattern for images whose source is resolved after
rendering) when `src` is absent. When locating a product's price text
within a candidate block, the system SHALL search `<div>` elements with a
price-hinted class token in addition to `<p>` and `<span>`.

#### Scenario: Image uses ng-src when src is absent
- **WHEN** a product card's image element has an `ng-src` attribute with a
  resolved URL but no `src` attribute
- **THEN** the extracted image URL SHALL be the `ng-src` value

#### Scenario: Price found in a div-wrapped element
- **WHEN** a product card's price text is inside a `<div>` element whose
  class token contains "price" (rather than a `<p>` or `<span>`)
- **THEN** the system SHALL still locate and parse that price text

### Requirement: Extraction strategies and pagination
The system SHALL extract product entries from a listing page's HTML by (in
order) first attempting schema.org JSON-LD `Product` data embedded in
`<script type="application/ld+json">` blocks, then falling back to a
heuristic scan for repeated container elements matching the class-token
rule above. It SHALL follow pagination (a `<link rel="next">`, or an
element whose class token includes "next" containing a link) up to a
caller-specified page limit, resolving all discovered product and image
URLs to absolute URLs relative to the page they were found on.

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
