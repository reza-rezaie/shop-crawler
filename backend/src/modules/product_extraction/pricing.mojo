# Native Mojo price-string normalization. No Python interop here.
#
# Scanning is done over raw UTF-8 bytes (`as_bytes()`/integer comparisons)
# rather than single-byte String slices, so a currency symbol or accented
# character sitting next to the digits (both common in real listings) can
# never land us on an invalid UTF-8 codepoint boundary.

comptime ASCII_ZERO = 48
comptime ASCII_NINE = 57
comptime ASCII_DOT = 46
comptime ASCII_COMMA = 44
comptime ASCII_SPACE = 32


struct ParsedPrice(Copyable, Movable):
    var price: Optional[Float64]
    var currency: String

    def __init__(out self, price: Optional[Float64], currency: String):
        self.price = price
        self.currency = currency


def parse_price(raw: String) -> ParsedPrice:
    """Normalize a price string like "£51.77", "$1,299.00" or "12.50 EUR"
    into a numeric value plus whatever currency marker (symbol or code) sits
    next to it. Returns price=None when no digits are found."""
    var text = String(raw.strip())
    var data = text.as_bytes()
    var n = text.byte_length()

    var first_digit = -1
    var i = 0
    while i < n:
        var b = Int(data[i])
        if b >= ASCII_ZERO and b <= ASCII_NINE:
            first_digit = i
            break
        i += 1

    if first_digit == -1:
        return ParsedPrice(None, String(""))

    var currency = String(text[byte = 0 : first_digit].strip())

    var digits = String("")
    var seen_dot = False
    var pos = first_digit
    while pos < n:
        var b = Int(data[pos])
        if b >= ASCII_ZERO and b <= ASCII_NINE:
            digits += chr(b)
        elif b == ASCII_DOT and not seen_dot:
            digits += "."
            seen_dot = True
        elif b == ASCII_COMMA:
            pass  # thousands separator
        else:
            break
        pos += 1
    var consumed_end = pos

    if currency.byte_length() == 0:
        # Look for a trailing currency code, e.g. "12.50 EUR". Only trust it
        # when it's separated by whitespace, so we never need to slice
        # directly against whatever (possibly multi-byte) byte follows the
        # digits.
        var space_idx = text.find(" ", consumed_end)
        if space_idx != -1:
            var rest = String(text[byte = space_idx + 1 : n].strip())
            if rest.byte_length() > 0:
                currency = rest

    var value: Optional[Float64] = None
    try:
        value = Float64(digits)
    except e:
        pass

    return ParsedPrice(value, currency)
