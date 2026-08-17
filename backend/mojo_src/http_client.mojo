# Thin native-Mojo wrappers around the handful of `urllib`/`time` stdlib
# calls the crawler needs (see SPEC.md ss6 for why these specific pieces are
# Python interop rather than native Mojo). Control flow -- what to fetch,
# in what order, how long to wait -- lives here in Mojo; Python only does
# the actual socket I/O.

from std.python import Python, PythonObject

comptime USER_AGENT = "MojoCrawlerPOC/1.0 (+educational, single-host, rate-limited)"
comptime REQUEST_TIMEOUT_SECONDS = 10
comptime RATE_LIMIT_SECONDS = 0.5


struct FetchResult(Copyable, Movable):
    var ok: Bool
    var status: Int
    var body: String
    var error: String

    def __init__(out self, ok: Bool, status: Int, body: String, error: String):
        self.ok = ok
        self.status = status
        self.body = body
        self.error = error


def fetch(url: String) raises -> FetchResult:
    """GET `url` with a descriptive User-Agent and a fixed timeout."""
    var urllib_request = Python.import_module("urllib.request")
    try:
        var req = urllib_request.Request(url, headers=Python.dict())
        req.add_header("User-Agent", USER_AGENT)
        var resp = urllib_request.urlopen(req, timeout=PythonObject(REQUEST_TIMEOUT_SECONDS))
        var status = Int(String(resp.status))
        var body_bytes = resp.read()
        var body = String(body_bytes.decode("utf-8", "replace"))
        return FetchResult(True, status, body, String(""))
    except e:
        return FetchResult(False, 0, String(""), String(e))


def can_fetch(url: String) raises -> Bool:
    """Check the target host's robots.txt before crawling it."""
    var urlparse = Python.import_module("urllib.parse")
    var robotparser = Python.import_module("urllib.robotparser")
    try:
        var parts = urlparse.urlsplit(url)
        var robots_url = String(parts.scheme) + "://" + String(parts.netloc) + "/robots.txt"
        var rp = robotparser.RobotFileParser()
        rp.set_url(robots_url)
        rp.read()
        var allowed = rp.can_fetch(USER_AGENT, url)
        return Bool(allowed)
    except e:
        # No robots.txt / unreachable: default to allowed, matching what a
        # normal browser visit would do.
        return True


def resolve_url(base_url: String, relative_url: String) raises -> String:
    var urlparse = Python.import_module("urllib.parse")
    return String(urlparse.urljoin(base_url, relative_url))


def rate_limit_sleep() raises:
    var time_mod = Python.import_module("time")
    time_mod.sleep(RATE_LIMIT_SECONDS)


def now_iso() raises -> String:
    var datetime_mod = Python.import_module("datetime")
    var now = datetime_mod.datetime.now(datetime_mod.timezone.utc)
    return String(now.isoformat())
