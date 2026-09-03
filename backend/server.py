"""Thin Python HTTP shim -- NOT where the application logic lives.

Everything under src/ (crawling, HTML extraction, price parsing,
filtering, SQL, dedup/upsert) is native Mojo, compiled on the fly and
imported here via `mojo.importer` (Mojo's official Python<->Mojo bridge).
This file's only two jobs are:

  1. Speak raw HTTP (`http.server` from the standard library -- no
     FastAPI/Flask) and route requests to one `api.*` Mojo function each.
  2. Serve the built React frontend's static files for everything else.

See SPEC.md for the full architecture and why the split is drawn here.
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

PROJECT_ROOT = Path(__file__).resolve().parent.parent
MOJO_SRC_DIR = PROJECT_ROOT / "backend" / "src"
DATA_DIR = PROJECT_ROOT / "data"
# The Postgres database to connect to -- host/port/user/password come from
# the standard libpq env vars (PGHOST/PGPORT/PGUSER/PGPASSWORD), defaulted
# by scripts/activate.sh to the pixi-managed local instance (see
# scripts/pg_local.sh). DB_NAME just says which database on that instance.
DB_NAME = os.environ.get("PGDATABASE", "products")
# The Next.js static export (`bun run build` in frontend/, output: 'export').
STATIC_DIR = PROJECT_ROOT / "frontend" / "out"

HOST = os.environ.get("HOST", "0.0.0.0")
if "--port" in sys.argv:
    PORT = int(sys.argv[sys.argv.index("--port") + 1])
else:
    PORT = int(os.environ.get("PORT", "8000"))

DATA_DIR.mkdir(exist_ok=True)

sys.path.insert(0, str(MOJO_SRC_DIR))
import mojo.importer  # noqa: E402  (enables `import api` below to load api.mojo)
import api  # noqa: E402  -- the native Mojo backend


def _json_bytes(obj) -> bytes:
    return json.dumps(obj).encode("utf-8")


# Live progress for whichever crawl/discovery run is currently in flight.
# One shared slot, not a per-job registry: the UI only ever has one crawl
# or discovery button active at a time (disabled while its own request is
# in flight), so there's only ever one run to report on. The dict object
# itself is handed straight into the Mojo crawl/discovery function (as
# request["_progress"]) -- it mutates this same object in place from
# whatever thread is running the POST request, and a concurrent GET
# /api/progress request (a different thread) reads it directly. Plain
# dict reads/writes of primitives are safe here without an explicit lock:
# CPython's GIL makes each individual get/set atomic, and progress is
# advisory display data, not something that needs to be transactionally
# consistent across fields.
CURRENT_PROGRESS = {"active": False}


def _run_with_progress(kind: str, fn, db_path, request):
    """Reset CURRENT_PROGRESS, hand it to the Mojo call as request["_progress"]
    so it can report live updates, and always clear `active` afterwards --
    including on error, so a failed crawl doesn't leave the UI's progress
    bar stuck showing an in-progress run forever."""
    CURRENT_PROGRESS.clear()
    CURRENT_PROGRESS["active"] = True
    CURRENT_PROGRESS["kind"] = kind
    request = dict(request)
    request["_progress"] = CURRENT_PROGRESS
    try:
        return fn(db_path, request)
    finally:
        CURRENT_PROGRESS["active"] = False


class Handler(BaseHTTPRequestHandler):
    server_version = "MojoCrawlerPOC/1.0"

    def log_message(self, fmt, *args):  # quieter default logging
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send_json(self, status: int, payload) -> None:
        body = _json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle_api(self, method: str) -> bool:
        parsed = urlparse(self.path)
        if not parsed.path.startswith("/api/"):
            return False

        try:
            if parsed.path == "/api/health" and method == "GET":
                self._send_json(200, api.health(DB_NAME))
            elif parsed.path == "/api/products" and method == "GET":
                query = {k: v[0] for k, v in parse_qs(parsed.query).items()}
                self._send_json(200, api.list_products(DB_NAME, query))
            elif parsed.path == "/api/categories" and method == "GET":
                self._send_json(200, api.categories(DB_NAME))
            elif parsed.path == "/api/sources" and method == "GET":
                self._send_json(200, api.sources(DB_NAME))
            elif parsed.path == "/api/crawl" and method == "POST":
                length = int(self.headers.get("Content-Length", "0"))
                raw = self.rfile.read(length) if length else b"{}"
                request = json.loads(raw or b"{}")
                self._send_json(200, _run_with_progress("crawl", api.crawl, DB_NAME, request))
            elif parsed.path == "/api/site-categories" and method == "GET":
                query = {k: v[0] for k, v in parse_qs(parsed.query).items()}
                self._send_json(200, api.site_categories(DB_NAME, query))
            elif parsed.path == "/api/site-categories/discover" and method == "POST":
                length = int(self.headers.get("Content-Length", "0"))
                raw = self.rfile.read(length) if length else b"{}"
                request = json.loads(raw or b"{}")
                self._send_json(200, _run_with_progress("discover", api.discover_categories, DB_NAME, request))
            elif parsed.path == "/api/progress" and method == "GET":
                self._send_json(200, dict(CURRENT_PROGRESS))
            else:
                self._send_json(404, {"error": "not found"})
        except Exception as exc:  # keep the shim from ever hard-crashing
            self._send_json(500, {"error": str(exc)})
        return True

    def do_GET(self):
        if self._handle_api("GET"):
            return
        self._serve_static()

    def do_POST(self):
        if self._handle_api("POST"):
            return
        self._send_json(404, {"error": "not found"})

    def _serve_static(self):
        parsed = urlparse(self.path)
        rel_path = parsed.path.lstrip("/") or "index.html"
        candidate = (STATIC_DIR / rel_path).resolve()

        # Never serve outside STATIC_DIR.
        if STATIC_DIR.resolve() not in candidate.parents and candidate != STATIC_DIR.resolve():
            self.send_response(403)
            self.end_headers()
            return

        if not candidate.is_file():
            candidate = STATIC_DIR / "index.html"  # SPA fallback

        if not candidate.is_file():
            self._send_json(
                404,
                {
                    "error": "Frontend build not found. Run `pixi run frontend-install` "
                    "then `pixi run frontend-build` (Next.js static export via Bun) first."
                },
            )
            return

        content_type = _guess_content_type(candidate)
        data = candidate.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def _guess_content_type(path: Path) -> str:
    ext = path.suffix.lower()
    return {
        ".html": "text/html; charset=utf-8",
        ".js": "application/javascript",
        ".css": "text/css",
        ".json": "application/json",
        ".svg": "image/svg+xml",
        ".png": "image/png",
        ".ico": "image/x-icon",
        # Next.js static export emits an index.txt (RSC payload) alongside
        # index.html.
        ".txt": "text/plain; charset=utf-8",
    }.get(ext, "application/octet-stream")


def run_crawl_once(url: str, max_pages: int = 3) -> None:
    """`pixi run crawl` -- crawl from the command line, no server needed."""
    result = api.crawl(DB_NAME, {"url": url, "max_pages": max_pages, "fetch_descriptions": True})
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    if "--crawl-once" in sys.argv:
        idx = sys.argv.index("--crawl-once")
        target_url = sys.argv[idx + 1] if len(sys.argv) > idx + 1 else "https://books.toscrape.com/"
        run_crawl_once(target_url)
        sys.exit(0)

    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Mojo Crawler POC backend listening on {HOST}:{PORT}")
    print(f"Open http://localhost:{PORT} in your browser")
    print(f"Database: {DB_NAME}")
    if not (STATIC_DIR / "index.html").exists():
        print(
            "NOTE: frontend build not found at",
            STATIC_DIR,
            "- run `pixi run frontend-install && pixi run frontend-build` "
            "to serve the UI (the API still works without it).",
        )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
