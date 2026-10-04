# I Hate Perfume app

Native Flutter app (Android first, iOS later) for ihateperfume.com: scan a barcode or photograph an ingredient
list, see scent ingredients, fragrance allergens, and other flags with their sources, and find fragrance-free
products that have no ingredient list. Website repo: ~/Documents/ihateperfume (leakydata/ihateperfume); its
CLAUDE.md holds the evidence, voice, spelling, and serial-comma rules, and they apply here too.

## Non-negotiables (agreed with the owner)
- Not about money: no ads, no analytics or tracking SDKs, no paid tiers, no required account. Ever.
- Everything that can run on the phone does (barcode, text recognition, matching). Photos leave the phone only
  when the user submits a missing product; strip location data first.
- Never say a product is "safe". Every flag names its source. Never state or imply fragrance causes autism.
- A real native app, not a website in a wrapper (the owner dislikes those).
- License GPL-3.0 + ADDITIONAL-TERMS.md (credit ihateperfume.com, modified versions renamed). Repo private for
  now; plan to make it public for volunteers once a first version works.
- New store products/features: the owner approves on their own phone first.

## Design
`design/mockups.png` (source `design/mockups.html`) is THE design guide: website palette (ink #111111,
signal #C4361B, signal-dark #9E2A14, signal-light #FF8A6E, label #F3F1EC, paper #FFFFFF), Archivo condensed caps
for headlines, IBM Plex Mono for labels (fonts in design/fonts). Screens: home, scanner (barcode | ingredient
list), result, ingredient, not-found contribute, fragrance-free finds. Icon: red scan corners + crossed-out
bottle. Name: "I Hate Perfume" (store title "I Hate Perfume: Fragrance Scanner"); "Unmasked" rejected (an
autism/ADHD app uses it). Tagline "Scan it. Unmask it." The owner also wants a small "IHP" mark for tiny icons.

## Engine
- `lib/engine/decoder.dart` is a port of the website decoder (assets/decoder.js + decoder-flags.js in the
  website repo). Keep them identical: `flutter test test/decoder_parity_test.dart` compares against the live
  site's results (`test/parity/site_results.json`; regenerate with `node test/parity/site_results.js`, which
  needs Playwright, e.g. run from a folder where `require('playwright')` resolves).
- Data: `python3 tool/fetch_data.py` copies decoder.json, decoder-data.json, inci-vocab.json from the live site
  into assets/data. Later the app refreshes them from the site (no store release needed for data).
- Barcodes: Open Beauty Facts / Open Products Facts (US coverage is thin: ~2.3k cosmetics and ~230 household
  products with ingredient lists), then photograph the list, then our moderated submissions.

## Tooling
- Flutter: ~/development/flutter/bin/flutter (not on PATH). JDK 21 configured (system Java 25 is too new).
- Android SDK ~/Android/Sdk. The owner's Pixel 10 Pro XL is on adb (USB debugging): install test builds there.
- Google Play account: the owner creates it ($25); 12 testers x 14 days closed test (Discord). Apple later.
