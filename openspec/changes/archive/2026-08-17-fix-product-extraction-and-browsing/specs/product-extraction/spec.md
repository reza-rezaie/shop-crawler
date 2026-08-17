## Purpose

Extract product listings (name, price, image, URL, category/description
when available) from a fetched shop/category page's raw HTML, follow
pagination, and clearly report when a page contains no product data the
crawler can actually see.

## ADDED Requirements

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
with little or no static content, the crawl result SHALL include a
human-readable note that the page likely requires JavaScript rendering to
show its products, distinct from a page that legitimately has no matching
markup for other reasons.

#### Scenario: Client-rendered page yields an explanatory note
- **WHEN** a listing page's fetched HTML contains an SPA shell marker and
  neither the JSON-LD nor heuristic extraction strategy finds any product
  candidates
- **THEN** the crawl summary SHALL report zero products found for that page
  AND SHALL include a note indicating the page appears to require
  JavaScript rendering

#### Scenario: Ordinary page with genuinely no products is unaffected
- **WHEN** a listing page's fetched HTML has no SPA shell markers and
  extraction finds zero products (e.g. an empty category)
- **THEN** the crawl summary SHALL report zero products found for that page
  with no SPA-related note

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
