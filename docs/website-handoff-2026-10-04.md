# Scanner improvements in the app (2026-10-03/04), for the website's label decoder

The app (`~/Documents/ihateperfume-app`, Flutter) and the website's label decoder (`/label-decoder/`:
`ihp-evidence/assets/decoder.js`, `decoder-flags.js`, `scan.js`, `barcode.js`) share the decoder logic. These are the
scanner improvements made in the app, what's already on the site, and what the site could adopt. Everything was
tested on real phone scans; the evidence and privacy rules in both CLAUDE.md files apply unchanged.

## Already on the website (no action)
- **Allergen lookalikes:** `research/claims/allergen-lookalikes.json` + decoder.js 0.7.3 (Ethyl Linalool isn't
  Linalool). The app's port is identical (parity test case 12).
- **ihp-app plugin (REST `ihp-app/v1`):** submissions with photos, our reviewed products (`/products/{barcode}`,
  `/products.json`), finds, data updates (`/data`, `/decoder.json`), the opt-in wanted list (`/wanted`), reports
  (`/reports`), and the wp-admin review screen (Pending, Products and finds, Most wanted, Reports, Walmart check
  (off), Send to Open Beauty Facts). Contract: `~/Documents/ihateperfume-app/docs/app-api.md`.
  PHP accessors for site pages: `ihp_app_finds(): array`, `ihp_app_product(string $barcode): ?array`.

## Could come to the website decoder (each is self-contained)
1. **Our reviewed products first.** The app checks our own reviewed list before Open Beauty Facts and Open Products
   Facts, because volunteer entries can be wrong (real case: Crest Pro-Health mouthwash 037000811244 on Open Products
   Facts holds only the Drug Facts text, no inactive ingredients). barcode.js could call `ihp_app_product()` data
   first (e.g. inline the small `/products.json`, or query `/products/{barcode}` from the same origin, which sends the
   barcode only to us). App: `lib/services.dart` `lookUp`, `lib/data_update.dart` `localProduct`.
2. **openFDA as a third barcode source** (over-the-counter drugs: sunscreen, antiperspirant, acne wash). By UPC:
   `api.fda.gov/drug/label.json?search=openfda.upc:"<13-digit>"`; fallback for UPC-A starting with 3: the NDC
   inside it (4-4-2 / 5-3-2 / 5-4-1) via `drug/ndc.json` then `drug/label.json?search=openfda.product_ndc:`. Combine
   active ingredient names + `inactive_ingredient`. CC0, no key. App: `lib/services.dart` (`fdaUpc`, FDA parsing),
   tests `test/fda_test.dart` with recorded fixtures.
3. **"Report this list"** on barcode results: reasons not_ingredients / wrong_product / missing / other, POST
   `/wp-json/ihp-app/v1/reports` (barcode, source, reason; no free text, no email). Reports show in wp-admin.
   App: `lib/list_report.dart`, `lib/screens/report_list.dart`.
4. **"Ask us to find it"** when a barcode isn't found anywhere: opt-in, sends only the barcode to
   `/wp-json/ihp-app/v1/wanted`; feeds the Most wanted tab. App: `lib/wanted.dart`.
5. **Photo-scan cleanup before decoding** (scan.js OCR text): start at the list heading even when misread
   ("IMGREDIENTS:", "INGREDlENTS", "1NGREDIENTS"), rejoin words broken across lines ("Methylisothia-/zolinone"), and
   cut the footer even without a period ("Distributed by", "Made in", "Dist. by", US address/zip, phone, URL,
   8+ digit runs). App: `cleanOcr` in `lib/services.dart`; tests in `test/report_test.dart` and the real-scan
   fixtures `test/fixtures/ocr-cetaphil-body-wash*.txt`.
6. **"Items to check" panel after a photo scan** (the biggest UX win on phones): instead of silently decoding OCR
   text, list only the items that didn't match a known ingredient name, in three groups:
   - **Probably misread** → one-tap fix (OCR-aware edit distance over the ~33k INCI names: 0/O, 1/l/I, rn↔m, cl↔d,
     5/S, missing spaces; never guesses when two different ingredients are equally close, e.g. "Sodium Octrate" is
     as close to citrate as nitrate). Also splits two names joined by a missing comma
     ("Lauryl Lactate Acrylates/C10-30 …").
   - **Not recognized** → "Edit" selects the text so the user retypes it.
   - **Looks like other label text** (addresses, lot numbers, directions, "Distributed by…") → "Remove".
   Nothing changes until the user taps. App: `lib/engine/ocr_fix.dart` (pure Dart, ~600 lines, port to JS would be
   needed), UI `lib/screens/review.dart`, tests `test/ocr_fix_test.dart` (incl. two real Cetaphil scans). It never
   changes the decoder's own matching, so site/app parity is unaffected.
7. **Maker's ingredient page link** for barcode results (opened only on click, never fetched): P&G GS1 prefixes →
   `smartlabel.pg.com/en-us/<GTIN-14>.html`; any other barcode → `smartlabel.org/product-search/?product=<barcode>`.
   App: `makerPage` in `lib/services.dart`.

## Not adopted on purpose
- **Guessing whether a database entry is a real ingredient list** (e.g. Drug Facts text): tried and reverted at the
  owner's request. Reports plus our reviewed products handle it instead.
- **Walmart / Amazon / Yuka data:** not used (terms forbid storing or showing it). Walmart's API is only a planned,
  reviewer-only photo check in wp-admin, off until its API terms are read.

## Privacy reminders for any of the above on the site
Update `/privacy/` (research/claims/privacy-page.html) before shipping anything that sends new data, and show the
owner the text first, as was done for the app (`/app-privacy/`, page 344).
