# The one file in this project with Playwright interop -- a JS-rendering
# fallback for pages whose product listing doesn't exist in the raw fetched
# HTML at all (client-rendered SPAs; see html_extract.looks_like_client_
# rendered_app). Every other file keeps working with plain FetchResult
# values (the same struct http_client.fetch returns) and doesn't need to
# know whether a page's HTML came from urllib or a rendered browser.
#
# Deliberately not reused across pages/crawls: a fresh headless Chromium is
# launched per call and closed before returning. See openspec/changes/
# add-js-rendered-crawling/design.md for why (this fallback only ever runs
# on the minority of pages that need it, so the per-call launch cost is an
# acceptable simplicity/POC trade-off).

from std.python import Python, PythonObject
from http_client import FetchResult

comptime NAVIGATION_TIMEOUT_MS = 30000
comptime RENDER_SETTLE_MS = 3000


def render_fetch(url: String) raises -> FetchResult:
    """Fetch `url` by actually rendering it in headless Chromium, for pages
    whose product markup only exists after client-side JavaScript runs.
    Returns the same FetchResult shape as http_client.fetch, with `body`
    being the rendered DOM's HTML instead of the raw response body."""
    try:
        var sync_api = Python.import_module("playwright.sync_api")
        var pw_cm = sync_api.sync_playwright()
        var pw = pw_cm.__enter__()
        try:
            var browser_args = Python.list()
            browser_args.append("--no-sandbox")
            var browser = pw.chromium.launch(args=browser_args)
            try:
                var page = browser.new_page()
                var resp = page.goto(
                    url,
                    wait_until="domcontentloaded",
                    timeout=PythonObject(NAVIGATION_TIMEOUT_MS),
                )
                # Give client-side rendering a bounded amount of time to
                # finish. `networkidle` isn't a usable wait condition here:
                # sites with continuous background XHR/analytics traffic
                # (confirmed on the real site this fallback was built for)
                # never reach it, degenerating to "always wait the full
                # timeout" -- a fixed settle delay is simpler and, for that
                # site, strictly faster.
                page.wait_for_timeout(PythonObject(RENDER_SETTLE_MS))
                var html = String(page.content())
                var status = 200
                if resp is not None:
                    status = Int(String(resp.status))
                return FetchResult(True, status, html, String(""))
            finally:
                browser.close()
        finally:
            pw_cm.__exit__(Python.none(), Python.none(), Python.none())
    except e:
        return FetchResult(False, 0, String(""), String(e))
