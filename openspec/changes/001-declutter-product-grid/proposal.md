## Why

Product cards in the dashboard's browse view lead with an image thumbnail,
but crawled `image_url`s are often missing or broken, so a large share of
cards show a blank/placeholder box instead of useful information. That
wastes the card's most prominent space and pushes name, category, and price
down and to the side. Dropping the thumbnail and tightening the card lets
more products fit on screen and puts the data the user actually filters and
scans by front and center.

## What Changes

- Remove the image thumbnail from product cards in the browse view
  (`ProductCard` in `frontend/src/App.jsx`); the card's link, source,
  name, category, and price stay.
- Restyle `.product-card` / `.product-grid` as a denser grid now that the
  image no longer sets the card's shape: shorter cards, a tighter
  `grid-template-columns` minmax so more cards fit per row, and adjusted
  spacing/type scale inside the card body.
- **BREAKING**: `image_url` is no longer rendered anywhere in the browse
  view. It stays in the API response and the catalog (still exported and
  filterable by other means) since it's crawled data used elsewhere, not a
  browse-view concern.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `product-browsing`: product cards in the browse view no longer display an
  image, and the browse view's layout is denser as a result.

## Impact

- `frontend/src/App.jsx`: `ProductCard` component.
- `frontend/src/App.css`: `.product-grid`, `.product-card`, `.product-thumb`,
  `.product-body` and related rules.
- No backend/API changes — `image_url` continues to be crawled, stored, and
  returned by `/api/products`; only its use in the frontend changes.
