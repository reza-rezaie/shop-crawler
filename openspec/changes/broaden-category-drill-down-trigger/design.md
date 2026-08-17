## Context

See `proposal.md` - Why. This is a narrow, single-file follow-up to the
previous change's own `crawler.mojo` trigger condition, discovered by
running that change's own feature against the corrected top-level URL for
the reported bug. No new module, dependency, or data model change.

## Goals / Non-Goals

**Goals:** make a page's own products and its subcategory links both get
picked up, instead of being mutually exclusive.

**Non-Goals:** anything about the per-page child-link cap, the overall
page budget, or the not-found check — all unchanged from the previous
change; this only widens *when* `find_child_links` gets called.

## Decisions

**Trigger unconditionally (once a page isn't a 404), not "only when
zero products."** `crawler.mojo`'s per-page branch already separately
handles "this page had products" (store them, follow pagination) and
"this page had none" (note, look for children). Moving the
`find_child_links` call out of the "had none" branch so it runs either
way is the entire change — no new function, no new parameter. Alternative
considered: a caller-supplied flag ("always drill down" vs "only on empty
pages") — rejected as unnecessary API surface for a POC; always looking
is strictly more useful (a genuine leaf page just finds zero children, at
the cost of one extra harmless string scan) and matches what "crawl
everything under this page" means in the first place.

## Found during verification

Broadening the trigger surfaced a real, pre-existing bug in
`is_child_path` (added by the previous change, never triggered until
now): the site root's path stem is `/` itself — a prefix of every path
on the site — so any link on a homepage was misread as a "child" page.
Harmless before this change (drill-down only ran on zero-product pages,
and a homepage always has products, so the buggy path was never
exercised); a real regression once drill-down became unconditional
(confirmed live: `books.toscrape.com` dropped from 60 to 40 products at
`max_pages=3`, its budget consumed fetching individual book/product links
as if they were subcategories). Fixed by making `is_child_path` refuse to
treat the root (`/`) as having children at all — there's no meaningful
"nested under the root" relationship to detect, only "everything is
technically a substring match." Covered by new regression tests.

## Risks / Trade-offs

- [Every page now pays a `find_child_links` scan, even ones that were
  previously skipping it because they had products] → Purely a local
  string scan over already-fetched HTML, no extra network request; the
  cost that actually matters (page budget, rendering time) is unchanged.
- [A crawl aimed at a large, deep category tree can now expand much
  faster since every level contributes children, not just empty ones] →
  This is the explicit goal (reach more of the tree within a given
  budget); the overall page limit is still the only bound, unchanged from
  before, so a caller controls total cost the same way as always via
  `max_pages`.
