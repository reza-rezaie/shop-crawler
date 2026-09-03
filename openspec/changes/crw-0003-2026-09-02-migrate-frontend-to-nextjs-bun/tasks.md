## 1. Prove the toolchain (spike)

- [ ] 1.1 Add `bun` to `pixi.toml` `[dependencies]` (`bun = ">=1.1,<2"`),
      run `pixi install`, and verify `pixi run bun --version` prints a
      1.x version on `linux-64`. If conda-forge has no usable `bun`,
      stop and switch to the `setup-bun`-in-CI fallback (design.md
      decision 3 / Risks) before continuing.
- [ ] 1.2 In a throwaway branch, scaffold a minimal Next.js App Router
      page with `output: 'export'`, run `bun run build`, and verify it
      writes `frontend/out/index.html` plus `_next/static/...` with no
      Next.js server required.
- [ ] 1.3 Temporarily point `backend/server.py`'s `STATIC_DIR` at that
      `out/` and verify `curl localhost:8000/`, a `/_next/static/...`
      asset, and an unknown route (SPA fallback) all return the expected
      files/content-types. Note any missing content-type map entries
      (e.g. `.woff2`, `.map`) for task 3.2. Discard the spike after.

## 2. Restructure the frontend to Next.js

- [ ] 2.1 Rewrite `frontend/package.json`: dependencies `next`, `react`,
      `react-dom` (19.x); devDependency `oxlint`; scripts `dev`=`next
      dev`, `build`=`next build`, `lint`=`oxlint`; remove `vite`,
      `@vitejs/plugin-react`, `@types/*`, `start`/`preview`. Run `bun
      install` and verify it produces `frontend/bun.lock`.
- [ ] 2.2 Add `frontend/next.config.js` with `output: 'export'` and a
      `rewrites()` mapping `/api/:path*` →
      `http://127.0.0.1:8000/api/:path*`; verify `bun run build`
      succeeds.
- [ ] 2.3 Create `frontend/app/layout.jsx` (root `<html><body>`, `import
      './index.css'`, `export const metadata` with the
      `Mojo Product Crawler` title and the favicon link) and
      `frontend/app/page.jsx` (`'use client'` + the current `App.jsx`
      body verbatim, `import './App.css'`). Move `src/index.css`,
      `src/App.css` into `app/`. Verify the built `out/index.html` has
      the title and loads the app.
- [ ] 2.4 Delete `frontend/index.html`, `frontend/src/` (`main.jsx`,
      `App.jsx`, moved CSS), `frontend/vite.config.js`,
      `frontend/package-lock.json`. Verify `rg -l vite frontend` and a
      search for `src/main.jsx` come back empty.
- [ ] 2.5 Update `frontend/.gitignore`: replace `dist` with `out`, add
      `.next`. Keep `node_modules`. Verify `git status` shows neither
      `frontend/out/` nor `frontend/.next/` as untracked after a build.
- [ ] 2.6 Confirm `frontend/.oxlintrc.json` still resolves its
      `node_modules/oxlint/...` schema `$ref` under Bun's install, and
      that `bun run lint` lints `app/` with `rules-of-hooks` /
      `only-export-components` active and passes.

## 3. Backend static serving

- [ ] 3.1 In `backend/server.py`, change `STATIC_DIR` to
      `PROJECT_ROOT / "frontend" / "out"` and update the two
      "Frontend build not found. Run ..." hint strings to name the Bun
      commands. Verify `python backend/server.py` with a built frontend
      serves the UI at `/` and `/api/health` still returns JSON.
- [ ] 3.2 Add any content-type map entries flagged in task 1.3 (e.g.
      `.woff2`, `.map`) so every file in a real `out/` export is served
      with a correct `Content-Type`; verify by `curl -I` against each
      asset type present.
- [ ] 3.3 Verify the SPA fallback: request a path that is not a file and
      not `/api/*` and confirm `backend/server.py` returns
      `out/index.html`.

## 4. pixi tasks, dev script, CI

- [ ] 4.1 Update `pixi.toml` tasks: `frontend-install`=`bun install`,
      `frontend-build`=`bun run build`, `frontend-dev`=`bun run dev`
      (all `cwd = "frontend"`); `ci` = `pixi run test && cd frontend &&
      bun install --frozen-lockfile && bun run lint && bun run build`.
      Verify each task runs.
- [ ] 4.2 Update `scripts/dev_server.sh`: gate on
      `frontend/out/index.html`; use `(cd frontend && bun install)` when
      `frontend/node_modules` is missing and `(cd frontend && bun run
      build)` to build. Verify `pixi run dev` from a clean checkout
      builds the frontend then serves the app on port 8934.
- [ ] 4.3 Edit `.github/workflows/ci.yml` to remove the
      `actions/setup-node` step (nothing replaces it). Verify the YAML
      still has checkout + `setup-pixi` + `pixi run ci`.
- [ ] 4.4 Run `pixi run ci` locally on a clean checkout and verify it
      passes end-to-end (Mojo tests, `bun run lint`, `bun run build`)
      with no Node.js/npm on `PATH`.

## 5. Documentation

- [ ] 5.1 Update `README.md`: drop Node.js/npm from "Prerequisites"
      (pixi now provides Bun); update the "Run it" commands and the
      project-tree comment (`frontend/` line, `dist` → `out`). Verify no
      `npm`/`Node` references remain except historical notes.
- [ ] 5.2 Update `SPEC.md`: revise the "React via Vite, not Next.js"
      section to record this change (now Next.js static export under
      Bun, still no SSR), and any `frontend/dist` / npm references.
      Verify the architecture diagram/text matches the new layout.

## 6. Verification against specs

- [ ] 6.1 With a live backend + built frontend, walk the products view:
      name search, category, source-host, price filters combined, and
      pagination — confirm behaviour matches pre-migration
      (`specs/web-frontend/spec.md` "Browse, filter, and paginate
      products").
- [ ] 6.2 Run a crawl from the UI and confirm the progress bar polling,
      status message, notes list, and automatic source-host narrowing
      behave as before ("Run a crawl" scenario).
- [ ] 6.3 Run category discovery and view a host's category tree; confirm
      discovery progress, status, and the recursive tree with product
      signals behave as before ("Discover and view a site's category
      tree" scenario).
- [ ] 6.4 Start `pixi run frontend-dev`, confirm the Next dev server
      serves the UI and `/api/*` calls reach the backend via the
      `rewrites()` proxy (no CORS errors) ("Dev server proxies API calls
      to the backend").
- [ ] 6.5 Open a real PR for this change; confirm CI runs and passes
      without any Node provisioning step ("CI builds the frontend
      without a Node provisioning step").
