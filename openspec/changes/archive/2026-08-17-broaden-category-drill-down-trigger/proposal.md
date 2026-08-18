## Why

Trying the previous change's own example against a broader real starting
point (`https://www.azurestandard.com/shop/category/food/21244`, the
correct top-level "Food" URL — the literal URL from the original bug
report, `.../shop/category/food/`, is missing its ID and genuinely 404s)
showed the drill-down trigger from that change is too narrow: it only
looks for narrower category links on a page that has **zero** products of
its own. Real category pages on this site (confirmed on both this
top-level page and the earlier-verified `food/flour/22474`) commonly show
a handful of products directly *and* link to dozens of narrower
subcategories on the same page — a department landing page, not a pure
zero-product hub. With the previous trigger, a crawl aimed at such a page
only ever sees the handful of products shown at that level and never
reaches the (potentially thousands of) products in its subcategories,
which is short of "crawl and fetch all the products, even at higher
level."

## What Changes

- Look for narrower category links on **every** crawled page, not only
  ones with zero products of their own. A page that has both products and
  subcategory links now gets both: its own products stored, and its
  subcategory links enqueued (still bounded by the same per-page cap and
  overall page budget as before — no change to those bounds).
- Not-found detection is unaffected (still only checked, and still only
  suppresses further crawling of that one page, when a page has zero
  products).

## Capabilities

### Modified Capabilities
- `product-extraction`: the "child link" scenario introduced by the
  previous change changes from "only pages with zero products get looked
  at for child links" to "every page does," reflecting that a real
  category page can legitimately have both.

## Impact

- `backend/mojo_src/crawler.mojo`: trigger condition only; no changes to
  `html_extract.find_child_links`, `textutil.is_child_path`, or any other
  function signature.
- Tests: existing `find_child_links`/`is_child_path` unit tests are
  unaffected (they test the link-matching logic directly, not the
  trigger). Re-verify the crawl-loop behavior live, same targets as the
  previous change plus the corrected top-level URL.
