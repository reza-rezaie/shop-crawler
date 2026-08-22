## Why

There's no single, skimmable history of what shipped and when. The closest
things today are `openspec/changes/archive/` (detailed but spread across
many per-change folders, not a rollup) and `HANDOFF.md` (a rolling
snapshot that gets overwritten each time, not an append-only history).
Anyone wanting "what changed recently" has to dig through archived changes
or git log.

## What Changes

- Add `CHANGELOG.md` at the repo root: a reverse-chronological, one-entry
  per merged change/PR log (no semver version headers — this project
  doesn't cut dated releases, so entries are just dated and titled).
- Establish the convention that a PR introducing a user-visible or
  behavior-level change adds its own `CHANGELOG.md` entry in that same PR
  (so it merges atomically with the change, never as a forgotten
  follow-up) — mirroring how `pixi run ci` already keeps local and remote
  checks in the same command instead of two steps that can drift apart.
- Seed `CHANGELOG.md` with entries backfilled from the existing
  `openspec/changes/archive/` history, so it starts complete rather than
  empty.
- Document the convention in `README.md` (or `CLAUDE.md`/contributor docs)
  so it's discoverable, not just tribal knowledge.

## Capabilities

### New Capabilities
- `changelog`: a maintained `CHANGELOG.md` at the repo root, with the
  expectation that a PR changing observable behavior updates it in the
  same PR.

### Modified Capabilities
(none — no existing capability's requirements change)

## Impact

- **Affected files**: new `CHANGELOG.md`; a short addition to `README.md`
  documenting the convention.
- **Affected process**: future PRs that change observable behavior are
  expected to include a changelog entry — this is a contribution
  convention, not something mechanically enforced (no CI check is being
  added to require it; see design.md for why).
- **No code/runtime impact**: nothing in `backend/`, `frontend/`, or
  `pixi.toml` changes.
