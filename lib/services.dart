/// Loading the bundled decoder data, recent scans (kept only on this phone), and the barcode lookup.
library;

import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/decoder.dart';

late Decoder decoder;

/// The data version (decoder-data.json "v", e.g. 2026-09-27).
String dataVersion = '';

Future<void> loadDecoder() async {
  final a = await rootBundle.loadString('assets/data/decoder.json');
  final b = await rootBundle.loadString('assets/data/decoder-data.json');
  final c = await rootBundle.loadString('assets/data/inci-vocab.json');
  decoder = await Isolate.run(() => Decoder.fromJson(a, b, c));
  dataVersion = (jsonDecode(b) as Map)['v'] as String? ?? '';
}

// ---------- recent scans: shared preferences on the phone, excluded from Android backup ----------

class Scan {
  final String name;
  final String? barcode;
  final String text;
  final String source; // 'obf', 'opf', 'photo', 'typed'
  final DateTime at;
  final String tag; // summary chip, e.g. "3 scent"
  final int level;
  const Scan(this.name, this.barcode, this.text, this.source, this.at, this.tag, this.level);

  Map<String, dynamic> toJson() => {
        'name': name,
        'barcode': barcode,
        'text': text,
        'source': source,
        'at': at.toIso8601String(),
        'tag': tag,
        'level': level,
      };
  static Scan fromJson(Map<String, dynamic> j) => Scan(j['name'] as String, j['barcode'] as String?,
      j['text'] as String, j['source'] as String, DateTime.parse(j['at'] as String), (j['tag'] ?? '') as String,
      (j['level'] ?? 1) as int);
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
    list.removeWhere((x) => (s.barcode != null && x.barcode == s.barcode) || x.text == s.text);
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
  final String source; // 'obf' or 'opf'
  const Product(this.barcode, this.name, this.ingredients, this.source);
  String get sourceName => source == 'obf' ? 'Open Beauty Facts' : 'Open Products Facts';
}

class LookupError implements Exception {
  final String message;
  const LookupError(this.message);
}

const _hosts = {'obf': 'world.openbeautyfacts.org', 'opf': 'world.openproductsfacts.org'};
const _fields = 'product_name,product_name_en,brands,ingredients_text,ingredients_text_en';
const _userAgent = 'IHatePerfume-Android/1.0 (https://ihateperfume.com)';

/// Open Beauty Facts first, then Open Products Facts. Returns the first product that has an ingredient list,
/// else the first one found without one, else null. Throws [LookupError] if neither could be reached.
Future<Product?> lookUp(String barcode, {http.Client? client}) async {
  final c = client ?? http.Client();
  Product? nameOnly;
  var reached = 0;
  try {
    for (final e in _hosts.entries) {
      final uri = Uri.https(e.value, '/api/v2/product/$barcode.json', {'fields': _fields});
      try {
        final res = await c.get(uri, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 10));
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
  } finally {
    if (client == null) c.close();
  }
  if (reached == 0) throw const LookupError('Couldn’t reach Open Beauty Facts. Check your connection.');
  return nameOnly;
}

/// Tidy text read from a photo of a label: start at "Ingredients:", and join lines broken mid-ingredient.
String cleanOcr(String raw) {
  var t = raw.replaceAll('\r', '');
  final m = RegExp(r'\b(ingredients?|inci)\s*[:;.]', caseSensitive: false).firstMatch(t);
  if (m != null) t = t.substring(m.end);
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
  return t.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\s+,'), ',').trim();
}
