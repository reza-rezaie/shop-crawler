## Purpose

Give the project a single, skimmable, append-only history of what shipped
and when, instead of requiring readers to dig through per-change archive
folders or git log.

## ADDED Requirements

### Requirement: A changelog file exists and is append-only
The repository SHALL maintain a `CHANGELOG.md` at its root listing merged
changes in reverse-chronological order (most recent first), and existing
entries SHALL NOT be rewritten or removed by a later change.

#### Scenario: Reading recent history
- **WHEN** someone opens `CHANGELOG.md`
- **THEN** the most recently merged change SHALL appear at (or near) the
  top, and each entry SHALL be dated

#### Scenario: A new entry is added
- **WHEN** a new change is merged and its entry is added to
  `CHANGELOG.md`
- **THEN** every previously existing entry SHALL remain present and
  unchanged

### Requirement: A merged PR's changelog entry ships in that same PR
A pull request that changes user-visible or observable system behavior
SHALL include its `CHANGELOG.md` entry as part of that same pull request,
so the entry merges atomically with the change it describes.

#### Scenario: PR adds a new capability or changes behavior
- **WHEN** a pull request adds a new capability or changes existing
  observable behavior
- **THEN** that pull request's diff SHALL include a corresponding
  `CHANGELOG.md` entry

#### Scenario: PR is purely internal with no observable behavior change
- **WHEN** a pull request is a pure refactor, dependency bump, or
  internal tooling change with no user-visible or observable behavior
  change
- **THEN** a `CHANGELOG.md` entry is not required for that pull request

### Requirement: Each entry identifies what changed and where to look for more
Each `CHANGELOG.md` entry SHALL include a date, a short human-readable
description of what changed, and — when the change has one — a reference
to its source (PR number and/or its `openspec/changes/archive/` folder).

#### Scenario: Entry for a change with an archived openspec change
- **WHEN** a changelog entry is added for a change that has a
  corresponding `openspec/changes/archive/<...>/` folder
- **THEN** the entry SHALL reference that folder (or the PR number) so a
  reader can find the full proposal/design/tasks detail
