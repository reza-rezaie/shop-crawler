# Changelog

Notable changes to this project, most recent first. Entries are dated
(not versioned — this project doesn't cut dated/semver releases; see
`openspec/changes/archive/2026-08-21-crw-0002-2026-08-21-add-changelog/design.md`
Decision 1 once archived, or the active change while in progress).

**Convention:** a pull request that changes user-visible or observable
behavior adds its own entry here, in that same PR — not as a follow-up
afterward. Purely internal changes (refactors, tooling, docs) don't need
one. See `README.md` for the short version of this note.

## 2026-08-22 — Add CHANGELOG.md

Added this file, backfilled from the existing `openspec/changes/archive/`
history, plus the convention (above) that a PR ships its own entry.
Reference: `openspec/changes/crw-0002-2026-08-21-add-changelog/`.

## 2026-08-21 — Add CI

Added a GitHub Actions workflow (`.github/workflows/ci.yml`) that runs the
native-Mojo test suite, frontend lint, and frontend build on every push/PR
to `main`, plus a local `pixi run ci` task that runs the identical checks.
`main` now requires the check to pass before merging.
Reference: PR [#8](https://github.com/reza-rezaie/shop-crawler/pull/8),
`openspec/changes/archive/2026-08-21-crw-0001-add-ci/`.

## 2026-08-21 — Reorganize backend into a modular monolith

Restructured `backend/` from organization-by-technical-layer (one
`db.mojo`, one `api.mojo` for every table/endpoint) into
organization-by-feature: `backend/src/core/` (shared kernel) plus
`backend/src/modules/{product_extraction,category_discovery,
product_browsing}/`, each with its own tests. No behavior change.
Reference: PR [#7](https://github.com/reza-rezaie/shop-crawler/pull/7),
`openspec/changes/archive/2026-08-21-chg-0001-2026-08-21-modular-monolith-vertical-slice/`.

## 2026-08-19 — Declutter product grid

Removed the product-card image thumbnail from the browse view (crawled
`image_url`s were often missing/broken, wasting the card's most prominent
space) and densified the grid layout to fit more cards per row.
**BREAKING** for anything relying on the thumbnail rendering there —
`image_url` itself is unchanged in the API/catalog.
Reference: PR [#6](https://github.com/reza-rezaie/shop-crawler/pull/6),
`openspec/changes/archive/2026-08-18-001-declutter-product-grid/`.

## 2026-08-19 — Switch catalog storage from SQLite to Postgres

Replaced the single-writer SQLite store (`data/products.db`) with a
pixi-managed local Postgres instance, giving the catalog atomic,
race-free upserts instead of SELECT-then-INSERT/UPDATE. Added
`pixi run db-migrate` to carry over existing SQLite data.
Reference: PR [#5](https://github.com/reza-rezaie/shop-crawler/pull/5),
`openspec/changes/archive/2026-08-19-switch-to-postgres/`.

## 2026-08-18 — Add category-discovery crawl

Added a way to see a site's category structure before running a product
crawl, plus live crawl progress reporting and a higher max-pages limit.
Reference: PR [#4](https://github.com/reza-rezaie/shop-crawler/pull/4),
`openspec/changes/archive/2026-08-18-add-category-discovery-crawl/`.

## 2026-08-18 — Broaden category drill-down trigger

Broadened category drill-down to trigger correctly from a real top-level
category URL (not just the narrower case the initial version handled),
and made the crawl result distinguish "not a real page on this site" from
a generic "found nothing."
Reference: PR [#3](https://github.com/reza-rezaie/shop-crawler/pull/3),
`openspec/changes/archive/2026-08-17-broaden-category-drill-down-trigger/`.

## 2026-08-18 — Add category drill-down crawling

Added crawling that follows a bounded number of narrower category-page
links from each crawled page (a category tree, common on larger stores),
drilling deeper level by level within the existing page budget.
Reference: PR [#3](https://github.com/reza-rezaie/shop-crawler/pull/3),
`openspec/changes/archive/2026-08-17-add-category-drill-down-crawling/`.

## 2026-08-17 — Add JS-rendered crawling fallback

Added a headless-Chromium (Playwright) rendering fallback for pages whose
product listing only exists client-side (React/Angular/Vue/Next.js SPA
shells), triggered automatically only when a first pass finds zero
products. Verified end-to-end against a real AngularJS SPA.
Reference: PR [#2](https://github.com/reza-rezaie/shop-crawler/pull/2),
`openspec/changes/archive/2026-08-17-add-js-rendered-crawling/`.

## 2026-08-17 — Fix product extraction/browsing, add browse-all view

Fixed a bug where crawled products could be attributed to the wrong
source page, root-caused to two compounding extraction issues, and added
a browse-all view over the full catalog.
Reference: PR [#1](https://github.com/reza-rezaie/shop-crawler/pull/1),
`openspec/changes/archive/2026-08-17-fix-product-extraction-and-browsing/`.
