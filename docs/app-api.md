# App ↔ ihateperfume.com API (contract)

The website side lives in a new WordPress plugin, `ihp-app` (website repo:
`site/wp-content/plugins/ihp-app/`), deployed by `deploy-theme.sh`. The app side calls it from
`lib/services.dart`. Both sides build against this file; change it first if the contract changes.

Base: `https://ihateperfume.com/wp-json/ihp-app/v1`

Privacy rules (non-negotiable, see CLAUDE.md):
- No accounts, no cookies, no device IDs, no analytics. Requests carry only what each endpoint lists.
- Photos leave the phone only through `POST /submissions`, only when the user taps Send, with all metadata
  (EXIF, including location) removed on the phone first.
- The server never stores IP addresses. Rate limiting uses a salted hash of the IP that rotates daily and is
  discarded after 48 hours.

## `GET /data`
What the app needs to keep its ingredient data current without a store release. Cacheable (1 hour).
```json
{
  "v": "2026-09-27",                       // decoder-data.json "v"
  "files": {
    "decoder.json":      {"url": "…", "sha256": "…", "bytes": 19570},
    "decoder-data.json": {"url": "…", "sha256": "…", "bytes": 893370},
    "inci-vocab.json":   {"url": "…", "sha256": "…", "bytes": 966546}
  },
  "finds": {"url": "…/finds", "updated": "2026-10-04T12:00:00Z"}
}
```
`decoder.json` is the same object `tool/fetch_data.py` builds today:
`{"allergens": [...], "caution": "...", "lookalikes": [...], "pages": {...}}` (served at
`GET /decoder.json`, generated from the same PHP the label decoder uses, so the two can't drift).
The app downloads a file only when its sha256 differs from what it has, verifies the sha256, parses it,
and only then swaps it in (falls back to the bundled copy on any error).

## `GET /products/{barcode}`
Our own reviewed products (after Open Beauty Facts, Open Products Facts, and openFDA miss).
`barcode`: 8–14 digits. 404 when unknown. 200:
```json
{"barcode": "0123456789012", "name": "Brand Product", "ingredients": "Water, …" | null,
 "no_list": false, "says": "fragrance-free" | "unscented" | "no scent listed" | "scented" | null,
 "checked": "2026-10", "evidence": "package photo" | "maker site"}
```
`ingredients` is null for products with no ingredient list (then `no_list` is true).

## `GET /finds`
Fragrance-free finds: reviewed products that have no ingredient list (trash bags, laundry, paper, cleaning).
```json
{"updated": "2026-10-04T12:00:00Z",
 "categories": ["Trash bags", "Laundry", "Cleaning", "Paper"],
 "items": [{"name": "…", "brand": "…", "category": "Trash bags",
            "says": "unscented" | "fragrance-free" | "no scent listed" | "scented",
            "note": "Says “fresh scent” on the box" | null,
            "checked": "2026-10", "evidence": "package photo" | "maker site", "barcode": "…" | null}]}
```
Only reviewed entries appear. Never "safe"; "scented" entries are listed too, as warnings.

## `POST /submissions`
`multipart/form-data`. No account. Fields:
- `barcode` (optional, 8–14 digits)
- `name` (optional, ≤ 120 chars)
- `says_fragrance_free`, `says_unscented`, `no_list` (each "0" or "1": the "The package says" checkboxes)
- `category` (optional, one of the finds categories, or "Other")
- `front` (JPEG, required: the front of the package)
- `ingredients` (JPEG, required unless `no_list` = "1": the ingredient list), plus optional `ingredients_2` and
  `ingredients_3` when the list wraps around a bottle (order matters: they're read left to right)
- `extra_1`, `extra_2`, `extra_3` (JPEG, optional: back, sides, bottom, or anything else that shows a claim such as
  "scented" or "unscented", or the barcode)
- Every photo: ≤ 2.5 MB, longest side ≤ 2000 px, metadata stripped on the phone. At most 7 photos; separate field
  names (no arrays). A whole request is at most 18 MB.
- `app` (e.g. "1.0.0+1")

Responses: `201 {"ok": true, "ref": "S-7F3K2"}` (a short reference the user can quote),
`400 {"ok": false, "error": "…"}` (plain-English message the app can show, naming the photo that failed),
`429` when over the limit (10 submissions per IP hash per day), `413` when too big.

Server side: the photo bytes are re-checked (real JPEG, size limits) and metadata is stripped again;
files go to a private folder that isn't web-readable; each submission becomes a pending item in a
WP-admin review screen, where a moderator reads the photos, types or corrects the ingredient list,
fills in name/brand/says/category, and approves (→ `/products/{barcode}` and, for no-list products,
`/finds`) or rejects (photos deleted). Approved photos are kept only as long as needed for review
and then deleted; nothing personal is ever published.

## `POST /wanted` (opt-in "Ask us to find it")
Sent only when the user tapped "Ask us to find it", or chose "Send missing barcodes automatically" in the one-time
sheet (off unless they say yes; changeable in Learn). `application/x-www-form-urlencoded`: `barcode` (8–14 digits),
`app`. Nothing else. `202 {"ok": true}` (also when the barcode was already wanted), `400` bad barcode, `429` over the
limit (50 per IP hash per day, same daily-salted HMAC as submissions; IPs never stored).
Server keeps per barcode: count, first asked, last asked (dates only). When a product with that barcode is approved,
its wanted entry is removed. A 12-digit UPC-A and its 13-digit form count as one.

The app keeps the barcodes the user asked about in a private list on the phone (max 100, oldest dropped). At most once
a day, after start, it re-checks them with `GET /products/{barcode}` (one request per barcode, max 20 per day,
same User-Agent, nothing else) and, if any were added, shows "We found N products you asked about." Found or
older-than-180-days barcodes leave the list.

## Admin only (no public endpoints)
- **Most wanted** tab: wanted barcodes by count (then last asked), with "Add it" (pre-filled product form) and
  "Check Walmart's photos".
- **Check Walmart's photos** (also on each pending submission with a barcode): the server signs a Walmart affiliate
  API lookup with the key in a file outside the web root (path and consumer ID set in wp-config.php:
  `IHP_APP_WALMART_KEY_FILE`, `IHP_APP_WALMART_CONSUMER_ID`, `IHP_APP_WALMART_KEY_VERSION`) and shows Walmart's
  product name and photos to the reviewer. Nothing from Walmart is stored or cached, and nothing reaches the app.
  Disabled when the constants aren't set.
- **Send to Open Beauty Facts** on approved products: posts the factual fields (barcode, product name, brand,
  ingredient list) to Open Beauty Facts' write API under the project's account. Disabled until
  `IHP_APP_OBF_USER` / `IHP_APP_OBF_PASSWORD` are set in wp-config.php. Never sends user photos.

## Our reviewed products come first (checked on the phone)
`GET /data` gains `"products": {"url": "…/products.json", "sha256": "…", "bytes": N}`. `GET /products.json` returns
`{"updated": "…", "items": [<same objects as GET /products/{barcode}>]}` for every approved product with a barcode,
compact JSON, cacheable 1 hour. The app downloads it with its data update (only when the sha256 changes) and checks
it **on the phone first**, before Open Beauty Facts, Open Products Facts, and openFDA, so a reviewed product never
sends its barcode anywhere. `GET /products/{barcode}` stays as the last fallback (products approved since the
phone's last update).

## `POST /reports` ("Wrong or missing ingredients? Report it")
Sent only when the user taps "Just report" in the report sheet. `application/x-www-form-urlencoded`: `barcode`
(8–14 digits), `source` (`obf` | `opf` | `fda` | `ihp`), `reason` (`not_ingredients` | `wrong_product` |
`missing` | `other`), `app`. Nothing else. `202 {"ok": true}`, `400`, `429` (50 per IP hash per day; same daily-salted
HMAC; IPs never stored). Server keeps per (barcode, source): counts per reason, first and last date. Saving our own
product for that barcode clears its reports. The sheet's other choice, "Add photos (fastest fix)", opens the normal
"Add it" flow with the barcode filled in.

Admin: a **Reports** tab grouped by barcode and source, most reported first: reasons with counts, dates, a link to the
entry at its source (Open Beauty Facts / Open Products Facts product page, or the openFDA query), "Add the correct
list" (pre-filled product form), "Check Walmart's photos", and "Dismiss".
