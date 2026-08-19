## ADDED Requirements

### Requirement: Product cards omit images
The browse view SHALL render each product card without an image, even when
the product has a stored `image_url`; the card SHALL still show the
product's source site, name, category (if any), and price. The browse
view's grid SHALL lay out cards more densely than an image-led card would
allow (more cards visible per row at a given viewport width).

#### Scenario: Card renders without an image regardless of image_url
- **WHEN** the browse view renders a product that has a non-empty
  `image_url`
- **THEN** the card SHALL NOT render an image element or an image
  placeholder for that product

#### Scenario: Card still shows its other attributes
- **WHEN** the browse view renders any product card
- **THEN** the card SHALL display the product's source site, name,
  category (if present), and price
