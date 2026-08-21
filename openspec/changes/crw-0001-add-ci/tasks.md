## 1. Local `ci` task

- [x] 1.1 Add a `ci` task to `pixi.toml` that runs, in order: `pixi run
      test` (native-Mojo suite + local Postgres), then `cd frontend && npm
      ci && npm run lint && npm run build`, failing (non-zero exit) if any
      step fails.
- [x] 1.2 Run `pixi run ci` locally end-to-end and confirm it passes on a
      clean checkout.

## 2. GitHub Actions workflow

- [x] 2.1 Create `.github/workflows/ci.yml` triggered on `push` to `main`
      and `pull_request` targeting `main`.
- [x] 2.2 Add steps: checkout, `prefix-dev/setup-pixi` (with lockfile
      caching enabled), `actions/setup-node` (version matching
      `frontend/package.json` engine expectations, or latest LTS if
      unspecified), then run `pixi run ci`.
- [ ] 2.3 Push the workflow on a throwaway branch/PR and confirm
      `pixi install` succeeds on the hosted runner (validates the
      `conda.modular.com/max` reachability risk from design.md). If it
      fails on authentication, add the required token/secret and re-run
      before continuing.
- [ ] 2.4 Confirm the workflow goes green end-to-end (tests, lint, build)
      on that throwaway PR.

## 3. Branch protection

- [ ] 3.1 Once the workflow has passed at least once, enable a branch
      protection rule on `main` requiring the CI workflow's status check
      to pass before merging.

## 4. Documentation

- [x] 4.1 Add a short section to `README.md` documenting `pixi run ci` as
      the local pre-push check command, and noting that PRs are gated on
      the GitHub Actions workflow passing.

## 5. Verification

- [ ] 5.1 Open a real pull request for this change itself and confirm the
      new workflow runs and reports status on it, satisfying the specs in
      `specs/ci/spec.md`.
