/// "Ask us to find it" (docs/app-api.md, `POST /wanted`): when a barcode isn't found, the user can ask
/// ihateperfume.com to look for the product. Off until the user chooses: nothing is sent before they pick an option
/// in the one-time sheet. Only the barcode number and the app version are sent.
///
/// The barcodes the user asked about stay in a private list on this phone (max [maxWanted], oldest dropped, gone
/// after [wantedMaxAge]). At most once a day, a few seconds after start, the app checks up to [maxChecksPerDay] of
/// them with `GET /products/{barcode}` (only that barcode in each request) and remembers the ones that were added,
/// for the home screen's "We found N products you asked about." panel.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'contribute.dart' show appVersion;
import 'services.dart';

/// What happens when a barcode isn't found. Unset (null) until the user picks one in the sheet or in Learn.
enum WantedMode { auto, ask, off }

const maxWanted = 100;
const maxChecksPerDay = 20;
const wantedMaxAge = Duration(days: 180);
const _checkEvery = Duration(hours: 23); // "once a day", without drifting later each day
const _timeout = Duration(seconds: 10);

const _modeKey = 'wanted-mode';
const _listKey = 'wanted-list';
const _foundKey = 'wanted-found';
const _lastCheckKey = 'wanted-last-check';

final wantedUri = Uri.parse('$ihpApi/wanted');

/// A barcode the user asked us to find. [checked] is the last time the found-it check asked about it.
class WantedEntry {
  final String barcode;
  final String? name;
  final DateTime asked;
  final DateTime? checked;
  const WantedEntry(this.barcode, this.asked, {this.name, this.checked});

  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        if (name != null) 'name': name,
        'asked': asked.toIso8601String(),
        if (checked != null) 'checked': checked!.toIso8601String(),
      };

  static WantedEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final b = j['barcode'], a = DateTime.tryParse('${j['asked']}');
    if (b is! String || a == null) return null;
    final n = j['name'];
    return WantedEntry(b, a,
        name: n is String && n.trim().isNotEmpty ? n.trim() : null, checked: DateTime.tryParse('${j['checked']}'));
  }
}

/// Only barcodes the server accepts: 8 to 14 digits.
bool isWantedBarcode(String? b) => b != null && RegExp(r'^\d{8,14}$').hasMatch(b);

/// The exact request: the barcode and the app version, form encoded, with the app's User-Agent. Nothing else.
http.Request buildWantedRequest(String barcode) => http.Request('POST', wantedUri)
  ..headers['User-Agent'] = appUserAgent
  ..bodyFields = {'barcode': barcode, 'app': appVersion};

class Wanted {
  /// Products the found-it check found, until the user dismisses the home panel.
  static final found = ValueNotifier<List<Product>>(const []);

  static Future<WantedMode?> mode() async {
    final v = (await SharedPreferences.getInstance()).getString(_modeKey);
    return WantedMode.values.where((m) => m.name == v).firstOrNull;
  }

  static Future<void> setMode(WantedMode m) async =>
      (await SharedPreferences.getInstance()).setString(_modeKey, m.name);

  /// The local list, newest first, without entries older than [wantedMaxAge].
  static Future<List<WantedEntry>> list({DateTime? now}) async {
    final p = await SharedPreferences.getInstance();
    List<WantedEntry> all;
    try {
      all = (jsonDecode(p.getString(_listKey) ?? '[]') as List).map(WantedEntry.fromJson).nonNulls.toList();
    } catch (_) {
      all = [];
    }
    final t = now ?? DateTime.now();
    return all.where((e) => t.difference(e.asked) <= wantedMaxAge).toList();
  }

  static Future<void> _save(List<WantedEntry> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_listKey, jsonEncode(l.take(maxWanted).map((e) => e.toJson()).toList()));
  }

  /// Add [barcode] to the front of the local list (moved there if it's already in it). Oldest dropped past
  /// [maxWanted].
  static Future<void> remember(String barcode, {String? name, DateTime? now}) async {
    final t = now ?? DateTime.now();
    final l = await list(now: t)..removeWhere((e) => e.barcode == barcode);
    l.insert(0, WantedEntry(barcode, t, name: name));
    await _save(l);
  }

  static Future<bool> isAsked(String barcode) async => (await list()).any((e) => e.barcode == barcode);

  /// Send [barcode] to ihateperfume.com. True when the server took it (and then it's in the local list). Never
  /// throws. Invalid barcodes are never sent.
  static Future<bool> send(String barcode, {String? name, http.Client? client}) async {
    if (!isWantedBarcode(barcode)) return false;
    final c = client ?? http.Client();
    try {
      final res = await c.send(buildWantedRequest(barcode)).then(http.Response.fromStream).timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      await remember(barcode, name: name);
      return true;
    } on Exception {
      return false;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Load the found products saved by an earlier check (for the home panel).
  static Future<void> loadFound() async {
    try {
      final p = await SharedPreferences.getInstance();
      found.value = (jsonDecode(p.getString(_foundKey) ?? '[]') as List).map(_productFromJson).nonNulls.toList();
    } catch (_) {
      found.value = const [];
    }
  }

  /// The user closed the panel: forget the found products.
  static Future<void> dismissFound() async {
    found.value = const [];
    (await SharedPreferences.getInstance()).remove(_foundKey);
  }

  static bool _triedThisRun = false;

  /// For tests: allow another check in this run.
  @visibleForTesting
  static void resetRun() => _triedThisRun = false;

  /// The found-it check. Does nothing (no request at all) when the list is empty, when it already ran today, or
  /// when it already ran in this app run. Checks the [maxChecksPerDay] least recently checked barcodes, one
  /// `GET /products/{barcode}` each. Found ones leave the list and go to [found]; not found or unreachable ones stay.
  /// Returns the products found by this check.
  static Future<List<Product>> checkFound({http.Client? client, DateTime? now, bool force = false}) async {
    final t = now ?? DateTime.now();
    final p = await SharedPreferences.getInstance();
    final l = await list(now: t);
    await _save(l); // drops the ones past wantedMaxAge
    if (l.isEmpty) return const [];
    if (!force) {
      final last = DateTime.tryParse(p.getString(_lastCheckKey) ?? '');
      if (_triedThisRun || (last != null && t.difference(last).abs() < _checkEvery)) return const [];
    }
    _triedThisRun = true;
    await p.setString(_lastCheckKey, t.toIso8601String());
    final due = [...l]..sort((a, b) => (a.checked ?? DateTime(0)).compareTo(b.checked ?? DateTime(0)));
    final c = client ?? http.Client();
    final hits = <Product>[];
    final tried = <String>{};
    try {
      for (final e in due.take(maxChecksPerDay)) {
        tried.add(e.barcode);
        final (prod, _) = await lookUpIhp(e.barcode, c);
        if (prod != null) {
          hits.add(Product(prod.barcode, prod.name.isNotEmpty ? prod.name : (e.name ?? ''), prod.ingredients,
              prod.source, ihp: prod.ihp));
        }
      }
    } finally {
      if (client == null) c.close();
    }
    // Re-read: a barcode may have been asked about while this ran.
    final foundCodes = hits.map((h) => h.barcode).toSet();
    final now2 = await list(now: t);
    await _save([
      for (final e in now2)
        if (!foundCodes.contains(e.barcode))
          tried.contains(e.barcode) ? WantedEntry(e.barcode, e.asked, name: e.name, checked: t) : e,
    ]);
    if (hits.isNotEmpty) {
      await loadFound();
      final all = [...hits, ...found.value.where((f) => !foundCodes.contains(f.barcode))];
      await p.setString(_foundKey, jsonEncode(all.map(_productToJson).toList()));
      found.value = all;
    }
    return hits;
  }
}

/// Check a few seconds after the app is up (never blocks it), at most once a day, only if the list has barcodes.
void scheduleWantedCheck({Duration after = const Duration(seconds: 8)}) {
  Timer(after, () async {
    try {
      await Wanted.loadFound();
      await Wanted.checkFound();
    } catch (e) {
      if (kDebugMode) debugPrint('Found-it check: $e');
    }
  });
}

Map<String, dynamic> _productToJson(Product p) => {
      'barcode': p.barcode,
      'name': p.name,
      'ingredients': p.ingredients,
      'source': p.source,
      if (p.ihp != null) 'ihp': p.ihp!.toJson(),
    };

Product? _productFromJson(Object? j) {
  if (j is! Map) return null;
  final b = j['barcode'], n = j['name'], i = j['ingredients'], s = j['source'];
  if (b is! String || s is! String) return null;
  return Product(b, n is String ? n : '', i is String ? i : null, s,
      ihp: j['ihp'] is Map ? IhpInfo.fromJson((j['ihp'] as Map).cast<String, dynamic>()) : null);
}
