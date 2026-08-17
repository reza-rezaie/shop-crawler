## Context

See `proposal.md` - Why. Relevant existing structure (see repo `SPEC.md`):
extraction is native Mojo string scanning over raw HTML (`textutil.mojo`,
`html_extract.mojo`) with two strategies (JSON-LD, then a heuristic
"class contains a hint" block scanner); `crawler.mojo` orchestrates
fetch → extract → paginate → upsert; `db.mojo` already stores
`source_listing_url` per product but nothing reads it back out except as an
opaque field; the frontend product grid (`App.jsx`) never displays it.

Confirmed live against `https://www.azurestandard.com/shop/category/`: the
page is an AngularJS SPA (`<html ... ng-app="app">`) with zero `<article>`
tags, no JSON-LD, and the only `class` attribute containing the substring
"product" is a binding expression
(`class="{ 'Animate--heartPulse': product.favoriteProcessing }"`) - real
product data isn't in the fetched HTML at all. `extract_blocks_by_class_hint`'s
`contains_ci(class_value, "product")` check matches that substring, so the
element (an unrelated favorite/heart-icon widget) becomes a false-positive
product-card candidate.

Found while implementing the fix above: re-testing the fixed extractor
against a *live* crawl of the same URL still produced zero pages crawled,
because `can_fetch()` (`http_client.mojo`) reported the URL as disallowed
by robots.txt. Root cause: `RobotFileParser.read()` fetches `robots.txt`
via plain `urllib.request.urlopen()` with no way to set a User-Agent, and
azurestandard.com's edge returns `403` for that bare default UA (confirmed:
`curl` and a request using this crawler's own UA both get `robots.txt`
with `200`). `read()` maps a `403`/`401` response to `disallow_all = True`,
so the crawl was being blocked before extraction ever ran on the real page.

## Goals / Non-Goals

**Goals:**
- Stop framework binding expressions from being matched as product classes.
- Make a page that structurally can't be scraped (client-rendered, no
  product markup) fail loudly in the crawl result instead of silently.
- Make it possible to see, from the browse UI alone, which site any given
  stored product actually came from.

**Non-Goals:**
- Do not add JavaScript rendering (Playwright) to handle SPA sites like
  azurestandard.com in this change - detecting and reporting the
  limitation is in scope; working around it is not (matches repo `SPEC.md`:
  Playwright is reserved for when JS rendering is actually implemented).
- Do not change the SQLite schema - `source_listing_url` already exists;
  this change only reads/derives from it (a host) and exposes it.
- Do not rework the two-strategy extraction approach itself, only the
  matching predicate within the heuristic strategy and attribute lookup.

## Decisions

**robots.txt: fetch with our own UA, feed the text to `RobotFileParser.parse()`.**
`can_fetch()` now calls this project's own `fetch()` (our descriptive UA,
already used for every other request) to retrieve `robots.txt`, then passes
the response body's lines to `RobotFileParser.parse()` instead of calling
`RobotFileParser.read()`. `parse()` only interprets rule text; it does no
fetching itself, so there's no separate UA to get blocked. A fetch failure
(404, connection error, etc.) is treated as "no robots.txt" -> allowed,
same as the previous behavior's intent. Alternative considered: subclass or
monkeypatch `RobotFileParser`'s internal opener to inject a UA - rejected as
more Python-interop surface for no benefit over just doing the fetch
ourselves, which this project already has a function for.

**Class-hint matching: whitespace-tokenize + character-class validate,
done in Mojo, no new dependency.**
`extract_blocks_by_class_hint` (textutil.mojo) currently calls
`contains_ci(class_attr_value, hint)` against the raw attribute string.
Change it to split the attribute value on whitespace and check each token
individually, first validating the token contains only
`[A-Za-z0-9_-]` characters (real CSS class syntax) before substring-matching
the hint against it. Alternative considered: reject the whole element if the
attribute value contains characters invalid in CSS (`{`, `}`, `'`, `.`,
`:`) - rejected because some sites legitimately mix valid and templated
class tokens in one `class` value (e.g. `"product-card {{dynamicClass}}"`)
and per-token validation degrades more gracefully than an all-or-nothing
attribute check.

**Attribute-name boundary check in `extract_attr` (textutil.mojo).**
Require the character immediately before a matched `<name>="` to be absent
(start of string) or whitespace/`"`/`'` (end of a preceding attribute),
mirroring the boundary check `find_tag_open` already does for tag names.
This is a narrow, local fix with no new dependency.

**SPA-shell detection: static marker scan, in Mojo, over the already-fetched
HTML - no rendering, no new dependency.**
After both extraction strategies run and find zero products, scan the raw
HTML for a small fixed set of known app-shell markers
(`ng-app=`, `data-reactroot`, `id="root"`, `id="__next"`, `data-v-app`).
If any marker is present, attach a note to that page's contribution to the
crawl summary. This is a heuristic (a false positive just adds a note to a
legitimately-empty page; a false negative just means the older "0 products,
no explanation" behavior for that page) rather than a hard classification,
which fits a POC's cost/benefit better than a real content-based classifier.

**Source attribution: derive a display host from the already-stored
`source_listing_url`, don't add a new column.**
`db.mojo` already stores `source_listing_url` per product on every
upsert. Add a `source_host` computed at query time (via SQL
`substr`/`instr`, no new Python interop needed beyond what's already used)
so `GET /api/products` can both return it per item and accept an optional
`source_host` filter, without a schema migration.

**Frontend: extend the existing product grid rather than add a second
page/route.**
The existing grid already is "browse all products" mechanically; the gap
is attribution and a way to isolate one source. Add a source-site column to
each card and a source-site `<select>` filter next to the existing
category filter, populated from a new `GET /api/sources` endpoint
(mirrors the existing `GET /api/categories`). Alternative considered: a
separate "Browse" route/page - rejected as unnecessary complexity; the
grid already is the browse view, it just needs attribution surfaced.

## Risks / Trade-offs

- [Per-token class validation could still admit a pathological token that
  happens to be alphanumeric and contains "product" while not being a real
  class] → Accepted for this POC; the fix removes the concrete failure mode
  observed (punctuation-laden binding expressions), and heuristic scraping
  of arbitrary markup can never be 100% precise.
- [robots.txt fetched with our own UA could itself be blocked by a host
  that blocks *every* UA it doesn't recognize, not just urllib's default]
  → Falls back to "allowed" exactly like the unreachable case, matching
  standard robots.txt convention (missing/unreachable = allowed); no
  behavior change from before this fix in that scenario.
- [SPA-shell marker list is a fixed, incomplete set] → Documented as a
  heuristic in the spec (may under- or over-detect); acceptable because the
  fallback behavior (no note) is exactly today's behavior, so this only
  ever adds information, never removes existing capability.
- [Existing rows already in `data/products.db` from prior crawls of
  different sites won't retroactively gain a distinguishable source_host
  unless recomputed] → `source_host` is derived from the existing
  `source_listing_url` column at query time, not stored, so it is correct
  for all existing rows with no migration needed.

## Open Questions

None - all decisions above are resolved for this change.
