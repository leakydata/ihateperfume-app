#!/usr/bin/env python3
"""Copy the website label decoder's data into the app (assets/data/), exactly as ihateperfume.com serves it.

    python3 tool/fetch_data.py

- decoder.json: the fragrance part (EU allergen list with US spelling, the no-allergens caution) and the
  ingredient-page map, read from the live /label-decoder/ page's inline config.
- decoder-data.json: flags beyond fragrance (official lists + graded evidence).
- inci-vocab.json: ~33,000 real ingredient names for typo-tolerant matching.
The app ships these for offline use and later checks the site for newer versions.
"""
import json
import pathlib
import re
import urllib.request

SITE = "https://ihateperfume.com"
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets/data"
UA = {"User-Agent": "Mozilla/5.0 (ihateperfume-app data fetch)"}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read().decode()


def inline(page, name):
    m = re.search(r"window\." + name + r" = (\{.*?\});\s*\n?", page, re.S)
    if not m:
        raise SystemExit(f"{name} not found on /label-decoder/")
    return json.loads(m.group(1))


page = get(SITE + "/label-decoder/?app-fetch=1")
dec, flags = inline(page, "ihpDecoder"), inline(page, "ihpDecoderFlagsCfg")
OUT.mkdir(parents=True, exist_ok=True)
(OUT / "decoder.json").write_text(json.dumps({"allergens": dec["allergens"], "caution": dec["caution"],
                                              "lookalikes": dec.get("lookalikes", []),
                                              "pages": flags["pages"]}, ensure_ascii=False, separators=(",", ":")))
for name, key in (("decoder-data.json", "url"), ("inci-vocab.json", "vocab")):
    (OUT / name).write_text(get(flags[key]))
for f in sorted(OUT.glob("*.json")):
    print(f.name, f.stat().st_size)
