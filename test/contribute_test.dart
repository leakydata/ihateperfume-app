// Submissions: photos lose all metadata on the phone, and the request carries exactly the contract's fields
// (fake http client, no network).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:ihateperfume/contribute.dart';

/// A JPEG like a phone camera makes: EXIF with GPS location, camera make, and an orientation.
Uint8List phoneJpeg({int w = 300, int h = 200, int orientation = 1}) {
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    p
      ..r = (p.x * 255 ~/ w)
      ..g = (p.y * 255 ~/ h)
      ..b = 90;
  }
  im.exif.imageIfd.make = 'Google';
  im.exif.imageIfd.orientation = orientation;
  im.exif.gpsIfd.setGpsLocation(latitude: 40.7128, longitude: -74.0060);
  im.textData = {'Comment': 'secret'};
  return img.encodeJpg(im, quality: 95);
}

bool hasBytes(Uint8List hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// The JPEG marker segments (0xFFxx) before the image data.
List<int> markers(Uint8List jpg) {
  final out = <int>[];
  var i = 2;
  while (i + 4 <= jpg.length && jpg[i] == 0xFF) {
    final m = jpg[i + 1];
    out.add(m);
    if (m == 0xDA) break; // start of scan
    i += 2 + (jpg[i + 2] << 8 | jpg[i + 3]);
  }
  return out;
}

void main() {
  test('the test photo really has GPS EXIF to strip', () {
    final src = phoneJpeg();
    final d = img.decodeJpg(src)!;
    expect(d.exif.gpsIfd.gpsLatitude, closeTo(40.7128, 1e-3));
    expect(d.exif.imageIfd.make, 'Google');
    expect(markers(src), contains(0xE1)); // APP1 (EXIF)
    expect(hasBytes(src, ascii.encode('Exif')), isTrue);
  });

  test('preparePhoto removes all metadata, including location', () {
    final out = preparePhoto(phoneJpeg());
    final d = img.decodeJpg(out)!;
    expect(d.exif.isEmpty, isTrue);
    expect(d.exif.gpsIfd.gpsLatitude, isNull);
    expect(d.exif.imageIfd.make, isNull);
    expect(d.iccProfile, isNull);
    expect(hasBytes(out, ascii.encode('Exif')), isFalse);
    expect(hasBytes(out, ascii.encode('Google')), isFalse);
    expect(hasBytes(out, ascii.encode('secret')), isFalse);
    // Only the JFIF header, tables, frame, and scan: no APP1 (EXIF/XMP), APP2 (ICC), or COM (comment) segment.
    final m = markers(out);
    expect(m.where((x) => x == 0xE1 || x == 0xE2 || x == 0xFE || (x >= 0xE3 && x <= 0xEF)), isEmpty);
    expect(d.width, 300);
    expect(d.height, 200);
  });

  test('preparePhoto turns the photo upright before dropping the orientation tag', () {
    final d = img.decodeJpg(preparePhoto(phoneJpeg(orientation: 6)))!; // 6 = rotate 90° to view
    expect((d.width, d.height), (200, 300));
    expect(d.exif.isEmpty, isTrue);
  });

  test('preparePhoto shrinks the longest side to 2000 px and fits the size limit', () {
    final big = phoneJpeg(w: 3000, h: 1500);
    final d = img.decodeJpg(preparePhoto(big))!;
    expect((d.width, d.height), (2000, 1000));
    // A tight byte limit makes it lower the quality and then the size until it fits.
    final small = preparePhoto(big, maxBytes: 20000);
    expect(small.length, lessThanOrEqualTo(20000));
    expect(img.decodeJpg(small)!.exif.isEmpty, isTrue);
  });

  test('preparePhoto rejects what isn’t an image', () {
    expect(() => preparePhoto(Uint8List.fromList(utf8.encode('not a photo'))), throwsFormatException);
  });

  final front = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);
  final list = Uint8List.fromList([0xFF, 0xD8, 4, 5, 6, 0xFF, 0xD9]);

  test('the request has exactly the contract’s fields', () {
    final r = buildSubmissionRequest(Submission(
        barcode: '0123456789012',
        name: '  Brand   Kitchen Bags ',
        fragranceFree: true,
        front: front,
        ingredients: list,
        category: 'Laundry')); // ignored: it has a list
    expect(r.method, 'POST');
    expect(r.url.toString(), 'https://ihateperfume.com/wp-json/ihp-app/v1/submissions');
    expect(r.fields, {
      'barcode': '0123456789012',
      'name': 'Brand Kitchen Bags',
      'says_fragrance_free': '1',
      'says_unscented': '0',
      'no_list': '0',
      'app': appVersion,
    });
    expect(r.files.map((f) => (f.field, f.filename, f.contentType.mimeType)), [
      ('front', 'front.jpg', 'image/jpeg'),
      ('ingredients', 'ingredients.jpg', 'image/jpeg'),
    ]);
    expect(r.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cookie')));
  });

  test('no list: no ingredient photo, the category goes, a bad barcode doesn’t, long names are cut', () {
    final r = buildSubmissionRequest(Submission(
        barcode: '12ab',
        name: 'x' * 200,
        unscented: true,
        noList: true,
        category: 'Trash bags',
        front: front,
        ingredients: list));
    expect(r.fields['barcode'], isNull);
    expect(r.fields['name']!.length, 120);
    expect(r.fields['no_list'], '1');
    expect(r.fields['says_unscented'], '1');
    expect(r.fields['category'], 'Trash bags');
    expect(r.files.map((f) => f.field), ['front']);
    // An unknown category isn't sent.
    expect(buildSubmissionRequest(Submission(noList: true, category: 'Cars', front: front)).fields['category'],
        isNull);
  });

  test('the multipart body that goes out', () async {
    late http.Request sent;
    final c = MockClient((req) async {
      sent = req;
      return http.Response('{"ok": true, "ref": "S-7F3K2"}', 201);
    });
    final r = await sendSubmission(Submission(barcode: '12345678', front: front, ingredients: list), client: c);
    expect(r.ok, isTrue);
    expect(r.ref, 'S-7F3K2');
    expect(sent.headers['content-type'], startsWith('multipart/form-data; boundary='));
    expect(sent.headers['User-Agent'], 'IHatePerfume-Android/1.0 (https://ihateperfume.com)');
    final body = latin1.decode(sent.bodyBytes);
    final names = RegExp(r'; name="([^"]+)"').allMatches(body).map((m) => m[1]).toList();
    expect(names, ['barcode', 'says_fragrance_free', 'says_unscented', 'no_list', 'app', 'front', 'ingredients']);
    expect(body, contains('filename="front.jpg"'));
  });

  test('server answers become messages', () async {
    Future<SubmitResult> answer(int code, String body) =>
        sendSubmission(Submission(front: front, noList: true), client: MockClient((_) async => http.Response(body, code)));
    expect((await answer(400, '{"ok": false, "error": "The front photo is missing."}')).error,
        'The front photo is missing.');
    expect((await answer(429, '')).error, contains('tomorrow'));
    expect((await answer(413, '')).error, contains('too big'));
    expect((await answer(500, '<html>')).error, contains('error 500'));
    final down = await sendSubmission(Submission(front: front, noList: true),
        client: MockClient((_) async => throw const SocketException('offline')));
    expect(down.ok, isFalse);
    expect(down.error, contains('Check your connection'));
  });

  test('the version sent matches pubspec.yaml', () {
    final v = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())![1];
    expect(appVersion, v);
  });
}
