## Context

See `proposal.md` - Why for motivation. Relevant current state:

- `openspec/changes/archive/` already has 9 dated folders (each a full
  proposal/design/tasks record) going back to 2026-08-17 - real history
  exists, it's just not rolled up anywhere skimmable.
- `pixi.toml` is at `version = "0.1.0"` and nothing in the repo cuts
  dated/tagged releases on a cadence (aside from the one `v0.1.0` tag
  mentioned in `HANDOFF.md`) - there's no version-per-entry structure to
  hang a [Keep a Changelog](https://keepachangelog.com/)-style
  `## [x.y.z] - date` header off of.
- CI (`.github/workflows/ci.yml`, from `crw-0001-add-ci`) currently runs
  Mojo tests, frontend lint, and frontend build - nothing that inspects
  which files a PR touched.

## Goals / Non-Goals

**Goals:**
- One `CHANGELOG.md`, reverse-chronological, that a reader can open and
  understand "what shipped recently" without digging through
  `openspec/changes/archive/` or git log.
- Entries ship in the same PR as the change they describe (per your
  answer) - no separate "update changelog" follow-up step to forget.
- Backfilled from existing history so the file is useful on day one.

**Non-Goals:**
- No semver version headers/releases - see Context above, there's no
  release cadence to hang them on. Entries are dated, not versioned.
- No mechanical CI enforcement (see Decision 3 below) - this is a
  contribution convention, not a merge gate.
- No changelog *generation* tooling (e.g. auto-drafting entries from
  commit messages/conventional commits) - out of scope, entries are
  written by hand same as `openspec/changes/*` artifacts already are.

## Decisions

**1. Format: flat, dated, reverse-chronological entries - not
Keep-a-Changelog version sections.**
Each entry is `## YYYY-MM-DD - <title>` followed by a short description
and a reference (PR link and/or archived-change folder). No `[Unreleased]`
section, no semver headers - matching the Non-Goal above. Alternative
considered: full Keep a Changelog format with version headers - rejected
for now since it would require inventing a release cadence this project
doesn't have; can be adopted later without losing existing entries if the
project ever does start cutting versioned releases.

**2. Backfill source: `openspec/changes/archive/`, one entry per folder,
in date-prefix order.**
Each archived folder's `proposal.md` "Why"/"What Changes" already has the
material for a one-paragraph entry. This also fixes the two folders whose
names don't carry a clean title (`2026-08-18-001-declutter-product-grid`,
and the two `chg-0001`/`crw-0001` folders with redundant prefixes) into a
plain-English title.

**3. Not CI-enforced - a documented convention only.**
A CI check that fails a PR for not touching `CHANGELOG.md` would need to
distinguish "this PR should have a changelog entry" from "this PR is
internal/no-behavior-change" (see the spec's second scenario) - that
classification isn't mechanically checkable from a diff alone without
false positives (e.g. a README typo fix, a CI tooling tweak) or false
negatives (e.g. a behavior change hidden in a file that looks internal).
Getting that heuristic wrong either blocks legitimate PRs or gives false
confidence. Given this is a solo-maintainer POC repo, the lower-friction
choice is a documented convention (in README.md) plus this spec's
requirement, not a hard gate. Revisit if the contributor base grows enough
that convention alone stops being reliable.

## Risks / Trade-offs

- **[Risk] Without CI enforcement, a PR can merge without its changelog
  entry, same as any documented-but-unenforced convention.**
  → Mitigation: none mechanical, by Decision 3. The spec requirement makes
  the expectation explicit and reviewable; a future change can add a
  lightweight CI check (e.g. warn-only, or scoped to specific paths) if
  drift becomes a real problem.
- **[Trade-off] Flat dated entries (Decision 1) don't map to installable
  versions.**
  Fine for this project today (no published/versioned releases); would
  need revisiting if `pixi.toml`'s version starts being bumped and
  tagged per release.

## Migration Plan

Purely additive: create `CHANGELOG.md` with backfilled entries, add the
convention note to `README.md`. No rollback concerns - deleting the file
or reverting the README note would fully undo this change.
