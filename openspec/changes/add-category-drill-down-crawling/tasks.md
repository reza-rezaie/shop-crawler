## 1. URL path helpers (native Mojo, no Python interop)

- [ ] 1.1 In `textutil.mojo`, add `url_path(url) -> String` (path only,
      query/fragment stripped) and `url_path_stem(url) -> String` (path
      with its last `/`-segment removed).
- [ ] 1.2 In `textutil.mojo`, add `is_child_path(candidate_url, current_url) -> Bool`:
      same host as `current_url`, and `url_path(candidate_url)` starts
      with `url_path_stem(current_url) + "/"`.
- [ ] 1.3 In `textutil.mojo`, add `find_all_anchor_hrefs(html) -> List[String]`:
      every `<a href="...">` value found on the page (no class/hint
      filter, unlike existing block extraction).
- [ ] 1.4 Unit tests for 1.1-1.3 (table-driven: real parent/child/sibling/
      unrelated path examples from the live investigation).

## 2. Not-found page detection

- [ ] 2.1 In `html_extract.mojo`, add `looks_like_not_found_page(html) -> Bool`:
      a short heading-like element whose text matches "not found" / "404"
      / "page not found" (case-insensitive), with little surrounding
      content.
- [ ] 2.2 Wire it into `crawler.mojo`'s per-page note logic: checked
      after zero products are found (raw, then rendered if attempted),
      before the existing SPA-shell note, with distinct note wording.
- [ ] 2.3 Fixture + test: a trimmed real "Not found (404)" page (from the
      live investigation) is detected; the existing SPA-shell fixture
      (which legitimately has zero products but isn't a 404) is not.

## 3. Child-link discovery

- [ ] 3.1 In `html_extract.mojo`, add `find_child_links(html, current_url, limit) -> List[String]`:
      resolve every anchor href to absolute, keep the ones
      `is_child_path` accepts, dedup, cap at `limit`.
- [ ] 3.2 Fixture + test using real child-category link samples from the
      live investigation (parent/child/sibling/unrelated cases from the
      design doc's Context section).

## 4. Crawl loop: pagination + drill-down as one work queue

- [ ] 4.1 In `crawler.mojo`, replace the `current_url`/`next_url_opt`
      linear walk with a `List[String]` queue seeded with `seed_url`,
      reusing `visited_pages` for dedup and the existing `capped_pages`
      budget as the loop bound.
- [ ] 4.2 After extraction (raw or rendered) on a popped URL: if it
      yielded products, enqueue its next-page link (existing behavior,
      now via the queue). If it yielded zero products (and isn't a
      not-found page), enqueue up to N child links found on it.
- [ ] 4.3 Update crawl-notes wording: not-found note, and (kept from the
      previous change) the SPA-shell "still nothing after rendering"
      note only when the page is *not* a not-found page and yields no
      child links either.

## 5. Tests and regression checks

- [ ] 5.1 Run the full `pixi run test` suite; all prior tests (extraction,
      SPA-shell, source attribution, JS-rendering) must still pass
      unchanged against the new queue-based crawl loop.
- [ ] 5.2 Add a crawler-level test (temp SQLite DB + fixture HTML served
      how the existing crawler tests do, or a scripted check of the new
      queue logic in isolation) proving: a hub page with zero products
      and 3 child links enqueues those children; a leaf page with
      products does not look for child links; the overall page budget is
      respected across combined pagination+drill-down pages.

## 6. Live verification

- [ ] 6.1 Crawl `https://www.azurestandard.com/shop/category/food/`
      (the reported URL) and confirm the crawl result now reports it as
      a not-found page, not a generic "still nothing" note.
- [ ] 6.2 Crawl a real category hub page discovered during investigation
      (e.g. `https://www.azurestandard.com/shop/category/food/flour/22474`)
      with a page budget large enough to drill down, and confirm real
      products from its child categories end up in the catalog.
- [ ] 6.3 Re-crawl `https://www.azurestandard.com/shop/category/food/baking-pantry/26644`
      (leaf page, previously verified) and confirm identical behavior to
      before this change (no drill-down attempted, same products).
- [ ] 6.4 Re-crawl `https://books.toscrape.com/...` and confirm pagination
      still works exactly as before (regression check on the rewritten
      loop).
