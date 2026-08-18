## Purpose

Map a site's category structure — URLs, names, and parent/child
relationships — ahead of and independent from product extraction, so it
can be discovered once, persisted, and browsed before any product crawl
targets it.

## ADDED Requirements

### Requirement: Discovery walks same-host category links breadth-first
Given a seed URL, the system SHALL discover candidate category pages by
following same-host links whose URL path is nested under the URL path of
the page they were found on (the same path-nesting rule product
extraction's drill-down already uses), visiting discovered pages in
breadth-first order. Each discovered link SHALL be recorded as a category
node with: its URL, a name, the URL of the page it was found on (its
parent), and its host.

#### Scenario: Nested category tree is discovered
- **WHEN** discovery starts at a hub page that links to subcategory pages,
  which themselves link to further subcategory pages
- **THEN** all reachable nodes within the discovery budget SHALL be
  recorded, each with its correct parent

#### Scenario: Unrelated same-host links are not treated as categories
- **WHEN** a visited page contains same-host links whose path is not
  nested under that page's own path (e.g. a footer or global nav link)
- **THEN** those links SHALL NOT be recorded as category nodes

#### Scenario: A category node's name falls back to its URL when anchor text is empty
- **WHEN** the anchor linking to a candidate category page has no visible
  text (e.g. it wraps only an image)
- **THEN** the system SHALL still record the node, using a name derived
  from its URL path instead of leaving the name empty

#### Scenario: A page's own pagination link is not treated as a category
- **WHEN** a visited page links to its own next-page-in-the-same-listing
  target (the same link product extraction's pagination-following would
  use)
- **THEN** that link SHALL NOT be recorded as a category node, even
  though its URL path is nested under the current page's path (this is a
  best-effort exclusion: a page reached only via a "previous"-style link
  to a URL distinct from the one it paginates forward from is not
  guaranteed to be excluded)

#### Scenario: A fragment-only variant of an already-found link is not a separate node
- **WHEN** a page links to the same URL twice, once plain and once with a
  trailing `#fragment` (e.g. `.../8428` and `.../8428#reviews`)
- **THEN** both SHALL be treated as the same candidate child, not
  recorded as two distinct category nodes

### Requirement: Discovery does not perform product extraction
While visiting a page to find further category links, the system SHALL
NOT run extraction that persists product rows, fetch product detail
pages, or fetch product descriptions. The only extraction work discovery
performs is checking whether a page's own HTML shows product-card markup
(see the product-presence signal requirement below), and its result is
never stored as a product record.

#### Scenario: Discovery run creates no product records
- **WHEN** a discovery crawl visits pages that contain product listings
- **THEN** no rows SHALL be created or updated in the product catalog as a
  result of that discovery run

### Requirement: JavaScript rendering fallback for pages with no static navigation
When a visited page's raw HTML carries a common client-side framework's
app-shell marker (the same detection product extraction uses) and yields
zero candidate child links, the system SHALL attempt to fetch that page
by rendering it in a headless browser (the same rendering mechanism
product extraction uses) and re-evaluate that page's category links and
product-presence signal from the rendered HTML instead. A page whose raw
HTML already yields at least one candidate child link SHALL NOT be
rendered.

#### Scenario: An SPA category hub's real links are found via rendering
- **WHEN** a visited page's raw HTML carries an SPA-shell marker and its
  raw HTML yields zero candidate child links
- **THEN** the system SHALL render that page and record whatever
  candidate child links and product-presence signal the rendered HTML
  yields, with a note that rendering was used

#### Scenario: A page with real static links is never rendered
- **WHEN** a visited page's raw HTML already yields at least one
  candidate child link
- **THEN** the system SHALL NOT fetch or render that page with a
  headless browser

#### Scenario: Rendering finds nothing either
- **WHEN** a visited page's raw HTML carries an SPA-shell marker, yields
  zero candidate child links, and the rendered HTML also yields zero
  candidate child links (or rendering itself fails)
- **THEN** the system SHALL treat that page as having no further children
  this run and SHALL include a note describing the outcome

### Requirement: Product-presence signal is captured at no extra fetch cost
For each category node whose page the system actually fetches (to look
for further child links), the system SHALL also check that same
already-fetched HTML for product-card markup (the existing class-token
heuristic) and record whether the page shows its own products, without
issuing any additional request for that page. A node that was recorded
from a parent's link but not itself fetched (e.g. because the discovery
budget was reached first) SHALL have this signal recorded as unknown
rather than false.

#### Scenario: A hub page with its own products is flagged
- **WHEN** a fetched category page's HTML matches the product-card
  heuristic
- **THEN** that node's product-presence signal SHALL be recorded as true

#### Scenario: A pure router hub page is flagged as having no products
- **WHEN** a fetched category page's HTML has no product-card matches but
  does have further child category links
- **THEN** that node's product-presence signal SHALL be recorded as false

#### Scenario: A node past the discovery budget has an unknown signal
- **WHEN** a category node is discovered (named and linked to its parent)
  but the discovery budget is exhausted before that node's own page is
  fetched
- **THEN** that node's product-presence signal SHALL be recorded as
  unknown, not false

### Requirement: Discovery is bounded and results are upserted, not duplicated
A discovery crawl SHALL be bounded by its own page-visit budget and a
per-page cap on how many child links it enqueues at once, independent of
a product crawl's `max_pages`. Recording a category node SHALL upsert by
URL: running discovery again against a site already represented in the
table SHALL update existing nodes and add newly-reached ones rather than
creating duplicate rows for the same URL.

#### Scenario: Re-running discovery extends a previously partial tree
- **WHEN** an earlier discovery run stopped partway through a site's tree
  because its budget was reached, and discovery is run again from the
  same seed
- **THEN** nodes already recorded SHALL NOT be duplicated, and nodes
  reachable within the new run's budget that were not reached before
  SHALL be added

### Requirement: Not-found pages are excluded from the discovered tree
When a page visited during discovery is itself a "not found" page (per
the same detection product extraction uses), the system SHALL NOT record
it as a category node and SHALL NOT look for further child links from it.

#### Scenario: A broken category link is not recorded
- **WHEN** discovery follows a link whose target page is a not-found page
- **THEN** no category node SHALL be recorded for that URL, and discovery
  SHALL NOT continue past it

### Requirement: Discovery respects robots.txt
Before fetching any page during discovery, the system SHALL evaluate
crawl permission the same way product extraction does (the host's
`robots.txt`, fetched with the crawler's own User-Agent).

#### Scenario: Disallowed seed URL is not crawled
- **WHEN** a discovery request's seed URL is disallowed by that host's
  `robots.txt`
- **THEN** the system SHALL NOT fetch it and SHALL report that discovery
  was blocked by robots.txt

### Requirement: A site's discovered category tree can be browsed
The system SHALL provide a way to view all category nodes discovered for
a given host, including each node's name, URL, parent, and
product-presence signal.

#### Scenario: Viewing a host with a discovered tree
- **WHEN** a host has one or more category nodes recorded
- **THEN** the view SHALL show them organized by their parent/child
  relationships

#### Scenario: Viewing a host with no discovered categories yet
- **WHEN** a host has no category nodes recorded
- **THEN** the view SHALL indicate none have been discovered yet, rather
  than showing unrelated data

### Requirement: Discovery can be triggered from a URL
The system SHALL let a user start a discovery crawl by submitting a seed
URL, and SHALL report a summary of the run (pages visited, category nodes
found/updated) once it completes.

#### Scenario: Successful discovery run
- **WHEN** a user submits a reachable seed URL
- **THEN** the system SHALL run the discovery crawl and report how many
  pages were visited and how many category nodes were found or updated

#### Scenario: Seed URL cannot be reached
- **WHEN** a user submits a seed URL that fails to fetch (e.g. host
  unreachable)
- **THEN** the system SHALL report the failure rather than silently
  showing an empty result
