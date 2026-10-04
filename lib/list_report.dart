/// "Wrong or missing ingredients? Report it" (docs/app-api.md, `POST /reports`): the user can tell us a barcode's
/// ingredient list is wrong. Sent only when they tap "Just report" in the report sheet, and only the barcode, where
/// the list came from, the reason, and the app version. The (barcode, source) pairs they reported stay in a private
/// list on this phone (max [maxReported], oldest dropped), so the link can say "Reported. Thanks." afterwards.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'contribute.dart' show appVersion;
import 'services.dart';

/// Why the list is wrong, with the key the server takes.
enum ReportReason {
  notIngredients('not_ingredients', 'These aren’t ingredients'),
  wrongProduct('wrong_product', 'It’s a different product'),
  missing('missing', 'Ingredients are missing'),
  other('other', 'Something else');

  final String key;
  final String label;
  const ReportReason(this.key, this.label);
}

/// The sources the server takes reports for.
const reportSources = {'obf', 'opf', 'fda', 'ihp'};

const maxReported = 200;
const _reportedKey = 'reported-lists';
const _timeout = Duration(seconds: 10);

final reportsUri = Uri.parse('$ihpApi/reports');

/// The source a report names for a result: the result's own source when it came from a database, else the lookup
/// that found the barcode (for a list photographed or typed after a lookup); null when neither is known.
String? reportSourceFor(String source, String? lookupSource) => reportSources.contains(source)
    ? source
    : (lookupSource != null && reportSources.contains(lookupSource) ? lookupSource : null);

/// Only barcodes the server accepts: 8 to 14 digits.
bool isReportBarcode(String? b) => b != null && RegExp(r'^\d{8,14}$').hasMatch(b);

/// The exact request: barcode, source, reason, and app version, form encoded, with the app's User-Agent. Nothing else.
http.Request buildReportRequest(String barcode, String source, ReportReason reason) =>
    http.Request('POST', reportsUri)
      ..headers['User-Agent'] = appUserAgent
      ..bodyFields = {'barcode': barcode, 'source': source, 'reason': reason.key, 'app': appVersion};

class ListReports {
  static String _id(String barcode, String source) => '$barcode|$source';

  static Future<List<String>> _all() async {
    try {
      final v = jsonDecode((await SharedPreferences.getInstance()).getString(_reportedKey) ?? '[]');
      return v is List ? v.whereType<String>().toList() : [];
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isReported(String barcode, String source) async =>
      (await _all()).contains(_id(barcode, source));

  static Future<void> remember(String barcode, String source) async {
    final l = await _all()..remove(_id(barcode, source));
    l.insert(0, _id(barcode, source));
    await (await SharedPreferences.getInstance()).setString(_reportedKey, jsonEncode(l.take(maxReported).toList()));
  }

  /// Send the report. True when the server took it (and then it's remembered). Never throws; never sends a bad
  /// barcode or an unknown source.
  static Future<bool> send(String barcode, String source, ReportReason reason, {http.Client? client}) async {
    if (!isReportBarcode(barcode) || !reportSources.contains(source)) return false;
    final c = client ?? http.Client();
    try {
      final res =
          await c.send(buildReportRequest(barcode, source, reason)).then(http.Response.fromStream).timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      await remember(barcode, source);
      return true;
    } on Exception {
      return false;
    } finally {
      if (client == null) c.close();
    }
  }
}
