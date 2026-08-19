## 1. Remove the image from product cards

- [x] 1.1 In `ProductCard` (`frontend/src/App.jsx`), remove the
  `.product-thumb` block (image + "No image" placeholder) entirely.
- [x] 1.2 Confirm `ProductCard` still renders source, name, category, and
  price with `product.image_url` untouched in the data it receives (no API
  or state changes needed).

## 2. Densify the grid

- [x] 2.1 In `frontend/src/App.css`, tighten `.product-grid`'s
  `grid-template-columns` minmax so more cards fit per row now that cards
  are no longer image-shaped (e.g. reduce the minimum column width).
- [x] 2.2 Remove now-unused `.product-thumb` / `.product-thumb img` /
  `.product-thumb .placeholder` rules.
- [x] 2.3 Adjust `.product-card` / `.product-body` spacing and type scale so
  cards read well at the new, shorter height (no dead space where the image
  used to be).

## 3. Verify

- [x] 3.1 Run the frontend locally and browse products with and without
  `image_url` set, confirming no image or placeholder renders either way
  and the grid is visibly denser than before.
- [x] 3.2 Run `openspec validate 001-declutter-product-grid --strict` and
  fix any reported issues.
