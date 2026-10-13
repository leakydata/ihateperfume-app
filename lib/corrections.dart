/// "Suggest a correction" (docs/app-api.md, `POST /corrections`): the user tells us what's wrong with a barcode's
/// listing, optionally with the corrected name or ingredient list. Sent only when they tap Send in the correction
/// sheet: the barcode, where the list came from, what they typed, and the app version. Nothing else.
library;

import 'package:http/http.dart' as http;

import 'contribute.dart' show appVersion;
import 'list_report.dart' show isReportBarcode, reportSources;
import 'services.dart';

const maxCorrectionMessage = 1000;
const maxCorrectionName = 120;
const maxCorrectionIngredients = 20000;
const _timeout = Duration(seconds: 10);

final correctionsUri = Uri.parse('$ihpApi/corrections');

/// What the user typed. [message] is required; the rest is sent only when filled in.
class Correction {
  final String message;
  final String name;
  final String ingredients;
  const Correction({required this.message, this.name = '', this.ingredients = ''});

  bool get valid => message.trim().isNotEmpty && message.trim().length <= maxCorrectionMessage;
}

/// The exact request: barcode, source, the user's text, and app version, form encoded, with the app's User-Agent.
http.Request buildCorrectionRequest(String barcode, String source, Correction c) {
  final fields = {'barcode': barcode, 'source': source, 'message': c.message.trim(), 'app': appVersion};
  if (c.name.trim().isNotEmpty) fields['name'] = c.name.trim();
  if (c.ingredients.trim().isNotEmpty) fields['ingredients'] = c.ingredients.trim();
  return http.Request('POST', correctionsUri)
    ..headers['User-Agent'] = appUserAgent
    ..bodyFields = fields;
}

/// Send it. Returns the reference ("C-XXXXX") when the server took it, null otherwise. Never throws; never sends a
/// bad barcode, an unknown source, or an empty message.
Future<String?> sendCorrection(String barcode, String source, Correction c, {http.Client? client}) async {
  if (!isReportBarcode(barcode) || !reportSources.contains(source) || !c.valid) return null;
  final cl = client ?? http.Client();
  try {
    final res = await cl.send(buildCorrectionRequest(barcode, source, c)).then(http.Response.fromStream).timeout(_timeout);
    if (res.statusCode != 201) return null;
    final m = RegExp(r'"ref"\s*:\s*"(C-[A-Z0-9]+)"').firstMatch(res.body);
    return m?.group(1) ?? '';
  } on Exception {
    return null;
  } finally {
    if (client == null) cl.close();
  }
}
