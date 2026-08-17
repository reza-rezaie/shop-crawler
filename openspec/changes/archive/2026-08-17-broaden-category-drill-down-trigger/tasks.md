## 1. Trigger change

- [x] 1.1 In `crawler.mojo`, move the `find_child_links` call so it runs
      for any non-not-found page, regardless of whether that page also
      yielded products; keep the not-found check, the per-page child cap,
      and the overall page budget unchanged.
- [x] 1.2 Adjust the "links to N narrower category page(s)" note wording
      if needed so it reads sensibly whether or not the page also had its
      own products.

## 2. Regression + tests

- [x] 2.1 Run the full `pixi run test` suite — `is_child_path`/
      `find_child_links` unit tests are unaffected (they test the link
      logic directly), confirm they still pass.
- [x] 2.2 Re-verify no regression on `books.toscrape.com` pagination and
      the previously-verified azurestandard.com leaf page.
- [x] 2.3 (found via 2.2) Fixed a latent `is_child_path` bug this task
      exposed: the site root's path-stem is `/` itself, a prefix of every
      path on the site, so crawling a homepage previously misread every
      link on it as a "child" page — silently harmless before this change
      (drill-down only ran on zero-product pages, and a homepage always
      has products), but a real regression once drill-down became
      unconditional (`books.toscrape.com` dropped from 60 to 40 products
      at `max_pages=3`, its budget consumed by spurious "children").
      Guarded `is_child_path` to never treat the root as having children;
      added regression tests; re-verified both the fix (60 products
      again) and that Food drill-down still works.

## 3. Live verification

- [x] 3.1 Crawl the corrected top-level URL,
      `https://www.azurestandard.com/shop/category/food/21244` (the
      reported `.../food/` URL's real form, with its ID), and confirm
      both its own products are stored AND its subcategory links are
      enqueued and followed within the page budget.
- [x] 3.2 Re-crawl `https://www.azurestandard.com/shop/category/outdoor-garden/19159?subcategories=true`
      (the zero-product hub verified in the previous change) and confirm
      identical drill-down behavior to before this refinement.
