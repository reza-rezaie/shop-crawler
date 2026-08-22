## 1. Create the changelog file

- [x] 1.1 Create `CHANGELOG.md` at the repo root with a brief header
      explaining the format (dated, reverse-chronological, no semver
      versions — see design.md Decision 1) and the same-PR convention.

## 2. Backfill from existing history

- [x] 2.1 Add one entry per folder in `openspec/changes/archive/`, in
      reverse date-prefix order (newest first), each with a plain-English
      title, a short description drawn from that folder's proposal.md,
      and a reference back to the archive folder:
      - `2026-08-21-crw-0001-add-ci` — add CI (GitHub Actions + local
        `pixi run ci`)
      - `2026-08-21-chg-0001-2026-08-21-modular-monolith-vertical-slice` —
        reorganize backend into a modular monolith by feature
      - `2026-08-19-switch-to-postgres` — switch catalog storage from
        SQLite to Postgres
      - `2026-08-18-add-category-discovery-crawl` — add category
        discovery crawl
      - `2026-08-18-001-declutter-product-grid` — remove product-card
        image thumbnails, densify the grid
      - `2026-08-17-fix-product-extraction-and-browsing` — fix product
        extraction/browsing mismatch bug
      - `2026-08-17-broaden-category-drill-down-trigger` — broaden
        category drill-down trigger
      - `2026-08-17-add-js-rendered-crawling` — add JS-rendered
        (headless-Chromium) crawl fallback
      - `2026-08-17-add-category-drill-down-crawling` — add category
        drill-down crawling
- [x] 2.2 Add one entry for *this* change itself
      (`crw-0002-2026-08-21-add-changelog`) once it's implemented, so the
      file documents its own addition.

## 3. Document the convention

- [x] 3.1 Add a short note to `README.md` pointing at `CHANGELOG.md` and
      stating the convention: a PR that changes observable behavior adds
      its own entry in that same PR (per design.md Decision 3 — this is a
      documented convention, not a CI-enforced check).

## 4. Verification

- [x] 4.1 Read through the finished `CHANGELOG.md` top to bottom and
      confirm every archived change has a corresponding entry, in the
      right order, satisfying `specs/changelog/spec.md`.
      → All 9 archived changes present, ordered by actual PR merge
      timestamp (not folder date-prefix — caught and fixed a mismatch
      for the two 2026-08-17-prefixed drill-down folders whose PR #3
      actually merged 2026-08-18).
