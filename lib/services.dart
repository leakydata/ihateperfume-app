/// The ingredient data and spelling index, recent scans (kept only on this phone), and the barcode lookup.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'data_update.dart';
import 'engine/decoder.dart';
import 'engine/ocr_fix.dart';

// The data's version and source, and a check for newer data (for the home footer and the Learn screen).
export 'data_update.dart' show DataCheck, DataStatus, barcodeKey, checkForDataUpdate, dataStatus, localProduct;

/// The decoder in use: the bundled data, or newer data downloaded from the site (see data_update.dart).
late Decoder decoder;

/// The data version (decoder-data.json "v", e.g. 2026-09-27). [dataStatus] has it with its source, to listen to.
String dataVersion = '';

/// Load the newest valid ingredient data (downloaded or bundled). The splash waits for this.
Future<void> loadDecoder() => loadData();

/// The User-Agent every request to ihateperfume.com and the product databases carries.
String get appUserAgent => _userAgent;

// ---------- spelling suggestions: built when first needed, let go when not used for a while ----------

Future<OcrFix>? _spelling;
Timer? _spellingIdle;
const _spellingKeep = Duration(minutes: 3);

/// Spelling suggestions for the review screen. The index (about 2 MB) is built from the loaded decoder on first
/// use, which takes a moment, and dropped a few minutes after the last use so it isn't held while it's not needed.
Future<OcrFix> get spelling {
  if (_spellingSet) return _spelling!;
  _spellingIdle?.cancel();
  _spellingIdle = Timer(_spellingKeep, dropSpelling);
  return _spelling ??= OcrFix.build(decoder)
    ..then((_) {}, onError: (_) => dropSpelling());
}

bool _spellingSet = false;

/// Use this index (tests). It isn't dropped when idle.
set spelling(Future<OcrFix> f) {
  _spellingIdle?.cancel();
  _spellingIdle = null;
  _spellingSet = true;
  _spelling = f;
}

/// Let the spelling index go (screens that hold it keep it until they close). The next use rebuilds it.
void dropSpelling() {
  _spellingIdle?.cancel();
  _spellingIdle = null;
  _spellingSet = false;
  _spelling = null;
}

// ---------- recent scans: shared preferences on the phone, excluded from Android backup ----------

class Scan {
  final String name;
  final String? barcode;
  final String text;
  final String source; // 'obf', 'opf', 'fda', 'ihp', 'photo', 'typed'
  final DateTime at;
  final String tag; // summary chip, e.g. "3 scent"
  final int level;
  final IhpInfo? ihp; // our review details, for products we checked (text is empty when it has no list)
  const Scan(this.name, this.barcode, this.text, this.source, this.at, this.tag, this.level, {this.ihp});

  Map<String, dynamic> toJson() => {
        'name': name,
        'barcode': barcode,
        'text': text,
        'source': source,
        'at': at.toIso8601String(),
        'tag': tag,
        'level': level,
        if (ihp != null) 'ihp': ihp!.toJson(),
      };
  static Scan fromJson(Map<String, dynamic> j) => Scan(j['name'] as String, j['barcode'] as String?,
      j['text'] as String, j['source'] as String, DateTime.parse(j['at'] as String), (j['tag'] ?? '') as String,
      (j['level'] ?? 1) as int,
      ihp: j['ihp'] is Map ? IhpInfo.fromJson((j['ihp'] as Map).cast<String, dynamic>()) : null);
}

class History {
  static const _key = 'recent-scans';
  static const _max = 50;
  static final changes = ChangeNotice();

  static Future<List<Scan>> all() async {
    final p = await SharedPreferences.getInstance();
    try {
      return ((jsonDecode(p.getString(_key) ?? '[]') as List).cast<Map<String, dynamic>>()).map(Scan.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(Scan s) async {
    final list = await all();
    list.removeWhere((x) => (s.barcode != null && x.barcode == s.barcode) || (s.text.isNotEmpty && x.text == s.text));
    list.insert(0, s);
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list.take(_max).map((x) => x.toJson()).toList()));
    changes.bump();
  }

  static Future<void> remove(Scan s) async {
    final list = await all();
    list.removeWhere((x) => x.at == s.at && x.text == s.text);
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list.map((x) => x.toJson()).toList()));
    changes.bump();
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
    changes.bump();
  }
}

class ChangeNotice extends ChangeNotifier {
  void bump() => notifyListeners();
}

/// Product type, saved on the phone: '' not sure, 'leave', 'rinse', 'home'.
class Prefs {
  static Future<String> productType() async => (await SharedPreferences.getInstance()).getString('ptype') ?? '';
  static Future<void> setProductType(String t) async => (await SharedPreferences.getInstance()).setString('ptype', t);
}

// ---------- barcode lookup: only the barcode number is sent ----------

class Product {
  final String barcode;
  final String name;
  final String? ingredients;
  final String source; // 'obf', 'opf', 'fda', or 'ihp'
  final IhpInfo? ihp; // set for products we reviewed ourselves
  const Product(this.barcode, this.name, this.ingredients, this.source, {this.ihp});
  String get sourceName => switch (source) {
        'obf' => 'Open Beauty Facts',
        'opf' => 'Open Products Facts',
        'ihp' => 'I Hate Perfume',
        _ => 'openFDA',
      };

  /// One of ours with no ingredient list on the package: shown with what the package says instead.
  bool get noList => ingredients == null && (ihp?.noList ?? false);
}

class LookupError implements Exception {
  final String message;
  const LookupError(this.message);
}

const _hosts = {'obf': 'world.openbeautyfacts.org', 'opf': 'world.openproductsfacts.org'};
const _fields = 'product_name,product_name_en,brands,ingredients_text,ingredients_text_en';
const _userAgent = 'IHatePerfume-Android/1.0 (https://ihateperfume.com)';
const _timeout = Duration(seconds: 10);

/// First the products we reviewed ourselves, from the copy on the phone (see data_update.dart): a hit returns at
/// once and nothing is sent anywhere. Then Open Beauty Facts, then Open Products Facts, then the FDA's drug labels (for US over-the-counter products such
/// as sunscreen and antiperspirant), then the products we reviewed ourselves on ihateperfume.com (which may have
/// no ingredient list, only what the package says about scent). Returns the first product that has an ingredient list, else the first one
/// found without one, else null. Throws [LookupError] if none of them could be reached.
Future<Product?> lookUp(String barcode, {http.Client? client}) async {
  final local = localProduct(barcode);
  if (local != null) return local;
  final c = client ?? http.Client();
  Product? nameOnly;
  var reached = 0;
  try {
    for (final e in _hosts.entries) {
      final uri = Uri.https(e.value, '/api/v2/product/$barcode.json', {'fields': _fields});
      try {
        final res = await c.get(uri, headers: {'User-Agent': _userAgent}).timeout(_timeout);
        reached++;
        if (res.statusCode != 200) continue;
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        if (j['status'] != 1 || j['product'] is! Map) continue;
        final p = j['product'] as Map<String, dynamic>;
        String s(String k) => ((p[k] ?? '') as Object).toString().trim();
        final name = [s('brands').split(',').first.trim(), s('product_name_en').isNotEmpty ? s('product_name_en') : s('product_name')]
            .where((x) => x.isNotEmpty)
            .join(' ');
        // Open Food Facts style lists mark allergens with underscores (_milk_); drop them.
        final ing = (s('ingredients_text_en').isNotEmpty ? s('ingredients_text_en') : s('ingredients_text'))
            .replaceAll('_', '')
            .trim();
        final prod = Product(barcode, name, ing.isEmpty ? null : ing, e.key);
        if (prod.ingredients != null) return prod;
        nameOnly ??= prod;
      } on Exception {
        continue;
      }
    }
    final (fda, fdaReached) = await _lookUpFda(barcode, c);
    if (fdaReached) reached++;
    if (fda?.ingredients != null) return fda;
    nameOnly ??= fda;
    final (ours, oursReached) = await lookUpIhp(barcode, c);
    if (oursReached) reached++;
    if (ours != null && (ours.ingredients != null || ours.noList)) return ours;
    nameOnly ??= ours;
  } finally {
    if (client == null) c.close();
  }
  if (reached == 0) throw const LookupError('Couldn’t reach the product databases. Check your connection.');
  return nameOnly;
}

// ---------- openFDA drug labels (public domain, no key; 240 requests a minute, 1,000 a day per IP) ----------

/// The 13-digit form openFDA lists UPCs in: a 12-digit UPC-A gets a leading zero, an EAN-13 stays as is, and a
/// GTIN-14 that starts with 0 loses it. Null for other lengths (EAN-8, UPC-E).
String? fdaUpc(String barcode) {
  if (!RegExp(r'^\d+$').hasMatch(barcode)) return null;
  return switch (barcode.length) {
    12 => '0$barcode',
    13 => barcode,
    14 when barcode.startsWith('0') => barcode.substring(1),
    _ => null,
  };
}

/// A drug's UPC-A often holds its National Drug Code: "3", then the 10 NDC digits, then the check digit. The
/// dashes aren't in the barcode, so this gives the three ways they can fall (4-4-2, 5-3-2, 5-4-1). Empty if the
/// barcode isn't a UPC-A starting with 3.
List<String> ndcCandidates(String barcode) {
  final u = fdaUpc(barcode);
  if (u == null || !u.startsWith('03')) return const [];
  final d = u.substring(2, 12);
  return [
    '${d.substring(0, 4)}-${d.substring(4, 8)}-${d.substring(8)}',
    '${d.substring(0, 5)}-${d.substring(5, 8)}-${d.substring(8)}',
    '${d.substring(0, 5)}-${d.substring(5, 9)}-${d.substring(9)}',
  ];
}

/// One openFDA query, `search` already in openFDA's syntax. Null if nothing matched; throws if it couldn't be
/// reached.
Future<Map<String, dynamic>?> _fdaFirst(http.Client c, String endpoint, String search) async {
  // Built by hand: openFDA wants the quotes and the + between terms as they are, not percent-encoded.
  final uri = Uri.parse('https://api.fda.gov/drug/$endpoint.json?search=$search&limit=1');
  final res = await c.get(uri, headers: {'User-Agent': _userAgent}).timeout(_timeout);
  if (res.statusCode != 200) return null; // 404 is openFDA's "No matches found"
  final j = jsonDecode(utf8.decode(res.bodyBytes));
  if (j is! Map || j['results'] is! List || (j['results'] as List).isEmpty) return null;
  return (j['results'] as List).first as Map<String, dynamic>;
}

/// The FDA label for this barcode: by its UPC, else by the NDC inside it. Returns (product or null, reached).
/// Any error counts as not found.
Future<(Product?, bool)> _lookUpFda(String barcode, http.Client c) async {
  final upc = fdaUpc(barcode);
  if (upc == null) return (null, false);
  var reached = false;
  try {
    var label = await _fdaFirst(c, 'label', 'openfda.upc:"$upc"');
    reached = true;
    final ndcs = ndcCandidates(barcode);
    if (label == null && ndcs.isNotEmpty) {
      // One request for all three dash patterns (a space between terms means "or").
      final pkg = await _fdaFirst(c, 'ndc', ndcs.map((n) => 'packaging.package_ndc:"$n"').join('+'));
      final productNdc = pkg?['product_ndc'];
      if (productNdc is String && RegExp(r'^[\d-]+$').hasMatch(productNdc)) {
        label = await _fdaFirst(c, 'label', 'openfda.product_ndc:"$productNdc"');
      }
    }
    return (label == null ? null : parseFdaLabel(barcode, label), reached);
  } on Exception {
    return (null, reached);
  }
}

/// A product from an openFDA drug label: the name, and its active then inactive ingredients. A label without an
/// inactive ingredient list counts as no ingredient list.
Product? parseFdaLabel(String barcode, Map<String, dynamic> label) {
  String joined(Object? v) =>
      v is List ? v.whereType<String>().join(' ').trim() : (v is String ? v.trim() : '');
  final openfda = label['openfda'] is Map ? label['openfda'] as Map : const {};
  String first(String k) {
    final v = openfda[k];
    return v is List && v.isNotEmpty && v.first is String ? (v.first as String).trim() : '';
  }

  final actives = fdaActives(joined(label['active_ingredient']), joined(label['purpose']));
  final inactive = fdaInactive(joined(label['inactive_ingredient']));

  var name = first('brand_name');
  final generic = first('generic_name');
  // generic_name is often just the active ingredients ("ZINC OXIDE"), but sometimes the product's own name.
  final g = generic.toLowerCase();
  if (generic.isNotEmpty &&
      g != name.toLowerCase() &&
      !actives.any((a) => g.contains(a.toLowerCase())) &&
      !name.toLowerCase().contains(g)) {
    name = [name, _titleCase(generic)].where((x) => x.isNotEmpty).join(' ');
  }
  if (name.isEmpty) name = first('manufacturer_name');
  if (name.isEmpty && inactive.isEmpty) return null;
  return Product(barcode, _titleCase(name), inactive.isEmpty ? null : [...actives, inactive].join(', '), 'fda');
}

String _titleCase(String s) => s == s.toUpperCase() && s.contains(RegExp('[A-Z]'))
    ? s.toLowerCase().replaceAllMapped(RegExp(r"(^|[\s/(-])([a-z])"), (m) => '${m[1]}${m[2]!.toUpperCase()}')
    : s;

/// The inactive ingredient list without its heading: "Inactive ingredients: Water, …" → "Water, …".
String fdaInactive(String s) => s
    .replaceFirst(RegExp(r'^.*?\binactive\s+ingredients?\b\s*[:.]?\s*', caseSensitive: false), '')
    .replaceFirst(RegExp(r'[\s.]+$'), '')
    .trim();

/// Active ingredient names, without the heading, strengths, or purposes:
/// "Active ingredients Purpose Avobenzone 3% Sunscreen Homosalate 10% Sunscreen" → [Avobenzone, Homosalate].
List<String> fdaActives(String active, String purpose) {
  final heading = RegExp(r'^.*?\bactive\s+ingredients?\b\s*(\([^)]*\))?\s*[:.]?\s*(purposes?\b\s*[:.]?)?\s*',
      caseSensitive: false);
  var t = active.replaceFirst(heading, '');
  // The purpose column, when it's printed separately ("Purpose Sunscreen"), to cut out of the names.
  final purposeText = purpose.toLowerCase().contains('active ingredient')
      ? ''
      : purpose.replaceFirst(RegExp(r'^\s*purposes?\b\s*[:.]?\s*', caseSensitive: false), '').toLowerCase();
  final strength = RegExp(r'\(?\s*\d+(?:\.\d+)?\s*%\s*(?:w/w|w/v|v/v)?\s*\)?', caseSensitive: false);
  final parts = t.split(strength);
  if (parts.length == 1) {
    t = t.replaceFirst(RegExp(r'[\s.,;]+$'), '').trim();
    return t.isEmpty || t.length > 80 ? const [] : [t];
  }
  // Whatever follows the last strength is a purpose ("Sunscreen"); the same words start the next name too.
  final trailing = parts.last.replaceAll(RegExp(r'^[\s,;.]+|[\s,;.]+$'), '').toLowerCase();
  final names = <String>[];
  for (var i = 0; i < parts.length - 1; i++) {
    var n = parts[i].replaceAll(RegExp(r'^[\s,;.]+|[\s,;.]+$'), '');
    if (i > 0) {
      final words = n.split(RegExp(r'\s+'));
      // Drop leading words that are the purpose of the previous ingredient.
      for (var k = words.length - 1; k >= 1; k--) {
        final lead = words.take(k).join(' ').toLowerCase();
        if (lead == trailing || (purposeText.isNotEmpty && purposeText.contains(lead))) {
          n = words.skip(k).join(' ');
          break;
        }
      }
    }
    if (n.isNotEmpty) names.add(n);
  }
  return names;
}

/// GS1 company prefixes (as the first digits of a 13-digit code) of Procter & Gamble, checked against P&G
/// products in openFDA and Open Beauty Facts: Crest, Secret, Scope (0037000), Old Spice (0012044), Secret, Dawn,
/// Crest (0030772), Gillette (0047400), Olay (0075609), Pantene (0080878), and Vicks (0323900).
const _pgPrefixes = ['0037000', '0012044', '0030772', '0047400', '0075609', '0080878', '0323900'];

/// Where to read the maker's own ingredient list, opened in the browser only when the user taps; the app never
/// fetches it (the SmartLabel and P&G terms forbid scraping). P&G barcodes go straight to P&G's SmartLabel page;
/// other barcodes to SmartLabel's product search, which covers many brands (no result if the maker isn't in it).
(String, String)? makerPage(String barcode) {
  final g13 = fdaUpc(barcode);
  if (g13 == null) return null;
  if (_pgPrefixes.any(g13.startsWith)) {
    return ('https://smartlabel.pg.com/en-us/0$g13.html', 'See the maker’s ingredient page');
  }
  return ('https://smartlabel.org/product-search/?product=$barcode', 'Search SmartLabel for this barcode');
}

/// Tidy text read from a photo of a label: start at "Ingredients:", and join lines broken mid-ingredient.
String cleanOcr(String raw) {
  var t = raw.replaceAll('\r', '');
  // The heading, even misread: "IMGREDIENTS:", "lNGREDIENTS;", "1NGREDIENTS.", "Ingrédients:", "INCI:".
  int dist(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = [i, ...List<int>.filled(b.length, 0)];
      for (var j = 1; j <= b.length; j++) {
        final sub = prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        final del = prev[j] + 1, ins = cur[j - 1] + 1;
        cur[j] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  for (final m in RegExp(r'([^\s:;.,]{4,13})\s*[:;.]').allMatches(t)) {
    final w = Decoder.norm(m[1]!.replaceAll(RegExp('[1|!]'), 'i').replaceAll('0', 'o')).replaceAll('l', 'i');
    if (w == 'inci' ||
        (w.length >= 8 && (dist(w, 'ingredients') <= 2 || dist(w, 'ingredient') <= 2 || dist(w, 'ingredientes') <= 2))) {
      t = t.substring(m.end);
      break;
    }
  }
  final lines = t.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  // Labels are comma separated; if there are commas, a new line is just the label wrapping.
  if (t.contains(',') && lines.length > 1) {
    final b = StringBuffer(lines.first);
    for (final l in lines.skip(1)) {
      final prev = b.toString();
      if (prev.endsWith('-') && RegExp(r'^[a-z]').hasMatch(l)) {
        b
          ..clear()
          ..write(prev.substring(0, prev.length - 1))
          ..write(l);
      } else {
        b.write(' $l');
      }
    }
    t = b.toString();
  } else {
    t = lines.join('\n');
  }
  // The list ends at a period followed by label text: a usual next heading ("Made in…", "Warning…"), or prose
  // with no more commas.
  final end = RegExp(
          r'\.\s+(?=(made|distributed|dist\.|manufactured|mfd|warnings?|caution|directions|keep|for external|questions|net wt|contains)\b)',
          caseSensitive: false)
      .firstMatch(t);
  if (end != null) {
    t = t.substring(0, end.start + 1);
  } else {
    for (final m in RegExp(r'\.\s+(?=[A-Z])').allMatches(t)) {
      if (!t.substring(m.end).contains(',')) {
        t = t.substring(0, m.start + 1);
        break;
      }
    }
  }
  // Label text glued on with no period: "Sodium Hydroxide 0299393816 Galderma Distributed by: ... TX 75201".
  // Never inside the first item.
  final firstSep = t.indexOf(RegExp(r'[,;\n]'));
  if (firstSep > 0) {
    const states = 'AL|AK|AZ|AR|CA|CO|CT|DE|DC|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|'
        'NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY';
    final footers = [
      RegExp(
          r'\b(distributed|dist\.?\s*by|manufactured\s+(for|by)|mfd|made\s+in|product\s+of|warnings?|caution|'
          r'directions|keep\s+out\s+of|for\s+external\s+use|questions|net\s+wt)\b',
          caseSensitive: false),
      RegExp(r'www\.|https?://|\b[a-z0-9-]+\.(com|net|org)\b', caseSensitive: false),
      RegExp(r'\b(' + states + r'),?\s+[0-9]{5}(-[0-9]{4})?\b'), // state and zip
      RegExp(r'\(?\b[0-9]{3}\)?[\s.-][0-9]{3}[\s.-][0-9]{4}\b'), // phone
      RegExp(r'[0-9]{8,}'), // lot number or barcode
    ];
    var cut = t.length;
    for (final r in footers) {
      for (final m in r.allMatches(t)) {
        if (m.start > firstSep) {
          if (m.start < cut) cut = m.start;
          break;
        }
      }
    }
    if (cut < t.length) t = t.substring(0, cut).replaceFirst(RegExp(r'[\s,;:]+$'), '');
  }
  return t.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\s+,'), ',').trim();
}

// ---------- ihateperfume.com: products we reviewed ourselves (docs/app-api.md); only the barcode is sent ----------

const ihpApi = 'https://ihateperfume.com/wp-json/ihp-app/v1';


/// What we recorded when we reviewed a product: what the package says about scent, when, and from what.
class IhpInfo {
  final String? says; // 'fragrance-free', 'unscented', 'no scent listed', 'scented', or null
  final String checked; // '2026-10'
  final String evidence; // 'package photo' or 'maker site'
  final bool noList;
  const IhpInfo({this.says, this.checked = '', this.evidence = '', this.noList = false});

  Map<String, dynamic> toJson() => {'says': says, 'checked': checked, 'evidence': evidence, 'no_list': noList};
  static IhpInfo fromJson(Map<String, dynamic> j) => IhpInfo(
        says: _str(j['says']),
        checked: _str(j['checked']) ?? '',
        evidence: _str(j['evidence']) ?? '',
        noList: j['no_list'] == true,
      );
}

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

/// A product from `GET /products/{barcode}`, or null if the answer isn't one.
Product? parseIhpProduct(String barcode, Object? j) {
  if (j is! Map) return null;
  final m = j.cast<String, dynamic>();
  final ing = _str(m['ingredients']);
  final info = IhpInfo.fromJson(m);
  if (ing == null && !info.noList) return null;
  return Product(barcode, _str(m['name']) ?? '', ing, 'ihp', ihp: info);
}

/// Our own reviewed products: only the barcode is in the request. 404 or any error counts as not found.
/// Returns (product or null, reached).
Future<(Product?, bool)> lookUpIhp(String barcode, http.Client c) async {
  if (!RegExp(r'^\d{8,14}$').hasMatch(barcode)) return (null, false);
  try {
    final res =
        await c.get(Uri.parse('$ihpApi/products/$barcode'), headers: {'User-Agent': _userAgent}).timeout(_timeout);
    if (res.statusCode != 200) return (null, true);
    return (parseIhpProduct(barcode, jsonDecode(utf8.decode(res.bodyBytes))), true);
  } on Exception {
    return (null, false);
  }
}

/// "2026-10" → "Oct 2026" (left as it is if it isn't a year and month).
String monthYear(String ym) {
  final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(ym);
  final i = m == null ? 0 : int.parse(m[2]!);
  if (i < 1 || i > 12) return ym;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[i - 1]} ${m![1]}';
}

/// "Reviewed by I Hate Perfume from a package photo (Oct 2026)."
String ihpNote(IhpInfo? i) {
  final from = switch (i?.evidence) {
    'package photo' => 'a package photo',
    'maker site' => 'the maker’s site',
    _ => 'a package photo or the maker’s site',
  };
  final when = i == null || i.checked.isEmpty ? '' : ' (${monthYear(i.checked)})';
  return 'Reviewed by I Hate Perfume from $from$when.';
}

/// The chip for what a package says about scent: its text and level (0 green when no scent is named, 3 red for
/// scented).
(String, int)? saysTag(String? says) => switch (says) {
      'fragrance-free' => ('Says fragrance-free', 0),
      'unscented' => ('Says unscented', 0),
      'no scent listed' => ('No scent listed', 0),
      'scented' => ('Scented', 3),
      _ => null,
    };
