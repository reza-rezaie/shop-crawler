## MODIFIED Requirements

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

## ADDED Requirements

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
