/// The label decoder, ported from ihateperfume.com (assets/decoder.js and assets/decoder-flags.js).
///
/// Everything runs on the phone. Keep the logic identical to the website: test/decoder_parity_test.dart
/// compares results against the live site's decoder.
library;

import 'dart:convert';

import 'package:diacritic/diacritic.dart';

/// A flag on one ingredient: [category, source key, detail, optional url].
class Flag {
  final String cat;
  final String src;
  final String detail;
  final String? url;
  const Flag(this.cat, this.src, this.detail, [this.url]);
  String get key => '$cat|$src|$detail|${url ?? ''}';
}

class Category {
  final String label;
  final String short;
  final String help;
  final int level;
  const Category(this.label, this.short, this.help, this.level);
}

class FragranceHit {
  final String item;
  final String label;
  const FragranceHit(this.item, this.label);
}

class AllergenHit {
  final String item;
  final String name;
  final String kind; // eu-original, eu-2023, eu-banned
  final String note;
  const AllergenHit(this.item, this.name, this.kind, this.note);
}

class FlagRow {
  final String item;
  final List<Flag> flags;
  final String? guess; // set when a misspelling was read as a known ingredient
  const FlagRow(this.item, this.flags, this.guess);
}

enum Verdict { red, amber, clear }

class Result {
  final List<String> items;
  final List<FragranceHit> fragrance;
  final List<AllergenHit> allergens;
  final List<String> plantOils;
  final List<FlagRow> rows;
  final Verdict verdict;
  final List<String> redShort; // short names of red-level categories found
  final List<String> amberShort;
  const Result(this.items, this.fragrance, this.allergens, this.plantOils, this.rows, this.verdict, this.redShort,
      this.amberShort);
  int get fragranceCount => fragrance.length + allergens.length + plantOils.length;
}

/// Product type: some EU rules depend on it. '' = not sure, 'leave', 'rinse', 'home'.
typedef ProductType = String;

class Decoder {
  final List<_Allergen> _allergens;
  final String caution;
  final Map<String, String> pages; // normalized name -> /ingredients/<slug>/
  final Map<String, Category> cats;
  final List<Map<String, dynamic>> _items;
  final Map<String, int> _names;
  final List<_Pattern> _patterns;
  final List<String> limits;
  final Map<String, Map<String, dynamic>> sources;
  final Map<String, String> facts;
  final Set<String> _vocabSet;
  final Map<int, List<String>> _byLen;

  Decoder._(this._allergens, this.caution, this.pages, this.cats, this._items, this._names, this._patterns, this.limits,
      this.sources, this.facts, this._vocabSet, this._byLen);

  /// Build from the three files in assets/data (decoder.json, decoder-data.json, inci-vocab.json).
  factory Decoder.fromJson(String decoderJson, String flagsJson, String vocabJson) {
    final dec = jsonDecode(decoderJson) as Map<String, dynamic>;
    final d = jsonDecode(flagsJson) as Map<String, dynamic>;
    final vocab = (jsonDecode(vocabJson) as List).cast<String>();
    final allergens = (dec['allergens'] as List).map((a) {
      final n = _normFragrance(a['name'] as String);
      final esc = RegExp.escape(n).replaceAll(RegExp(r'[\s-]+'), r'[\s-]*');
      return _Allergen(a['name'] as String, a['kind'] as String, (a['note'] ?? '') as String,
          RegExp('(^|[^a-z0-9])$esc(\$|[^a-z0-9])'));
    }).toList();
    final cats = <String, Category>{};
    (d['cats'] as Map<String, dynamic>).forEach((k, v) {
      cats[k] = Category(v['label'] ?? k, v['short'] ?? v['label'] ?? k, v['help'] ?? '', (v['level'] ?? 1) as int);
    });
    final byLen = <int, List<String>>{};
    for (final n in vocab) {
      (byLen[n.length] ??= []).add(n);
    }
    return Decoder._(
      allergens,
      (dec['caution'] ?? '') as String,
      Map<String, String>.from(dec['pages'] as Map),
      cats,
      (d['items'] as List).cast<Map<String, dynamic>>(),
      Map<String, int>.from(d['names'] as Map),
      (d['patterns'] as List)
          .map((p) => _Pattern(RegExp(p['re'] as String, caseSensitive: false), p['cat'] as String, p['src'] as String,
              p['detail'] as String, p['url'] as String?))
          .toList(),
      (d['limits'] as List).cast<String>(),
      (d['src'] as Map).cast<String, Map<String, dynamic>>(),
      Map<String, String>.from(d['facts'] as Map),
      vocab.toSet(),
      byLen,
    );
  }

  Category cat(String c) => cats[c] ?? Category(c, c, '', 1);

  // ---------- part 1: fragrance (decoder.js) ----------

  static final _fragranceWords = <(RegExp, String)>[
    (RegExp(r'\b(fragrance|parfum|perfume)\b', caseSensitive: false), 'Fragrance / Parfum'),
    (RegExp(r'\baroma\b', caseSensitive: false), 'Aroma (EU term for fragrance or flavor)'),
    (RegExp(r'\bflavou?r\b', caseSensitive: false), 'Flavor (can include the same scent chemicals)'),
    (RegExp(r'\bessential oils?\b', caseSensitive: false), 'Essential oil'),
    (RegExp(r'\bmasking\b', caseSensitive: false), 'Masking agent'),
  ];

  // Scented plant oils written INCI style; seed, kernel, nut and fruit oils are usually unscented carriers.
  static final _plantOil = RegExp(
      r'\b(flower|leaf|leaves|peel|rind|bark|herb|needle|root|wood|twig|stem|resin|balsam|zest)\s+(oil|extract|absolute|water)\b|\b(lavandula|citrus|mentha|eucalyptus|rosmarinus|melaleuca|cymbopogon|pelargonium|jasminum|rosa\s+damascena|santalum|cedrus|pogostemon|cananga|ylang|thymus|origanum|salvia\s+sclarea|litsea|cinnamomum|eugenia\s+caryophyllus|syzygium)[a-z\s]*\s+oil\b',
      caseSensitive: false);

  static String _normFragrance(String s) =>
      removeDiacritics(s.toLowerCase()).replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Ingredient lists are comma separated; also accept semicolons, bullets, and new lines.
  static List<String> split(String text) => text
      .split(RegExp(r'[,;\n•·●|]+'))
      .map((s) => s
          .replaceFirst(RegExp(r'^\s*(ingredients?|inci)\s*:\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'[.*\s]+$'), '')
          .trim())
      .where((s) => s.isNotEmpty)
      .toList();

  // ---------- part 2: other flags (decoder-flags.js) ----------

  static String norm(String s) => removeDiacritics(s.toLowerCase())
      .replaceAll(RegExp('[’\'`]'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  /// Exact name/synonym first, then without parentheses, then the parts in parentheses, then patterns.
  List<Map<String, dynamic>> _lookup(String raw) {
    final found = <Map<String, dynamic>>[];
    final tries = [raw, raw.replaceAll(RegExp(r'\([^)]*\)'), ' ')];
    for (final m in RegExp(r'\(([^)]+)\)').allMatches(raw)) {
      tries.add(m.group(1)!);
    }
    final seen = <String>{};
    for (final t in tries) {
      final idx = _names[norm(t)];
      if (idx != null && seen.add('$idx')) found.add(_items[idx]);
    }
    for (final p in _patterns) {
      if (p.re.hasMatch(raw) && seen.add('p${p.cat}')) {
        found.add({
          'n': raw,
          'f': [
            [p.cat, p.src, p.detail, p.url]
          ]
        });
      }
    }
    return found;
  }

  /// Typo-tolerant match against every real ingredient name: within 1 edit (6-9 letters) or 2 (10+),
  /// and only if the closest real name is flagged and no other name is equally close.
  String? _nearest(String raw) {
    final k = norm(raw);
    if (_vocabSet.contains(k)) return null;
    final max = k.length >= 10 ? 2 : (k.length >= 6 ? 1 : 0);
    if (max == 0) return null;
    var best = <String>[];
    var bestD = max + 1;
    for (var len = k.length - max; len <= k.length + max; len++) {
      for (final n in _byLen[len] ?? const <String>[]) {
        final d = _dist(k, n, bestD + 1);
        if (d < bestD) {
          bestD = d;
          best = [n];
        } else if (d == bestD) {
          best.add(n);
        }
      }
    }
    if (best.isEmpty || best.any((n) => _names[n] != _names[best[0]])) return null;
    return _names[best[0]] != null ? best[0] : null;
  }

  static int _dist(String a, String b, int cap) {
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      var rowMin = i;
      for (var j = 1; j <= b.length; j++) {
        final sub = prev[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
        var v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        if (sub < v) v = sub;
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin >= cap) return cap;
      prev = cur;
    }
    return prev[b.length];
  }

  List<FlagRow> _analyze(List<String> items, ProductType ptype) {
    final rows = <FlagRow>[];
    for (final item in items) {
      final flags = <Flag>[];
      final seen = <String>{};
      var hits = _lookup(item);
      String? guess;
      if (hits.isEmpty) {
        final n = _nearest(item);
        if (n != null) {
          final g = _items[_names[n]!];
          guess = g['n'] as String;
          hits = [g];
        }
      }
      for (final hit in hits) {
        for (final f in (hit['f'] as List)) {
          final l = (f as List);
          final flag = Flag(l[0] as String, l[1] as String, (l.length > 2 ? l[2] ?? '' : '') as String,
              l.length > 3 ? l[3] as String? : null);
          // The website de-duplicates on the flag's own fields.
          if (seen.add(flag.key)) flags.add(flag);
        }
        if (ptype == 'leave' && hit['ro'] != null && seen.add('ro')) {
          final ro = hit['ro'] as String;
          flags.add(Flag('leave-on-banned', RegExp(r'Annex V ').hasMatch(ro) ? 'annex5' : 'annex3',
              '$ro: rinse-off products only'));
        }
      }
      if (flags.isNotEmpty) rows.add(FlagRow(item, flags, guess));
    }
    return rows;
  }

  /// Decode a pasted or scanned ingredient list.
  Result decode(String text, {ProductType ptype = ''}) {
    final items = split(text);
    final fragrance = <FragranceHit>[];
    final allergens = <AllergenHit>[];
    final plantOils = <String>[];
    final seen = <String>{};
    for (final item in items) {
      final n = _normFragrance(item);
      for (final (re, label) in _fragranceWords) {
        if (re.hasMatch(item) && seen.add('f$label')) fragrance.add(FragranceHit(item, label));
      }
      var matched = false;
      for (final a in _allergens) {
        if (a.re.hasMatch(n) && seen.add('a${a.name}')) {
          matched = true;
          allergens.add(AllergenHit(item, a.name, a.kind, a.note));
        }
      }
      if (!matched && _plantOil.hasMatch(item) && seen.add('p$n')) plantOils.add(item);
    }
    final fragranceFound = fragrance.length + allergens.length + plantOils.length > 0;
    final rows = _analyze(items, ptype);
    final red = <String>{}, amber = <String>{};
    for (final r in rows) {
      for (final f in r.flags) {
        final lvl = cat(f.cat).level;
        if (lvl == 3) red.add(f.cat);
        if (lvl == 2) amber.add(f.cat);
      }
    }
    final verdict = red.isNotEmpty
        ? Verdict.red
        : (amber.isNotEmpty || fragranceFound ? Verdict.amber : Verdict.clear);
    return Result(items, fragrance, allergens, plantOils, rows, verdict, red.map((c) => cat(c).short).toList(),
        amber.map((c) => cat(c).short).toList());
  }

  /// The website's "What I care about" groups. A category in no group (e.g. the EU allergen label flag) is
  /// covered by the fragrance section instead of the flag list.
  static const groups = <String, (String, List<String>)>{
    'fragrance': ('Fragrance and scent allergens', ['scent-ingredient', 'oxidizes', 'ifra-prohibited', 'ifra-partial', 'ifra-restricted']),
    'skin': ('Skin and breathing allergens', ['skin-sensitizer', 'resp-sensitizer', 'formaldehyde', 'oxidizes']),
    'body': ('Cancer, hormones, and reproduction', ['carcinogen', 'carcinogen-possible', 'reprotoxic', 'reprotoxic-suspected', 'mutagen', 'mutagen-suspected', 'endocrine', 'endocrine-eval']),
    'banned': ('Banned, restricted, and chemicals of concern', ['eu-banned', 'leave-on-banned', 'ifra-prohibited', 'ifra-partial', 'ifra-restricted', 'pfas', 'csc', 'eu-restricted']),
  };

  /// Rows to list, keeping only flags in the chosen groups, worst first (stable, like the website).
  List<FlagRow> shown(Result r, {Set<String> on = const {'fragrance', 'skin', 'body', 'banned'}}) {
    final visible = <String>{for (final g in on) ...?groups[g]?.$2};
    final rows = <(int, int, FlagRow)>[];
    var i = 0;
    for (final row in r.rows) {
      final f = row.flags.where((x) => visible.contains(x.cat)).toList();
      if (f.isEmpty) continue;
      final worst = f.map((x) => cat(x.cat).level).reduce((a, b) => a > b ? a : b);
      rows.add((worst, i++, FlagRow(row.item, f, row.guess)));
    }
    rows.sort((a, b) => b.$1 != a.$1 ? b.$1 - a.$1 : a.$2 - b.$2);
    return [for (final x in rows) x.$3];
  }

  /// The ingredient's own page on ihateperfume.com, if it has one.
  String? pageFor(String name) {
    final slug = pages[norm(name)];
    return slug == null ? null : 'https://ihateperfume.com/ingredients/$slug/';
  }
}

class _Allergen {
  final String name;
  final String kind;
  final String note;
  final RegExp re;
  _Allergen(this.name, this.kind, this.note, this.re);
}

class _Pattern {
  final RegExp re;
  final String cat;
  final String src;
  final String detail;
  final String? url;
  _Pattern(this.re, this.cat, this.src, this.detail, this.url);
}
