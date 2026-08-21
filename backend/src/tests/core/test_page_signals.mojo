# Tests for core/page_signals.mojo's SPA-shell detection, added alongside
# the azurestandard.com bug fix: a client-rendered page that yields zero
# products should say so explicitly instead of failing silently.
#
# Run with: pixi run mojo run -I backend/src backend/src/tests/core/test_page_signals.mojo

from std.python import Python
from tests.testing import check
from core.page_signals import looks_like_client_rendered_app


def _read_fixture(name: String) raises -> String:
    var pyio = Python.import_module("builtins")
    var f = pyio.open("backend/src/tests/fixtures/" + name, "r", encoding="utf-8")
    var content = String(f.read())
    f.close()
    return content


def test_spa_shell_detection() raises:
    var spa_html = _read_fixture("spa_shell_angular.html")
    check(
        looks_like_client_rendered_app(spa_html, 0),
        "SPA-shell markup with zero products is flagged as likely client-rendered",
    )
    check(
        not looks_like_client_rendered_app(spa_html, 5),
        "SPA-shell markup is not flagged when products were actually found",
    )

    var normal_html = _read_fixture("books_toscrape_listing.html")
    check(
        not looks_like_client_rendered_app(normal_html, 0),
        "an ordinary static page with zero products is not flagged (no SPA markers present)",
    )


def main() raises:
    test_spa_shell_detection()
    print("All page_signals tests passed.")
