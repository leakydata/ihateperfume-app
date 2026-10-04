/// Fragrance-free finds (docs/app-api.md, `GET /finds`): reviewed products that have no ingredient list. The last
/// good answer is kept on this phone, so the list works offline. Nothing is sent but the request itself.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'services.dart';

class Find {
  final String name;
  final String brand;
  final String category;
  final String? says; // 'fragrance-free', 'unscented', 'no scent listed', 'scented'
  final String? note;
  final String checked; // '2026-10'
  final String evidence; // 'package photo' or 'maker site'
  final String? barcode;
  const Find(
      {required this.name,
      this.brand = '',
      this.category = '',
      this.says,
      this.note,
      this.checked = '',
      this.evidence = '',
      this.barcode});

  /// "Checked Oct 2026 · package photo"
  String get checkedLine => [
        if (checked.isNotEmpty) 'Checked ${monthYear(checked)}',
        if (evidence.isNotEmpty) evidence == 'maker site' ? 'maker’s site' : evidence,
      ].join(' · ');
}

class FindsData {
  final DateTime? updated;
  final List<String> categories;
  final List<Find> items;
  const FindsData({this.updated, this.categories = const [], this.items = const []});
}

String? _s(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

/// The `GET /finds` answer, or null if it isn't one. Entries without a name are skipped; categories that items use
/// but the list leaves out are added at the end.
FindsData? parseFinds(Object? j) {
  if (j is! Map || j['items'] is! List) return null;
  final items = <Find>[];
  for (final x in j['items'] as List) {
    if (x is! Map || _s(x['name']) == null) continue;
    final barcode = _s(x['barcode']);
    items.add(Find(
      name: _s(x['name'])!,
      brand: _s(x['brand']) ?? '',
      category: _s(x['category']) ?? '',
      says: _s(x['says'])?.toLowerCase(),
      note: _s(x['note']),
      checked: _s(x['checked']) ?? '',
      evidence: _s(x['evidence']) ?? '',
      barcode: barcode != null && RegExp(r'^\d{8,14}$').hasMatch(barcode) ? barcode : null,
    ));
  }
  final cats = <String>[
    if (j['categories'] is List) ...(j['categories'] as List).map(_s).whereType<String>(),
  ];
  for (final f in items) {
    if (f.category.isNotEmpty && !cats.contains(f.category)) cats.add(f.category);
  }
  return FindsData(updated: DateTime.tryParse(_s(j['updated']) ?? ''), categories: cats, items: items);
}

/// The finds and when this phone got them.
class CachedFinds {
  final FindsData data;
  final DateTime fetched;
  const CachedFinds(this.data, this.fetched);

  /// The date to show as "Last updated": the server's, else when the phone got it.
  DateTime get updated => data.updated ?? fetched;
}

class FindsError implements Exception {
  final String message;
  const FindsError(this.message);
}

final findsUri = Uri.parse('$ihpApi/finds');

class FindsStore {
  static const _key = 'finds-cache';

  /// The last good answer kept on this phone, or null.
  static Future<CachedFinds?> cached() async {
    final p = await SharedPreferences.getInstance();
    try {
      final j = jsonDecode(p.getString(_key) ?? '') as Map<String, dynamic>;
      final data = parseFinds(j['body']);
      final at = DateTime.tryParse(j['fetched'] as String? ?? '');
      return data == null || at == null ? null : CachedFinds(data, at);
    } catch (_) {
      return null;
    }
  }

  /// Fetches the finds and keeps them on this phone. Throws [FindsError] (and keeps the old copy) on any problem.
  static Future<CachedFinds> refresh({http.Client? client, DateTime? now}) async {
    final c = client ?? http.Client();
    try {
      final res = await c.get(findsUri, headers: {'User-Agent': appUserAgent}).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw FindsError('The finds list isn’t available right now (error ${res.statusCode}).');
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final data = parseFinds(body);
      if (data == null) throw const FindsError('The finds list came back in a form the app can’t read.');
      final at = now ?? DateTime.now();
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode({'fetched': at.toIso8601String(), 'body': body}));
      return CachedFinds(data, at);
    } on FindsError {
      rethrow;
    } on FormatException {
      throw const FindsError('The finds list came back in a form the app can’t read.');
    } on Exception {
      throw const FindsError('Couldn’t reach ihateperfume.com. Check your connection.');
    } finally {
      if (client == null) c.close();
    }
  }
}
