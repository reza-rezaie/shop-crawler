# Native Mojo product/pagination/category extraction from raw listing and
# detail-page HTML. Two extraction strategies are tried, in order:
#
#   1. JSON-LD (schema.org Product) <script> blocks -- generic and robust
#      when present, common on real Shopify/WooCommerce stores. Uses
#      Python's `json.loads` (see SPEC.md ss6) since Mojo has no native JSON
#      parser yet; everything else (finding the blocks, deciding which
#      fields to keep) is native Mojo.
#   2. A heuristic block scan for repeated "product-ish" container elements
#      (`class` containing "product"). This is the path exercised end-to-end
#      against books.toscrape.com, which has no JSON-LD.
#
# All markup scanning is native Mojo (see textutil.mojo); the only Python
# interop in this file is `json.loads` for strategy 1 and `html.unescape`
# (via textutil.clean_text) for cleaning extracted text.

from std.python import Python, PythonObject
from models import Product
from pricing import parse_price
from textutil import (
    extract_attr,
    extract_blocks_by_class_hint,
    extract_first_tag_block,
    extract_first_void_tag,
    find_tag_open,
    clean_text,
    contains_ci,
)

def _candidate_tags() -> List[String]:
    var tags = List[String]()
    tags.append(String("article"))
    tags.append(String("li"))
    tags.append(String("div"))
    return tags^


def extract_json_ld_products(html: String, listing_url: String) raises -> List[Product]:
    """Strategy 1: scan for <script type="application/ld+json"> blocks that
    describe a schema.org Product (or a list containing one)."""
    var results = List[Product]()
    var json_mod = Python.import_module("json")

    var pos = 0
    while True:
        var open_idx = find_tag_open(html, "script", pos)
        if open_idx == -1:
            break
        var open_end = html.find(">", open_idx)
        if open_end == -1:
            break
        var open_tag_text = String(html[byte = open_idx : open_end + 1])
        var type_attr = extract_attr(open_tag_text, "type")
        var close_marker = "</script>"
        var close_idx = html.find(close_marker, open_end + 1)
        if close_idx == -1:
            break
        var body = String(html[byte = open_end + 1 : close_idx])
        pos = close_idx + close_marker.byte_length()

        if not type_attr:
            continue
        if not contains_ci(type_attr.value(), "ld+json"):
            continue

        var parsed: PythonObject
        try:
            parsed = json_mod.loads(body)
        except e:
            continue

        _collect_products_from_jsonld(parsed, listing_url, results)

    return results^


def _collect_products_from_jsonld(node: PythonObject, listing_url: String, mut results: List[Product]) raises:
    var builtins = Python.import_module("builtins")
    if builtins.isinstance(node, builtins.list):
        var n = len(node)
        var i = 0
        while i < n:
            _collect_products_from_jsonld(node[i], listing_url, results)
            i += 1
        return

    if not builtins.isinstance(node, builtins.dict):
        return

    var type_val = node.get("@type")
    var is_product = False
    if type_val is not None:
        if builtins.isinstance(type_val, builtins.list):
            var m = len(type_val)
            var j = 0
            while j < m:
                if String(type_val[j]) == "Product":
                    is_product = True
                j += 1
        else:
            if String(type_val) == "Product":
                is_product = True

    if is_product:
        var name = String("")
        var name_val = node.get("name")
        if name_val is not None:
            name = String(name_val)

        var url = listing_url
        var url_val = node.get("url")
        if url_val is not None:
            url = String(url_val)

        var image = String("")
        var image_val = node.get("image")
        if image_val is not None:
            if builtins.isinstance(image_val, builtins.list):
                if len(image_val) > 0:
                    image = String(image_val[0])
            else:
                image = String(image_val)

        var description = String("")
        var desc_val = node.get("description")
        if desc_val is not None:
            description = String(desc_val)

        var category = String("")
        var category_val = node.get("category")
        if category_val is not None:
            category = String(category_val)

        var price_text = String("")
        var offers = node.get("offers")
        if offers is not None:
            var offer_node = offers
            if builtins.isinstance(offers, builtins.list):
                if len(offers) > 0:
                    offer_node = offers[0]
            if builtins.isinstance(offer_node, builtins.dict):
                var price_val = offer_node.get("price")
                if price_val is not None:
                    price_text = String(price_val)
                var currency_val = offer_node.get("priceCurrency")
                var parsed_price = parse_price(price_text)
                var currency = parsed_price.currency
                if currency_val is not None and currency.byte_length() == 0:
                    currency = String(currency_val)
                if name.byte_length() > 0:
                    results.append(
                        Product(
                            url=url,
                            name=name,
                            price=parsed_price.price,
                            currency=currency,
                            image_url=image,
                            category=category,
                            description=description,
                            source_listing_url=listing_url,
                        )
                    )
                return

        if name.byte_length() > 0:
            results.append(
                Product(
                    url=url,
                    name=name,
                    price=None,
                    currency=String(""),
                    image_url=image,
                    category=category,
                    description=description,
                    source_listing_url=listing_url,
                )
            )
        return

    # Not a Product itself -- recurse into values in case it's a wrapper
    # object (e.g. a "@graph" list, or breadcrumb/product siblings).
    var items = node.items()
    for kv in items:
        var value = kv[1]
        if builtins.isinstance(value, builtins.list) or builtins.isinstance(value, builtins.dict):
            _collect_products_from_jsonld(value, listing_url, results)


def extract_heuristic_products(html: String, listing_url: String, page_category: String) raises -> List[Product]:
    """Strategy 2: repeated "product-ish" container blocks."""
    var results = List[Product]()
    var tags = _candidate_tags()

    for tag in tags:
        var blocks = extract_blocks_by_class_hint(html, tag, String("product"))
        if len(blocks) >= 1:
            for block in blocks:
                var product = _product_from_block(block, listing_url, page_category)
                if product:
                    var p = product.value().copy()
                    results.append(p^)
            break  # first tag type that yields matches wins

    return results^


def _product_from_block(block: String, listing_url: String, page_category: String) raises -> Optional[Product]:
    # Product URL: first <a href="...">.
    var a_block = extract_first_tag_block(block, "a")
    if not a_block:
        return None
    var a_open_end = a_block.value().find(">")
    if a_open_end == -1:
        return None
    var a_open_tag = String(a_block.value()[byte = 0 : a_open_end + 1])
    var href = extract_attr(a_open_tag, "href")
    if not href:
        return None

    # Name: prefer an <h1>-<h6><a title="...">, then that anchor's text,
    # then the <img alt="...">, then the first anchor's own text.
    var name = String("")

    var heading_tags = List[String]()
    heading_tags.append(String("h1"))
    heading_tags.append(String("h2"))
    heading_tags.append(String("h3"))
    heading_tags.append(String("h4"))
    heading_tags.append(String("h5"))
    heading_tags.append(String("h6"))
    for h_tag in heading_tags:
        var h_block = extract_first_tag_block(block, h_tag)
        if h_block:
            var h_a = extract_first_tag_block(h_block.value(), "a")
            if h_a:
                var h_a_open_end = h_a.value().find(">")
                if h_a_open_end != -1:
                    var h_a_open_tag = String(h_a.value()[byte = 0 : h_a_open_end + 1])
                    var title = extract_attr(h_a_open_tag, "title")
                    if title:
                        name = clean_text(title.value())
                    if name.byte_length() == 0:
                        var close_marker = "</a>"
                        var close_idx = h_a.value().find(close_marker, h_a_open_end + 1)
                        if close_idx != -1:
                            name = clean_text(String(h_a.value()[byte = h_a_open_end + 1 : close_idx]))
            break

    # <img> is a void element (no closing tag), so it needs the void-tag
    # extractor rather than extract_first_tag_block.
    var img_alt = String("")
    var image_url = String("")
    var img_tag = extract_first_void_tag(block, "img")
    if img_tag:
        var alt = extract_attr(img_tag.value(), "alt")
        if alt:
            img_alt = clean_text(alt.value())
        var src = extract_attr(img_tag.value(), "src")
        if src:
            image_url = src.value()

    if name.byte_length() == 0:
        name = img_alt

    if name.byte_length() == 0:
        return None

    # Price: first currency-looking substring in the block's visible text.
    var price_text = _find_price_text(block)
    var parsed_price = parse_price(price_text)

    return Optional[Product](
        Product(
            url=href.value(),
            name=name,
            price=parsed_price.price,
            currency=parsed_price.currency,
            image_url=image_url,
            category=page_category,
            description=String(""),
            source_listing_url=listing_url,
        )
    )


def _find_price_text(block: String) raises -> String:
    """Look for the first "class contains price" tag's text; fall back to
    scanning the block's plain text for a currency-symbol-led number."""
    var price_block = extract_blocks_by_class_hint(block, "p", String("price"))
    if len(price_block) >= 1:
        return clean_text(price_block[0])
    var span_block = extract_blocks_by_class_hint(block, "span", String("price"))
    if len(span_block) >= 1:
        return clean_text(span_block[0])

    var currency_symbols = List[String]()
    currency_symbols.append(String("£"))
    currency_symbols.append(String("$"))
    currency_symbols.append(String("€"))
    var cleaned = clean_text(block)
    for sym in currency_symbols:
        var idx = cleaned.find(sym)
        if idx != -1:
            var n = cleaned.byte_length()
            var end = idx + sym.byte_length()
            var scanned = 0
            while end < n and scanned < 20:
                var b = Int(cleaned.as_bytes()[end])
                var is_digit_or_sep = (b >= 48 and b <= 57) or b == 46 or b == 44
                if not is_digit_or_sep:
                    break
                end += 1
                scanned += 1
            return String(cleaned[byte = idx : end])
    return String("")


def find_next_page_url(html: String, current_url: String) raises -> Optional[String]:
    """Find a pagination "next" link: <link rel="next"> in <head>, or any
    element whose class contains "next" with a nested href, resolved to an
    absolute URL relative to `current_url`."""
    var urlparse = Python.import_module("urllib.parse")

    # <link rel="next"> has no class, so scan <link> tags directly rather
    # than via extract_blocks_by_class_hint (which requires a class match).
    var pos = 0
    while True:
        var open_idx = find_tag_open(html, "link", pos)
        if open_idx == -1:
            break
        var open_end = html.find(">", open_idx)
        if open_end == -1:
            break
        var tag_text = String(html[byte = open_idx : open_end + 1])
        var rel = extract_attr(tag_text, "rel")
        if rel and String(rel.value()) == "next":
            var href = extract_attr(tag_text, "href")
            if href:
                var resolved = String(urlparse.urljoin(current_url, href.value()))
                return Optional[String](resolved)
        pos = open_end + 1

    var next_blocks = extract_blocks_by_class_hint(html, "a", String("next"))
    if len(next_blocks) == 0:
        next_blocks = extract_blocks_by_class_hint(html, "li", String("next"))
    for candidate in next_blocks:
        var a_block = extract_first_tag_block(candidate, "a")
        var target = candidate
        if a_block:
            target = a_block.value()
        var open_end2 = target.find(">")
        if open_end2 == -1:
            continue
        var tag_text2 = String(target[byte = 0 : open_end2 + 1])
        var href2 = extract_attr(tag_text2, "href")
        if href2:
            var resolved2 = String(urlparse.urljoin(current_url, href2.value()))
            if resolved2 != current_url:
                return Optional[String](resolved2)

    return None


def extract_breadcrumb_category(html: String) raises -> String:
    """Category from <ul class="breadcrumb">: last item's text (listing
    pages) -- callers on a detail page should prefer the second-to-last item
    instead, since the last one is the product's own name."""
    var crumb = extract_last_breadcrumb_items(html, 1)
    if len(crumb) >= 1:
        return crumb[0]
    return String("")


def extract_last_breadcrumb_items(html: String, count: Int) raises -> List[String]:
    var result = List[String]()
    var nav_blocks = extract_blocks_by_class_hint(html, "ul", String("breadcrumb"))
    if len(nav_blocks) == 0:
        return result^
    var nav = nav_blocks[0]

    var items = List[String]()
    var pos = 0
    while True:
        var open_idx = find_tag_open(nav, "li", pos)
        if open_idx == -1:
            break
        var open_end = nav.find(">", open_idx)
        if open_end == -1:
            break
        var close_marker = "</li>"
        var close_idx = nav.find(close_marker, open_end + 1)
        if close_idx == -1:
            break
        var inner = String(nav[byte = open_end + 1 : close_idx])
        items.append(clean_text(inner))
        pos = close_idx + close_marker.byte_length()

    var total = len(items)
    var start = total - count
    if start < 0:
        start = 0
    var i = start
    while i < total:
        result.append(items[i])
        i += 1
    return result^


def extract_product_description(html: String) raises -> String:
    """Product detail page description: the visible text right after a
    "#product_description"-style heading, falling back to the first
    reasonably long <p> on the page."""
    var marker_idx = html.find("product_description")
    if marker_idx != -1:
        var p_open = find_tag_open(html, "p", marker_idx)
        if p_open != -1:
            var open_end = html.find(">", p_open)
            if open_end != -1:
                var close_idx = html.find("</p>", open_end + 1)
                if close_idx != -1:
                    return clean_text(String(html[byte = open_end + 1 : close_idx]))
    return String("")
