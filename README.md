# I Hate Perfume (Android app)

Native Android app (Flutter, so iOS can follow) for finding fragrance in products: scan a barcode or photograph
the ingredient list, see which ingredients are scent ingredients or fragrance allergens and why, and find
fragrance-free products that have no ingredient list at all (trash bags, laundry, paper goods).

Companion to [ihateperfume.com](https://ihateperfume.com) (repo: leakydata/ihateperfume), which publishes the
ingredient data and reviews submitted products.

## Promises
- No account, no ads, no tracking. Free.
- Barcode reading, text recognition, and ingredient matching run on the phone. Photos leave the phone only when
  the user chooses to submit a missing product, with location data stripped.
- Every flag names its source. The app never says a product is "safe".
- Never state or imply that fragrance causes autism.

## What it does (first version)
- **Scan a barcode** (ML Kit, on the phone): the number is looked up in Open Beauty Facts, then Open Products
  Facts. If there's no ingredient list, it goes straight to photographing one.
- **Photograph the ingredients** (ML Kit text recognition, on the phone), or type/paste them. The text it read is
  shown for checking: it lists only the items it didn't recognize, with a suggested fix for misreads ("SODUM
  HYDROKDE" → Sodium Hydroxide), Edit for the rest, and Remove for label text such as addresses.
- **Results**: scent ingredients, fragrance allergens, and other flags, each with its source; links to the
  ingredient's page on ihateperfume.com; what the check can't see.
- **My list**: ingredients, groups, or words the user is allergic to, irritated by, or wants to know about,
  flagged first on every result (including "could be inside Fragrance").
- **Search** any ingredient name; **recent scans** on the phone only; **Learn** with the promises, data sources,
  terms, and privacy policy (drafts, `TERMS.md` and `PRIVACY.md`).

## Design
`design/mockups.png` (source `design/mockups.html`) is the design guide: the website's palette
(ink #111111, signal #C4361B, label #F3F1EC, paper #FFFFFF), Archivo condensed caps for headlines,
IBM Plex Mono for labels.

## Data
- Ingredient matching: the website label decoder's dataset (`decoder-data.json`, about 140 KB compressed), bundled
  for offline use and refreshed from ihateperfume.com.
- Barcodes: Open Beauty Facts and Open Products Facts (ODbL, credit required), then our own reviewed submissions.

## License
GPL-3.0 with the additional terms in `ADDITIONAL-TERMS.md`: keep the credit to ihateperfume.com, mark modified
versions, and don't use the I Hate Perfume name or logos for them.
