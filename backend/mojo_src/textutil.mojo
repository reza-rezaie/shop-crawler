# Native Mojo string/HTML scanning helpers.
#
# No DOM/HTML-parsing library is used here: books.toscrape.com (and most
# simple listing pages) can be scanned reliably with plain byte-level
# substring search, so this stays pure Mojo. The one exception is entity
# unescaping, which borrows Python's `html.unescape` (see `unescape`) since
# reimplementing the HTML5 entity table natively isn't worth it for a POC.

from std.python import Python


def is_digit(ch: String) -> Bool:
    return ch >= "0" and ch <= "9"


def extract_host(url: String) -> String:
    """Pull the `host[:port]` portion out of an absolute URL, e.g.
    `https://www.example.com/shop/category/` -> `www.example.com`. Used to
    attribute a stored product to the site it was crawled from without
    needing a separate stored column (see db.mojo)."""
    var scheme_end = url.find("://")
    if scheme_end == -1:
        return url
    var host_start = scheme_end + 3
    var path_start = url.find("/", host_start)
    if path_start == -1:
        return String(url[byte = host_start : url.byte_length()])
    return String(url[byte = host_start : path_start])


def to_lower_ascii(s: String) -> String:
    """ASCII-only lowercasing, used for case-insensitive keyword checks on
    short attribute values (class names etc.). Iterates by grapheme (Mojo's
    default String iteration) rather than raw bytes so multi-byte UTF-8
    characters (accents, currency symbols, ...) pass through unchanged
    instead of tripping a codepoint-boundary error."""
    var out = String("")
    for ch in s:
        var ch_str = String(ch)
        if ch_str >= "A" and ch_str <= "Z":
            var code = ord(ch_str) + 32
            out += chr(code)
        else:
            out += ch_str
    return out


def contains_ci(haystack: String, needle: String) -> Bool:
    return to_lower_ascii(needle) in to_lower_ascii(haystack)


def find_tag_open(html: String, tag: String, start: Int) -> Int:
    """Find the next real `<tag` occurrence at or after byte offset `start`,
    requiring a proper boundary after the tag name (space, `>`, `/`, or
    whitespace) so `li` doesn't match inside `link`, etc. Returns -1 if not
    found."""
    var marker = "<" + tag
    var pos = start
    var n = html.byte_length()
    while True:
        var idx = html.find(marker, pos)
        if idx == -1:
            return -1
        var after = idx + marker.byte_length()
        if after < n:
            var ch = String(html[byte = after : after + 1])
            if ch == " " or ch == ">" or ch == "/" or ch == "\t" or ch == "\n" or ch == "\r":
                return idx
        else:
            return idx
        pos = idx + 1


def find_matching_close(html: String, body_start: Int, tag: String) -> Int:
    """Given the byte offset right after an opening `<tag ...>`'s closing
    `>`, depth-match nested same-tag elements to find where `</tag>` closing
    this element ends. Returns the byte offset right after that `</tag>`, or
    -1 if unterminated."""
    var close_marker = "</" + tag + ">"
    var depth = 1
    var pos = body_start
    while depth > 0:
        var next_close = html.find(close_marker, pos)
        if next_close == -1:
            return -1
        var next_open = find_tag_open(html, tag, pos)
        if next_open != -1 and next_open < next_close:
            depth += 1
            var open_end = html.find(">", next_open)
            if open_end == -1:
                return -1
            pos = open_end + 1
        else:
            depth -= 1
            pos = next_close + close_marker.byte_length()
    return pos


def extract_attr(tag_text: String, attr_name: String) -> Optional[String]:
    """Extract `attr_name="..."` or `attr_name='...'` from a single opening
    tag's text (e.g. `<a href="foo" class="bar">`). Requires a proper
    boundary immediately before `attr_name`, so looking up `class` can never
    return the value of a differently-named attribute that merely ends with
    the same characters (e.g. `ng-class`)."""
    var dq_result = _find_attr_value(tag_text, attr_name + '="', '"')
    if dq_result:
        return dq_result

    var sq_result = _find_attr_value(tag_text, attr_name + "='", "'")
    if sq_result:
        return sq_result

    return None


def _find_attr_value(tag_text: String, marker: String, quote: String) -> Optional[String]:
    var pos = 0
    while True:
        var idx = tag_text.find(marker, pos)
        if idx == -1:
            return None

        var boundary_ok = True
        if idx > 0:
            var before = String(tag_text[byte = idx - 1 : idx])
            if not (
                before == " "
                or before == "\t"
                or before == "\n"
                or before == "\r"
                or before == '"'
                or before == "'"
            ):
                boundary_ok = False

        if boundary_ok:
            var start = idx + marker.byte_length()
            var end = tag_text.find(quote, start)
            if end == -1:
                return None
            return String(tag_text[byte = start : end])

        pos = idx + 1


def is_valid_class_token(token: String) -> Bool:
    """Whether `token` could be a real CSS class name: letters, digits,
    `-`, or `_` only. Used to reject JS-framework binding expressions
    (`{ 'x': product.y }`, `product.favoriteProcessing`, ...) that contain
    a hint word as plain text but aren't actual class names."""
    if token.byte_length() == 0:
        return False
    for ch in token:
        var c = String(ch)
        var is_ascii_alnum = (c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")
        if not (is_ascii_alnum or c == "-" or c == "_"):
            return False
    return True


def class_hint_matches(class_value: String, hint: String) -> Bool:
    """Whether `hint` appears inside one of `class_value`'s individual,
    whitespace-separated class tokens -- not merely anywhere in the raw
    attribute text. This is what keeps a `class="{ 'x':
    product.favoriteProcessing }"` binding expression from being mistaken
    for a real `product`-ish class."""
    var normalized = collapse_whitespace(class_value)
    var tokens = normalized.split(" ")
    for token in tokens:
        var t = String(token)
        if is_valid_class_token(t) and contains_ci(t, hint):
            return True
    return False


def extract_blocks_by_class_hint(html: String, tag: String, class_hint: String) -> List[String]:
    """Find all `<tag ...class="...hint...">...</tag>` elements (case
    insensitive hint match against a whole class token), returned as their
    full outer HTML."""
    var results = List[String]()
    var pos = 0
    while True:
        var open_idx = find_tag_open(html, tag, pos)
        if open_idx == -1:
            break
        var open_end = html.find(">", open_idx)
        if open_end == -1:
            break
        var open_tag_text = String(html[byte = open_idx : open_end + 1])
        var class_val = extract_attr(open_tag_text, "class")
        var is_match = False
        if class_val:
            if class_hint_matches(class_val.value(), class_hint):
                is_match = True
        if is_match:
            var close_end = find_matching_close(html, open_end + 1, tag)
            if close_end != -1:
                results.append(String(html[byte = open_idx : close_end]))
                pos = close_end
            else:
                pos = open_end + 1
        else:
            pos = open_end + 1
    return results^


def extract_first_tag_block(html: String, tag: String, start: Int = 0) -> Optional[String]:
    """Find the first `<tag>...</tag>` element at/after `start`, regardless
    of class, returned as its full outer HTML."""
    var open_idx = find_tag_open(html, tag, start)
    if open_idx == -1:
        return None
    var open_end = html.find(">", open_idx)
    if open_end == -1:
        return None
    var close_end = find_matching_close(html, open_end + 1, tag)
    if close_end == -1:
        return None
    return String(html[byte = open_idx : close_end])


def extract_first_void_tag(html: String, tag: String, start: Int = 0) -> Optional[String]:
    """Find the first `<tag ...>` at/after `start` and return just its
    opening-tag text. For void elements (`img`, `link`, `br`, ...) that
    never have a matching `</tag>`, so `find_matching_close` doesn't apply."""
    var open_idx = find_tag_open(html, tag, start)
    if open_idx == -1:
        return None
    var open_end = html.find(">", open_idx)
    if open_end == -1:
        return None
    return String(html[byte = open_idx : open_end + 1])


def inner_text_of_first(html: String, tag: String) -> Optional[String]:
    """Get the raw inner HTML/text of the first `<tag>...</tag>` found."""
    var open_idx = find_tag_open(html, tag, 0)
    if open_idx == -1:
        return None
    var open_end = html.find(">", open_idx)
    if open_end == -1:
        return None
    var close_marker = "</" + tag + ">"
    var close_idx = html.find(close_marker, open_end + 1)
    if close_idx == -1:
        return None
    return String(html[byte = open_end + 1 : close_idx])


def strip_tags(html_fragment: String) -> String:
    """Remove `<...>` markup, leaving plain text. Iterates by grapheme (see
    `to_lower_ascii`) so it is safe on non-ASCII text content."""
    var out = String("")
    var in_tag = False
    for ch in html_fragment:
        var ch_str = String(ch)
        if ch_str == "<":
            in_tag = True
        elif ch_str == ">":
            in_tag = False
        elif not in_tag:
            out += ch_str
    return out


def unescape(text: String) raises -> String:
    """Unescape HTML entities (&amp; &#39; etc.) via Python's stdlib `html`
    module -- Mojo has no native entity table, so this is one of the
    documented, minimal Python-interop pieces (see SPEC.md ss6)."""
    var html_mod = Python.import_module("html")
    var result = html_mod.unescape(text)
    return String(result)


def clean_text(html_fragment: String) raises -> String:
    """strip_tags + unescape + collapse surrounding whitespace."""
    var stripped = strip_tags(html_fragment)
    var unescaped = unescape(stripped)
    return collapse_whitespace(String(unescaped.strip()))


def collapse_whitespace(s: String) -> String:
    """Collapse runs of whitespace to a single space. Iterates by grapheme
    (see `to_lower_ascii`) so it is safe on non-ASCII text content."""
    var out = String("")
    var last_was_space = False
    for ch in s:
        var ch_str = String(ch)
        var is_space = ch_str == " " or ch_str == "\t" or ch_str == "\n" or ch_str == "\r"
        if is_space:
            if not last_was_space:
                out += " "
            last_was_space = True
        else:
            out += ch_str
            last_was_space = False
    return String(out.strip())
