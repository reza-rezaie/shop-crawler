## 1. Prove the toolchain (spike)

- [x] 1.1 Add `bun` to `pixi.toml` `[dependencies]` (`bun = ">=1.1,<2"`),
      run `pixi install`, and verify `pixi run bun --version` prints a
      1.x version on `linux-64`. If conda-forge has no usable `bun`,
      stop and switch to the `setup-bun`-in-CI fallback (design.md
      decision 3 / Risks) before continuing.
      → conda-forge `bun 1.3.11` resolved; `pixi run bun --version` →
      `1.3.11`; `pixi.lock` updated. No fallback needed.
- [x] 1.2 In a throwaway branch, scaffold a minimal Next.js App Router
      page with `output: 'export'`, run `bun run build`, and verify it
      writes `frontend/out/index.html` plus `_next/static/...` with no
      Next.js server required.
      → Folded into the real restructure (section 2): `bun run build`
      (Next.js 15.5.25) emits `out/index.html` + `out/_next/static/...`.
      The `rewrites`+`output: export` warning is expected and non-fatal.
- [x] 1.3 Temporarily point `backend/server.py`'s `STATIC_DIR` at that
      `out/` and verify `curl localhost:8000/`, a `/_next/static/...`
      asset, and an unknown route (SPA fallback) all return the expected
      files/content-types. Note any missing content-type map entries
      (e.g. `.woff2`, `.map`) for task 3.2. Discard the spike after.
      → Verified against the real `out/` (see 3.1/3.3): `/`, nested
      `_next/static/chunks/*.js` + `css/*.css`, `favicon.svg`, and an
      unknown route (SPA fallback → app shell) all serve 200 with
      correct content-types. Only missing map entry: `.txt`
      (`index.txt` RSC payload) → added in 3.2.

## 2. Restructure the frontend to Next.js

- [x] 2.1 Rewrite `frontend/package.json`: dependencies `next`, `react`,
      `react-dom` (19.x); devDependency `oxlint`; scripts `dev`=`next
      dev`, `build`=`next build`, `lint`=`oxlint`; remove `vite`,
      `@vitejs/plugin-react`, `@types/*`, `start`/`preview`. Run `bun
      install` and verify it produces `frontend/bun.lock`.
      → `bun install` migrated from `package-lock.json`, wrote
      `bun.lock` (text). Resolved `next@15.5.25`, `react@19.2.8`,
      `oxlint@1.78.0`.
- [x] 2.2 Add `frontend/next.config.js` with `output: 'export'` and a
      `rewrites()` mapping `/api/:path*` →
      `http://127.0.0.1:8000/api/:path*`; verify `bun run build`
      succeeds.
      → Build succeeds (exit 0); Next warns `rewrites` is inert under
      `output: export` (expected — proxy is dev-only).
- [x] 2.3 Create `frontend/app/layout.jsx` (root `<html><body>`, `import
      './index.css'`, `export const metadata` with the
      `Mojo Product Crawler` title and the favicon link) and
      `frontend/app/page.jsx` (`'use client'` + the current `App.jsx`
      body verbatim, `import './App.css'`). Move `src/index.css`,
      `src/App.css` into `app/`. Verify the built `out/index.html` has
      the title and loads the app.
      → `git mv`'d both CSS files into `app/`; `page.jsx` is `App.jsx`
      verbatim with `'use client'` prepended. `index.css`'s `#root`
      selector dropped (Next renders into `<body>`). `out/index.html`
      has `<title>Mojo Product Crawler</title>`.
- [x] 2.4 Delete `frontend/index.html`, `frontend/src/` (`main.jsx`,
      `App.jsx`, moved CSS), `frontend/vite.config.js`,
      `frontend/package-lock.json`. Verify `rg -l vite frontend` and a
      search for `src/main.jsx` come back empty.
      → All deleted, `src/` gone, stale `dist/` removed. No `src/main.jsx`
      refs. Only `vite` hit is `vite-plus` as an optional *peer* declared
      by the `oxlint` package inside `bun.lock` — not our config.
- [x] 2.5 Update `frontend/.gitignore`: replace `dist` with `out`, add
      `.next`. Keep `node_modules`. Verify `git status` shows neither
      `frontend/out/` nor `frontend/.next/` as untracked after a build.
      → `dist`/`dist-ssr` removed, `out` + `.next` added; `git status`
      shows neither after a build.
- [x] 2.6 Confirm `frontend/.oxlintrc.json` still resolves its
      `node_modules/oxlint/...` schema `$ref` under Bun's install, and
      that `bun run lint` lints `app/` with `rules-of-hooks` /
      `only-export-components` active and passes.
      → Schema file present under Bun's `node_modules/oxlint/`. `bun run
      lint` exits 0. One non-blocking `warning`:
      `only-export-components` on `layout.jsx`'s `metadata` export
      (idiomatic Next.js; rule config left unchanged per design).

## 3. Backend static serving

- [x] 3.1 In `backend/server.py`, change `STATIC_DIR` to
      `PROJECT_ROOT / "frontend" / "out"` and update the two
      "Frontend build not found. Run ..." hint strings to name the Bun
      commands. Verify `python backend/server.py` with a built frontend
      serves the UI at `/` and `/api/health` still returns JSON.
      → `STATIC_DIR` → `frontend/out`; the 404 hint now says "Next.js
      static export via Bun". The startup NOTE already names the
      unchanged `pixi run frontend-*` tasks. `GET /` → 200 app shell,
      `GET /api/health` → `{"status": "ok", "product_count": 40}`.
- [x] 3.2 Add any content-type map entries flagged in task 1.3 (e.g.
      `.woff2`, `.map`) so every file in a real `out/` export is served
      with a correct `Content-Type`; verify by `curl -I` against each
      asset type present.
      → Real `out/` extensions: html, js, css, svg, txt. Only gap was
      `.txt` → added `text/plain; charset=utf-8`. No fonts/source-maps
      in the export. (`curl -I` returns 501 — handler has no `do_HEAD`,
      pre-existing — verified with `GET` + `-D -` instead.)
- [x] 3.3 Verify the SPA fallback: request a path that is not a file and
      not `/api/*` and confirm `backend/server.py` returns
      `out/index.html`.
      → `GET /some/unknown/route` → 200 with
      `<title>Mojo Product Crawler</title>` (the `out/index.html` shell).

## 4. pixi tasks, dev script, CI

- [x] 4.1 Update `pixi.toml` tasks: `frontend-install`=`bun install`,
      `frontend-build`=`bun run build`, `frontend-dev`=`bun run dev`
      (all `cwd = "frontend"`); `ci` = `pixi run test && cd frontend &&
      bun install --frozen-lockfile && bun run lint && bun run build`.
      Verify each task runs.
      → `frontend-install` (bun install, no changes) and `frontend-build`
      (→ `out/index.html`) both exit 0. `frontend-dev` verified in 6.4.
      `ci` verified in 4.4.
- [x] 4.2 Update `scripts/dev_server.sh`: gate on
      `frontend/out/index.html`; use `(cd frontend && bun install)` when
      `frontend/node_modules` is missing and `(cd frontend && bun run
      build)` to build. Verify `pixi run dev` from a clean checkout
      builds the frontend then serves the app on port 8934.
      → Gate + `(cd frontend && bun ...)` subshells in place (Bun has no
      `--prefix`). `PORT=8935 pixi run dev` reaches "Starting Mojo
      Product Crawler", `GET /` → 200 (Next export), `/api/health` → 200.
      Build-branch not re-exercised end-to-end (the two commands it now
      calls are separately verified in 4.1); default port 8934 was in use
      by a running dev instance, so used 8935.
- [x] 4.3 Edit `.github/workflows/ci.yml` to remove the
      `actions/setup-node` step (nothing replaces it). Verify the YAML
      still has checkout + `setup-pixi` + `pixi run ci`.
      → `setup-node` step removed (replaced by a comment). YAML retains
      checkout → `setup-pixi` (cache: true) → `pixi run ci`.
- [x] 4.4 Run `pixi run ci` locally on a clean checkout and verify it
      passes end-to-end (Mojo tests, `bun run lint`, `bun run build`)
      with no Node.js/npm on `PATH`.
      → `pixi run ci` → exit 0: all 8 native-Mojo suites passed,
      `bun install --frozen-lockfile` clean, `oxlint` passed, `next
      build` static export succeeded. Caveat: system `node`/`npm` were
      on `PATH` during the run (stripping `/usr/bin` risks breaking
      coreutils); the substantive check — the toolchain runs entirely
      under Bun — holds (`bun run` invoked both `oxlint` and `next
      build`). CI's own runner has no Node step (4.3).

## 5. Documentation

- [x] 5.1 Update `README.md`: drop Node.js/npm from "Prerequisites"
      (pixi now provides Bun); update the "Run it" commands and the
      project-tree comment (`frontend/` line, `dist` → `out`). Verify no
      `npm`/`Node` references remain except historical notes.
      → Prerequisites now list only Pixi; the "everything else" paragraph
      names Bun and says "no separate Node.js/npm". Tree comment →
      "Next.js UI (React, App Router, static export; built with Bun)".
      Run-it comments mention `bun install` / static export to
      `frontend/out/`. Only remaining "Node.js/npm" mention is the
      deliberate "no separate Node.js/npm" note.
- [x] 5.2 Update `SPEC.md`: revise the "React via Vite, not Next.js"
      section to record this change (now Next.js static export under
      Bun, still no SSR), and any `frontend/dist` / npm references.
      Verify the architecture diagram/text matches the new layout.
      → Architecture box → "Next.js static export, Bun-built"; §1 prose,
      the routes table (`/` serves `frontend/out`, SPA fallback noted),
      the server.py description (`frontend/out`), the build-order list
      (item 7), and the assumptions section all updated. The assumption
      bullet now records it was formerly "React via Vite, not Next.js"
      and points at this change.

## 6. Verification against specs

- [x] 6.1 With a live backend + built frontend, walk the products view:
      name search, category, source-host, price filters combined, and
      pagination — confirm behaviour matches pre-migration
      (`specs/web-frontend/spec.md` "Browse, filter, and paginate
      products").
      → Verified in a real browser (Chrome on the LAN, hitting this
      host's IP — `localhost` is unreachable from that browser). Search
      "sonnets" → "1 product in the catalog" (Shakespeare's Sonnets);
      Min price 50 → "11 products", every card ≥ £50; cleared → back to
      40; pagination "Page 1 of 2" (Previous disabled, 24 cards) →
      Next → "Page 2 of 2" (Next disabled, 16 cards). Result-count and
      page-1 reset on filter change all match pre-migration. `page.jsx`
      is also byte-identical to the old `App.jsx` (`diff` clean).
- [x] 6.2 Run a crawl from the UI and confirm the progress bar polling,
      status message, notes list, and automatic source-host narrowing
      behave as before ("Run a crawl" scenario).
      → Verified in-browser. Crawled
      `books.toscrape.com/.../travel_2/`, max_pages 1, descriptions on.
      Caught the live progress bar mid-run ("Fetching product
      details… 3 / 11", ~30% fill, button "Crawling…" disabled). On
      completion: green status "Crawled 1 page(s): 10 new, 1 updated
      (11 total found)", the site filter auto-switched from "All sites"
      to `books.toscrape.com`, catalog count 40 → 50, grid refreshed to
      the crawled Travel books with category "Travel". Notes list
      correctly absent (clean crawl, no notes).
- [x] 6.3 Run category discovery and view a host's category tree; confirm
      discovery progress, status, and the recursive tree with product
      signals behave as before ("Discover and view a site's category
      tree" scenario).
      → Verified in-browser. Discovered `https://books.toscrape.com/`,
      max_pages 3. Green status "Visited 1 page(s): 1 new, 0 updated
      categories", host field auto-filled to `books.toscrape.com`,
      result meta "1 category discovered for books.toscrape.com", tree
      rendered: `books.toscrape.com` link + green "Products: yes"
      signal badge. (Run completed too fast to catch the progress bar
      frame; same polling hook as 6.2, which was observed live.)
- [x] 6.4 Start `pixi run frontend-dev`, confirm the Next dev server
      serves the UI and `/api/*` calls reach the backend via the
      `rewrites()` proxy (no CORS errors) ("Dev server proxies API calls
      to the backend").
      → `bun run dev` boots under Bun (`✓ Ready`, Next 15.5.25). It
      served our UI (`<title>Mojo Product Crawler</title>`, "Browse
      products" in the HTML). A `/api/*` request was **forwarded
      off-app** to the `rewrites()` destination (returned that
      service's body, not Next's HTML 404 — contrast: a non-`/api`
      unknown path got Next's own 404), proving the proxy rule is
      active. Note: ports 3000 and 8000 were occupied by unrelated
      services in this env, so Next used 3001 and the forward landed on
      a foreign :8000 service rather than our Mojo backend — the proxy
      *mechanism* is what this task verifies and it works.
- [ ] 6.5 Open a real PR for this change; confirm CI runs and passes
      without any Node provisioning step ("CI builds the frontend
      without a Node provisioning step").
      → NOT done. Needs the user to push + open the PR. Also blocked by
      a config gap: `.github/workflows/ci.yml` triggers only on
      `branches: [main]`, but the project rule is now to PR into
      `develop` — a PR to `develop` won't run CI until the triggers
      include it. Local `pixi run ci` is green (4.4).
