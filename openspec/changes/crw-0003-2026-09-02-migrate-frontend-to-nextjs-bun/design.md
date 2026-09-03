## Context

See `proposal.md` — Why / What Changes for motivation and scope. Relevant
current state:

- `frontend/` is a Vite + React 19 SPA: `index.html` → `src/main.jsx`
  (`createRoot`) → `src/App.jsx` (one file, ~640 lines, entirely
  `useState`/`useEffect`/`useCallback`/`fetch` — no router, no SSR). Two
  local CSS files (`index.css`, `App.css`). One static asset,
  `public/favicon.svg`.
- The build (`vite build`) emits `frontend/dist/`. `backend/server.py`
  sets `STATIC_DIR = frontend/dist` and serves it with a hand-rolled
  static handler: path-traversal guard, `index.html` SPA fallback for
  any non-file non-`/api/` path, and a small extension→content-type map.
- Dev: `vite` dev server with `server.proxy` forwarding `/api` to
  `http://127.0.0.1:8000`. `vite.config.js` uses `@vitejs/plugin-react`.
- Lint: `oxlint` via `.oxlintrc.json` (`plugins: ["react", "oxc"]`,
  rules-of-hooks + only-export-components). Wired as `npm run lint`.
- Toolchain: npm + `package-lock.json`. Node.js is a **manual**
  prerequisite (`README.md` "Prerequisites"); pixi does not manage it.
  CI adds `actions/setup-node` alongside `setup-pixi`, then `pixi run ci`
  runs `cd frontend && npm ci && npm run lint && npm run build`.
- `scripts/dev_server.sh` (`pixi run dev`) gates on
  `frontend/dist/index.html`, running `npm install --prefix frontend` +
  `npm run build --prefix frontend` if the build is missing, before
  starting the backend.
- Everything else (Mojo, the interop Python, Postgres, `psycopg2`,
  `playwright-python`) is pixi-managed from `pixi.toml` /`pixi.lock`.
  `platforms = ["linux-64"]`.
- `SPEC.md` records an explicit past decision: "React via Vite, not
  Next.js" — no SSR needed for a POC, Vite's static `dist/` served
  directly. This change reverses that.

## Goals / Non-Goals

**Goals:**

- Frontend framework is Next.js (App Router); the build is a static
  export served unchanged by `backend/server.py`'s existing static
  handler.
- Bun is the only frontend toolchain, and it is pixi-provisioned — no
  manual prerequisite, no `actions/setup-node`.
- Byte-for-byte-equivalent UI behaviour: same components, same fetch
  calls, same polling, same CSS.
- `pixi run dev`, `pixi run ci`, and the `frontend-*` tasks keep working
  with the same names and the same "one command" ergonomics.

**Non-Goals:**

- No SSR, React Server Components, route handlers, middleware, or any
  Next.js server-runtime feature. Static export only.
- No TypeScript migration. Files stay `.jsx`/`.js`.
- No routing beyond the single existing page. The products/categories
  tab switch stays client-state, not URL routes.
- No linter change (keep `oxlint`; do not adopt `eslint`/`next lint`).
- No CSS framework, no component-library, no visual redesign.
- No change to the Mojo backend, the `/api` surface, Postgres, or
  Playwright.
- No deployment/hosting target (none exists — see `crw-0001-add-ci`).

## Decisions

### 1. Static export (`output: 'export'`), not a Next.js server

`next.config.js` sets `output: 'export'`. `next build` then emits a fully
static site (default `out/`) that any file server can serve — so
`backend/server.py` keeps its role as the single process serving both the
UI and `/api`. No second port, no reverse proxy, no CORS, no process
manager, and the deployment story stays "run one Python process."

- **Alternative — run `next start` (or `next dev`) as a long-lived
  server and have `backend/server.py` reverse-proxy `/` to it**: adds a
  second runtime process to supervise, a second port, and startup
  ordering between the two. All of it to gain SSR/RSC the POC has
  explicitly said it does not want. Rejected.
- **Alternative — keep Vite, just swap npm→Bun**: smaller, but does not
  deliver the "move to Next.js" the change is for. Rejected (this is the
  literal ask).

Static export constraints we accept because the app already lives within
them: no `next/image` optimization loader (not used), no dynamic route
params without `generateStaticParams` (no dynamic routes), no server
code (none).

### 2. App Router with one client-component page

Structure:

```
frontend/
  app/
    layout.jsx     # <html><body>, imports index.css; exports metadata (title)
    page.jsx       # 'use client'; the current App.jsx body, verbatim
    App.css        # imported by page.jsx (unchanged)
    index.css      # imported by layout.jsx (unchanged, was main.jsx's import)
  public/
    favicon.svg    # unchanged
  next.config.js   # output: 'export', rewrites()
  package.json     # next + react + react-dom + oxlint; bun scripts
  .oxlintrc.json   # unchanged rules; see decision 6
```

`app/page.jsx` is the entire current `App.jsx` with a `'use client'`
directive prepended (it is 100% hooks + browser `fetch` + event
handlers). `index.html`, `src/main.jsx`, `vite.config.js`, and the `src/`
directory are deleted; `createRoot`/`StrictMode` bootstrapping is now
Next's job. `layout.jsx` carries the `<title>Mojo Product Crawler</title>`
(via `export const metadata`) and the favicon link that `index.html` had.

- **Alternative — Pages Router (`pages/index.jsx`)**: simpler mental
  model for a one-page app and no `'use client'` needed, but it is the
  legacy router; new Next.js work should be App Router. Since the app is
  trivially small the migration cost is identical either way. Chose App
  Router as the forward-looking default.

### 3. Bun is pixi-provisioned via conda-forge

Add to `pixi.toml` `[dependencies]`: `bun = ">=1.1,<2"` (conda-forge ships
`bun` for `linux-64`). This mirrors how Mojo/Postgres/`psycopg2` are
handled — one declaration in `pixi.toml`, pinned by `pixi.lock`, so dev
and CI resolve the identical version. The `README.md` "Prerequisites"
list loses Node.js/npm and does **not** gain Bun as a manual step (pixi
handles it); it keeps only pixi itself.

- **Alternative — `oven-sh/setup-bun` in CI + "install Bun yourself"
  in the README**: this is exactly the split we are trying to remove
  (it is what Node.js does today). Rejected.
- **Risk if conda-forge's `bun` lags upstream**: pinned range is wide
  (`>=1.1,<2`) and Next.js static export needs nothing bleeding-edge.
  Verified as the first implementation task (see `tasks.md`).

### 4. `backend/server.py`: point `STATIC_DIR` at the export dir

One-line change: `STATIC_DIR = PROJECT_ROOT / "frontend" / "out"` (was
`.../ "dist"`). The static handler itself — traversal guard, SPA
`index.html` fallback, content-type map — is unchanged and already
correct for a static export (which is just `index.html` + `_next/static/…`
+ `favicon.svg`). Update the two "Frontend build not found. Run …"
hint strings to name the new commands. `next build` with `output:
'export'` writes `out/` at the project-relative path
`frontend/out/`, so no `distDir` override is needed.

- Keep the export directory as `out/` (Next default) rather than
  overriding it back to `dist/`: less config, and `dist/` carried Vite
  connotations. `.gitignore` swaps `dist` → `out` and adds `.next`
  (Next's build cache).

### 5. Dev-time `/api` proxy → `next.config.js` `rewrites()`

```js
async rewrites() {
  return [{ source: '/api/:path*', destination: 'http://127.0.0.1:8000/api/:path*' }]
}
```

Replaces `vite.config.js`'s `server.proxy`. `rewrites()` is honored by
`next dev`; it is inert in a static export (no server to rewrite), which
is fine — the export is only ever served by `backend/server.py`, where
`/api` is a real route. Note the dev-server port changes from Vite's 5173
to Next's 3000; `scripts/dev_server.sh` is unaffected (it builds the
frontend and runs the *backend*, it never starts the frontend dev
server), and `pixi run frontend-dev` just prints whatever port Next
picks.

### 6. Keep `oxlint`, run it through Bun

`package.json` `scripts.lint` stays `oxlint`; it is invoked as `bun run
lint`. `oxlint` is a standalone Rust binary pulled from the npm registry
by `bun install` exactly as npm fetched it — no Node runtime needed to
run it. `.oxlintrc.json` keeps `plugins: ["react", "oxc"]` and both
rules. One caveat: it currently `$ref`s
`./node_modules/oxlint/configuration_schema.json`; Bun installs a
`node_modules/` tree so that path still resolves. The new `app/`
directory is linted; `rules-of-hooks` / `only-export-components` apply to
`page.jsx` and `layout.jsx` unchanged.

- **Alternative — `next lint` (ESLint + `eslint-config-next`)**: pulls
  in ESLint and a plugin set the project deliberately does not use, and
  is slower. `oxlint` already covers rules-of-hooks. Rejected; out of
  scope.

### 7. pixi task and CI wiring

`pixi.toml`:

| task | before | after |
|---|---|---|
| `frontend-install` | `npm install` (cwd `frontend`) | `bun install` (cwd `frontend`) |
| `frontend-build` | `npm run build` | `bun run build` (`next build`) |
| `frontend-dev` | `npm run dev` | `bun run dev` (`next dev`) |
| `ci` | `pixi run test && cd frontend && npm ci && npm run lint && npm run build` | `pixi run test && cd frontend && bun install --frozen-lockfile && bun run lint && bun run build` |

`package.json` `scripts`: `dev` → `next dev`, `build` → `next build`,
`lint` → `oxlint`, `start`/`preview` dropped (no server). `bun install
--frozen-lockfile` is the `npm ci` equivalent (lockfile-exact, fails on
drift) for the verification context; `frontend-install` stays plain `bun
install` for interactive dev.

`.github/workflows/ci.yml`: delete the `actions/setup-node` step. Nothing
replaces it — `pixi run ci` gets `bun` from the pixi environment
`setup-pixi` already installs. `setup-pixi`'s lockfile cache now also
covers Bun.

### 8. `scripts/dev_server.sh`

Three edits: gate on `frontend/out/index.html` (was
`frontend/dist/index.html`); `bun install` when `frontend/node_modules`
is absent (was `npm install --prefix frontend`); `bun run build` in
`frontend/` (was `npm run build --prefix frontend`). Bun has no
`--prefix`; use a subshell `(cd frontend && bun install && bun run
build)`.

## Risks / Trade-offs

- **[Risk] conda-forge `bun` is unavailable, too old, or broken on
  `linux-64`.** → Mitigation: first implementation task is `pixi add bun`
  + `pixi run bun --version` + a throwaway `next build`. If it fails,
  fall back to decision 3's rejected alternative (`setup-bun` in CI, Bun
  as a documented prerequisite) — this changes only `pixi.toml`, the CI
  YAML, and the README, not the app or the specs.
- **[Risk] Next static export produces paths `backend/server.py`'s
  static handler mishandles** (e.g. `_next/static/...` nested dirs, or a
  request for `/` vs `/index.html`). → Mitigation: the handler already
  does `rel_path or "index.html"` and resolves nested paths under
  `STATIC_DIR` with a traversal guard; verify by task with a real
  `next build` output and a manual `curl` of `/`, `/_next/static/...`,
  and an unknown route (SPA fallback). Add content-type map entries if
  the export contains extensions not already mapped (e.g. `.woff2`,
  `.map`).
- **[Risk] `'use client'` + App Router changes hydration timing vs. the
  old `createRoot` mount**, surfacing a latent bug in `App.jsx`'s effect
  ordering (it has several documented race-condition workarounds). →
  Mitigation: the component tree and effects are unchanged; test the
  three flows (browse/filter, crawl, discover) end-to-end against a live
  backend per `specs/web-frontend/spec.md`'s scenarios.
- **[Trade-off] Static export disables future Next.js server features**
  without another migration. → Accepted: the Non-Goals rule them out and
  `SPEC.md` records the POC does not want SSR. Revisiting means changing
  decision 1, which is a deliberate, spec-visible choice.
- **[Trade-off] `bun.lock` is a different lockfile format; anyone with
  local `npm`-based muscle memory has to switch.** → Accepted and
  documented in `README.md`; `package-lock.json` is deleted so there is
  no ambiguity about which is authoritative.

## Migration Plan

No data or schema migration. Sequence (also the `tasks.md` order):

1. Provision Bun via pixi; prove `next build` static export works and
   `backend/server.py` serves it (spike, may be thrown away).
2. Land the `frontend/` restructure (Next app, deleted Vite files,
   `bun.lock`), `backend/server.py` `STATIC_DIR`, `.gitignore`.
3. Rewire `pixi.toml` tasks, `scripts/dev_server.sh`, and
   `.github/workflows/ci.yml`.
4. Update `README.md` and `SPEC.md`.
5. Verify `pixi run ci` green locally, then on a PR (CI without the Node
   step), then walk the three UI flows against a live backend.

Rollback: revert the change set. The old `dist/`-based path, npm
lockfile, and Node prerequisite come back together; nothing else depends
on the new layout.
