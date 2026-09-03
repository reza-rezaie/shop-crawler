## Why

The browsable UI is a Vite + React 19 single-page app whose toolchain
(npm, Node.js) is a separate, hand-installed prerequisite that pixi does
not manage — the one part of the stack a developer has to provision
themselves (see `README.md` "Prerequisites" and CI's extra
`actions/setup-node` step). Moving the frontend to **Next.js** run under
**Bun** replaces that toolchain with a single fast runtime that pixi can
provision like everything else, removes the Node/npm prerequisite, and
puts the UI on a framework with a route/layout structure to grow into
instead of one hand-wired `App.jsx`. This intentionally reverses the
POC's earlier "React via Vite, not Next.js" decision recorded in
`SPEC.md` §"React via Vite, not Next.js".

## What Changes

- **BREAKING (developer setup)**: The frontend build toolchain changes
  from **npm/Node.js** to **Bun**. `npm`, `package-lock.json`, and the
  Node.js prerequisite are removed; `bun` and `bun.lock` replace them.
  Anyone building the frontend now needs Bun (provisioned by pixi — see
  below), not Node.
- The `frontend/` app is re-platformed from **Vite + React SPA** to
  **Next.js (App Router)**, React 19, configured for **static export**
  (`output: 'export'`). The build emits static HTML/CSS/JS that
  `backend/server.py` serves exactly as it serves `frontend/dist/`
  today — no long-running Next.js server, no second process, no SSR/RSC
  server runtime, no CORS.
- `backend/server.py`'s `STATIC_DIR` moves from `frontend/dist` to
  Next's export output (`frontend/out`); its SPA/index fallback is
  unchanged.
- The existing single-page UI (`src/App.jsx`, `src/main.jsx`,
  `index.html`) becomes Next's `app/layout.jsx` + `app/page.jsx` as a
  client component. **UI behaviour — every screen, control, API call,
  and polling loop — is unchanged.** No new user-facing features.
- Dev-time `/api` proxying moves from `vite.config.js`'s `server.proxy`
  to `next.config.js` `rewrites()`, still targeting the Mojo/Python
  backend.
- `bun` is added to `pixi.toml` `[dependencies]` (conda-forge), so
  `pixi run` provisions it. The pixi tasks `frontend-install`,
  `frontend-build`, `frontend-dev`, and `ci` switch from `npm …` to
  `bun …`. `scripts/dev_server.sh` switches its build check/commands to
  Bun and `frontend/out`.
- `.github/workflows/ci.yml` drops `actions/setup-node`; the frontend
  lint/build run under Bun from the pixi environment.
- `oxlint` is kept as the linter (run via Bun); no switch to
  `eslint`/`next lint`.
- `README.md` and `SPEC.md` are updated: Bun replaces Node/npm in
  prerequisites and run steps; the "React via Vite, not Next.js"
  rationale is revised to record this change.

## Capabilities

### New Capabilities
- `web-frontend`: How the browsable web UI is built and delivered — the
  framework it is built with, the toolchain/runtime that builds it, and
  the contract that its build output is static assets served by the
  existing backend process (no separate web server). Also asserts that
  this migration preserves all existing UI behaviour.

### Modified Capabilities
<!-- None. The `ci` capability's requirements (run the Mojo tests, the
     frontend lint, and the frontend build; one local command with
     local/remote parity) are unchanged in wording and intent — only the
     tool that runs the frontend half changes (Bun vs npm), which is an
     implementation detail, not a spec-level behaviour change. -->
(none)

## Impact

- **Affected code/config**:
  - `frontend/` — replaced: `package.json` (Next deps, Bun scripts),
    `next.config.js` (new, `output: 'export'` + `rewrites`),
    `app/layout.jsx` + `app/page.jsx` (new), removed `index.html`,
    `src/main.jsx`, `vite.config.js`; `package-lock.json` → `bun.lock`;
    `.gitignore` (`dist` → `out`, `.next`); `.oxlintrc.json` path/globs
    if needed.
  - `backend/server.py` — `STATIC_DIR` and the "build not found"
    hint strings.
  - `pixi.toml` — new `bun` dependency; `frontend-*` and `ci` tasks
    retargeted to Bun.
  - `scripts/dev_server.sh` — Bun build check/commands, `frontend/out`.
  - `.github/workflows/ci.yml` — remove `actions/setup-node`.
  - `README.md`, `SPEC.md` — prerequisites, run steps, architecture
    notes.
- **Affected dependencies**: adds `bun` (pixi/conda-forge), `next`;
  removes `vite`, `@vitejs/plugin-react`, the Node.js/npm prerequisite.
  `react`/`react-dom` 19 stay; `oxlint` stays.
- **Affected systems**: local developer setup (Bun instead of Node);
  GitHub Actions CI (no Node setup step). No production/deployment
  infrastructure exists or is touched. The Mojo backend, its API surface,
  Postgres, and Playwright are untouched.
- **Risk to resolve in design**: whether `bun` on conda-forge is
  available and current enough for the Linux runner and dev machines
  (`platforms = ["linux-64"]`), and confirming Next static export serves
  correctly through `backend/server.py`'s existing static handler.
