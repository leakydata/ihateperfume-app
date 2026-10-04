/// Sending us a product we don't know yet (docs/app-api.md, `POST /submissions`). Nothing is sent until the user
/// taps Send on the confirmation step. Photos are re-encoded on the phone first, which drops all their metadata
/// (EXIF, including location, the camera, and the time; color profiles; comments).
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'services.dart';

/// Sent as `app` with a submission. Must match the version in pubspec.yaml (a test checks).
const appVersion = '1.0.0+1';

/// The contract's limits for each photo.
const maxPhotoBytes = 2500000;
const maxPhotoSide = 2000;

/// The categories for products with no ingredient list (the finds categories, and Other).
const submitCategories = ['Trash bags', 'Laundry', 'Cleaning', 'Paper', 'Other'];

/// A photo ready to send: decoded and re-encoded as a JPEG with nothing but the pixels. Turned the right way up
/// first (the orientation tag goes with the rest), the longest side at most [maxSide], and at most [maxBytes]
/// (lower quality, then smaller, until it fits). Throws [FormatException] if [input] isn't an image.
Uint8List preparePhoto(Uint8List input, {int maxSide = maxPhotoSide, int maxBytes = maxPhotoBytes}) {
  final decoded = img.decodeImage(input);
  if (decoded == null) throw const FormatException('That file isn’t a photo the app can read.');
  final upright = img.bakeOrientation(decoded);
  var side = maxSide;
  while (true) {
    final w = upright.width, h = upright.height;
    final scaled = max(w, h) > side
        ? img.copyResize(upright,
            width: w >= h ? side : null, height: h > w ? side : null, interpolation: img.Interpolation.average)
        : upright;
    // Only the pixels go out: no EXIF (location, camera, time), no color profile, no text.
    scaled
      ..exif = img.ExifData()
      ..iccProfile = null
      ..textData = null;
    for (final q in const [85, 75, 65, 55]) {
      final out = img.encodeJpg(scaled, quality: q);
      if (out.length <= maxBytes) return out;
    }
    side = (min(side, max(w, h)) * .75).round();
  }
}

/// [preparePhoto] off the main thread (a 12-megapixel photo takes a moment).
Future<Uint8List> preparePhotoInBackground(Uint8List input) => Isolate.run(() => preparePhoto(input));

/// What the user is about to send. Exactly these fields, and nothing else, go in the request.
class Submission {
  final String? barcode;
  final String name;
  final bool fragranceFree;
  final bool unscented;
  final bool noList;
  final String? category;
  final Uint8List front;
  final Uint8List? ingredients;
  const Submission({
    this.barcode,
    this.name = '',
    this.fragranceFree = false,
    this.unscented = false,
    this.noList = false,
    this.category,
    required this.front,
    this.ingredients,
  });

  /// The barcode if it's one the server accepts (8 to 14 digits), else none.
  String? get validBarcode => barcode != null && RegExp(r'^\d{8,14}$').hasMatch(barcode!) ? barcode : null;

  String get trimmedName {
    final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return n.length > 120 ? n.substring(0, 120) : n;
  }

  /// The category, sent only for products with no ingredient list.
  String? get sentCategory => noList && submitCategories.contains(category) ? category : null;

  Map<String, String> get fields => {
        'barcode': ?validBarcode,
        if (trimmedName.isNotEmpty) 'name': trimmedName,
        'says_fragrance_free': fragranceFree ? '1' : '0',
        'says_unscented': unscented ? '1' : '0',
        'no_list': noList ? '1' : '0',
        'category': ?sentCategory,
        'app': appVersion,
      };
}

final submissionsUri = Uri.parse('$ihpApi/submissions');

/// The multipart request for [s]: its fields, the front photo, and the ingredient photo unless there's no list.
http.MultipartRequest buildSubmissionRequest(Submission s) {
  final r = http.MultipartRequest('POST', submissionsUri)
    ..headers['User-Agent'] = appUserAgent
    ..fields.addAll(s.fields)
    ..files.add(http.MultipartFile.fromBytes('front', s.front,
        filename: 'front.jpg', contentType: http.MediaType('image', 'jpeg')));
  if (s.ingredients != null && !s.noList) {
    r.files.add(http.MultipartFile.fromBytes('ingredients', s.ingredients!,
        filename: 'ingredients.jpg', contentType: http.MediaType('image', 'jpeg')));
  }
  return r;
}

/// The server's answer: a reference to quote, or a message to show.
class SubmitResult {
  final String? ref;
  final String? error;
  const SubmitResult.sent(this.ref) : error = null;
  const SubmitResult.failed(this.error) : ref = null;
  bool get ok => error == null;
}

/// Sends [s]. Never throws: any problem comes back as a plain-English [SubmitResult.error].
Future<SubmitResult> sendSubmission(Submission s, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res =
        await c.send(buildSubmissionRequest(s)).then(http.Response.fromStream).timeout(const Duration(seconds: 90));
    Map<String, dynamic>? body;
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is Map<String, dynamic>) body = j;
    } catch (_) {}
    final ref = body?['ref'];
    if ((res.statusCode == 201 || res.statusCode == 200) && body?['ok'] == true) {
      return SubmitResult.sent(ref is String && ref.isNotEmpty ? ref : null);
    }
    final msg = body?['error'];
    return SubmitResult.failed(switch (res.statusCode) {
      400 when msg is String && msg.trim().isNotEmpty => msg.trim(),
      429 => 'That’s a lot of products for one day. Please try again tomorrow.',
      413 => 'The photos are too big to send. Try taking them again.',
      _ => 'Couldn’t send it (error ${res.statusCode}). Please try again later.',
    });
  } on Exception {
    return const SubmitResult.failed('Couldn’t reach ihateperfume.com. Check your connection and try again.');
  } finally {
    if (client == null) c.close();
  }
}
