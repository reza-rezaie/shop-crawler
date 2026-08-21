## Context

See `proposal.md` - Why/What Changes for motivation and scope. Relevant
current state:

- All checks already exist as `pixi` tasks: `test` (native-Mojo suite,
  requires a local Postgres instance started via `scripts/pg_local.sh
  ensure`) and `frontend-build` (Vite build, `cwd: frontend`). The frontend
  also has an existing, unused `npm run lint` script (`oxlint`).
- Environment provisioning is entirely `pixi`-driven: Mojo, Postgres, and
  `psycopg2` all come from `pixi.toml`'s `[dependencies]`, resolved against
  `pixi.lock`. There is no Dockerfile and no system-level install step
  today.
- The Mojo/Postgres channels are `conda.modular.com/max` and
  `conda-forge`/`repo.prefix.dev/modular-community` - none of these are
  GitHub's own registries, so the workflow needs network egress to them
  from the runner.

## Goals / Non-Goals

**Goals:**
- One GitHub Actions workflow, triggered on push-to-`main` and PRs against
  `main`, that reuses the project's existing `pixi` tasks rather than
  reimplementing install/build steps in YAML.
- One local `pixi` task that runs the identical checks, so a green local
  run predicts a green remote run.
- Branch protection on `main` requiring the workflow to pass before merge.

**Non-Goals:**
- Any deployment/CD step (see proposal - no hosting target exists).
- Code coverage reporting, caching tuning, or matrix builds across
  OS/Mojo versions - single Linux runner, matching the project's own
  `platforms = ["linux-64"]` constraint in `pixi.toml`.
- Running `act` (GitHub Actions locally) - the local half is "run the same
  commands," not "run the workflow file itself" (see proposal's local-CI
  clarification).

## Decisions

**1. Use `prefix-dev/setup-pixi` (GitHub Action) to provision the
toolchain, not a hand-rolled conda/apt install.**
Pixi already pins every dependency (Mojo, Postgres, `psycopg2`,
`playwright-python`) in `pixi.lock`. Reimplementing that in raw YAML would
duplicate versions that can drift from what a developer's machine actually
has. `setup-pixi` installs pixi itself and, with `pixi install`, resolves
straight from the committed lockfile - so CI and local dev use exactly the
same versions. Alternative considered: install Mojo via `conda`/`micromamba`
directly in the workflow - rejected, it re-specifies channels/versions
already declared once in `pixi.toml`.

**2. New `pixi` task `ci` composes the existing tasks rather than the
workflow inlining shell steps.**
`pixi.toml` gets one new task, e.g.:
```
ci = "pixi run test && cd frontend && npm ci && npm run lint && npm run build"
```
The workflow's "run checks" step is then just `pixi run ci` (plus the
one-time `npm`/Node setup below) - so the workflow file and a developer's
terminal invoke the identical command, satisfying the "local parity"
requirement directly instead of by convention.
Note: `npm ci` (not `npm install`, which the existing `frontend-install`
task uses) is used here specifically for reproducible, lockfile-exact
installs appropriate for a CI/verification context - `frontend-install`
remains unchanged for interactive dev setup.

**3. Frontend toolchain (Node/npm) is provisioned by `actions/setup-node`
in the workflow, and is assumed already present locally.**
`pixi.toml` does not manage Node (see `README.md` prerequisites: Node/npm
listed as a prerequisite the developer installs themselves). Mirroring that
split, the workflow adds a standard `actions/setup-node` step alongside
`setup-pixi`, rather than trying to pull Node into the pixi environment.

**4. Postgres for CI reuses `scripts/pg_local.sh` (the same pixi-managed
local instance dev machines use), not a GitHub Actions service container.**
The `test` pixi task already runs `scripts/pg_local.sh ensure` before
tests. Keeping that as-is (rather than swapping in a `services: postgres:`
container) means the workflow's Postgres setup is identical to a
developer's - one less thing to keep in sync, and Postgres itself already
comes from `pixi.toml`'s dependencies so no extra runner setup is needed.

**5. Branch protection is configured via the GitHub repo settings (or a
one-time `gh api`/Settings-UI step during implementation), not committed
YAML.**
GitHub does not support declaring required-status-check branch protection
inside a workflow file - it's a repository setting. This is called out as
an explicit implementation task (see `tasks.md`) rather than modeled as a
spec-testable file change.

## Risks / Trade-offs

- **[Risk] `conda.modular.com/max` may require authentication or rate-limit
  anonymous/CI traffic differently than an interactive developer session.**
  → Mitigation: this is verified empirically as the first implementation
  task - push a minimal workflow and confirm `pixi install` succeeds on a
  hosted runner. If it fails on auth, the fallback is a Modular-provided
  CI token stored as a GitHub Actions secret (`MODULAR_AUTH_TOKEN` or
  equivalent) - this doesn't change the workflow's shape, only adds one
  `env:` entry, so it's safe to resolve during implementation rather than
  blocking design on it now.
- **[Risk] `pixi install` + Mojo compile + Postgres init on a fresh runner
  every run is slower than a warm local environment.**
  → Mitigation: rely on `setup-pixi`'s built-in cache-by-lockfile-hash
  support (`cache: true`) to avoid re-resolving the environment when
  `pixi.lock` hasn't changed. No further optimization (e.g. custom
  container images) is in scope for this change.
- **[Trade-off] Reusing `scripts/pg_local.sh` instead of a Postgres service
  container ties CI's Postgres lifecycle to the same script devs use.**
  If that script ever assumes a persistent/interactive machine (e.g. state
  left over between runs), CI could behave differently on a fresh runner
  each time. Mitigation is implicit: a fresh GitHub runner is a stronger
  version of "clean state" than most dev machines, so this is more likely
  to surface a real bug in the script than to cause a CI-only failure.

## Migration Plan

No data/schema migration. Rollout is additive: add the workflow file and
the `ci` pixi task, confirm the workflow goes green on a throwaway PR, then
turn on the "require status checks to pass" branch protection rule as the
last step (so `main` is never blocked on a workflow that hasn't been
proven to pass yet). Rollback is deleting the workflow file and/or turning
the branch protection rule back off - no other system depends on it.
