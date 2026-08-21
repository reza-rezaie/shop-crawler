## Why

There is no automated check today: a broken Mojo test, a failed frontend
build, or a bad merge can land on `main` unnoticed until someone runs
`pixi run test` by hand. The project already has the checks (`pixi run
test`, `pixi run frontend-build`) — they just never run automatically, and
nothing gates a pull request on them passing.

## What Changes

- Add a GitHub Actions workflow that runs on every push and pull request
  against `main`: installs Pixi, runs the native-Mojo test suite (`pixi run
  test`), lints the frontend (`npm run lint`, already configured via
  `oxlint` but never run automatically today), and builds the frontend
  (`pixi run frontend-build`).
- Add a single local command (a `pixi` task, e.g. `pixi run ci`) that runs
  the exact same checks the workflow runs, so a developer can validate
  before pushing instead of discovering a failure only after CI runs.
- Document in `README.md` how to run the CI checks locally and that PRs are
  gated on GitHub Actions passing.
- No deployment step is included — this is CI (checks), not CD. The
  project has no hosting/deployment target today; adding one is out of
  scope for this change.

## Capabilities

### New Capabilities
- `ci`: automated checks (native-Mojo tests, frontend build) that run on
  every push/PR via GitHub Actions, and can be run identically on a
  developer's machine with one local command.

### Modified Capabilities
(none — no existing capability's requirements change)

## Impact

- **Affected code/config**: new `.github/workflows/ci.yml`; a new task in
  `pixi.toml` (e.g. `ci`) composed from the existing `test` and
  `frontend-build` tasks; a short addition to `README.md`.
- **Affected systems**: GitHub Actions (hosted runner) for the remote half;
  local developer machines (via `pixi`) for the local half. No production
  or deployment infrastructure is touched.
- **Open risk to resolve in design**: the project's Mojo toolchain is
  installed from Modular's `conda.modular.com/max` channel. Whether that
  channel is reachable/anonymous-usable from a GitHub-hosted runner (or
  needs a token/secret) needs to be confirmed when the workflow is
  designed — see `design.md`.
