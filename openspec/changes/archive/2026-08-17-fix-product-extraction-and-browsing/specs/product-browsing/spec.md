## Purpose

Let a user browse, search, and filter every product currently stored in the
local catalog, with enough attribution per product to tell which site or
listing page it was actually crawled from.

## ADDED Requirements

### Requirement: Browse all stored products
The system SHALL provide a way to list every product currently stored in
the catalog, independent of which crawl(s) produced them, with pagination
over the full result set.

#### Scenario: Empty catalog
- **WHEN** no products have been crawled yet
- **THEN** the browse view SHALL indicate the catalog is empty rather than
  showing unrelated content

#### Scenario: Catalog spans multiple crawled sites
- **WHEN** products from more than one crawled site exist in the catalog
- **THEN** the browse view SHALL be able to list products from all of them

### Requirement: Search and filter
The system SHALL let the user filter the browsed product list by a
case-insensitive substring match on product name, by exact category, and
by minimum and/or maximum price, and these filters SHALL be combinable.

#### Scenario: Name search narrows results
- **WHEN** the user searches for a substring that matches some but not all
  stored product names
- **THEN** only products whose name contains that substring (case
  insensitive) SHALL be returned

#### Scenario: Combined filters narrow further
- **WHEN** the user applies a category filter and a price range together
- **THEN** only products matching both constraints SHALL be returned

### Requirement: Products are attributed to their source site
Each product returned by the browse view SHALL include which site (host)
and which listing page it was crawled from, and the browse view SHALL let
the user filter results down to a single source site.

#### Scenario: Product card shows its source site
- **WHEN** the browse view renders a product from `example-shop.com`
- **THEN** that product's card SHALL display `example-shop.com` (or
  equivalent source identification) alongside its name and price

#### Scenario: Filtering by source site
- **WHEN** the catalog contains products from two different sites and the
  user filters to one of them
- **THEN** only products crawled from that site SHALL be returned

### Requirement: Click-through to the original product page
Each product in the browse view SHALL link to the real product page it was
crawled from, opening it directly.

#### Scenario: Clicking a product card
- **WHEN** the user clicks a product card in the browse view
- **THEN** the original product page SHALL open in a new tab/window
