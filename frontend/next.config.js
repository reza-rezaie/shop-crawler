/**
 * Next.js config for the Mojo Product Crawler UI.
 *
 * `output: 'export'` makes `next build` emit a fully static site under
 * `out/` -- no Next.js runtime needed to serve it. `backend/server.py`
 * serves that directory directly (it used to serve the old `dist/`
 * build).
 *
 * `rewrites()` proxies `/api/*` to the Mojo/Python backend during
 * `next dev` so the dev server works without CORS. It has no effect on a
 * static export (there's no server to rewrite) -- in production the same
 * `backend/server.py` process serves both the UI and the real `/api`
 * routes, so no proxy is needed there.
 */
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: 'http://127.0.0.1:8000/api/:path*',
      },
    ]
  },
}

module.exports = nextConfig
