import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ihateperfume/corrections.dart';

void main() {
  test('the request sends only barcode, source, message, filled-in fields, and app version', () {
    final r = buildCorrectionRequest('037000811244', 'ihp', const Correction(message: ' Wrong size ', name: ''));
    expect(r.method, 'POST');
    expect(r.url.path, endsWith('/corrections'));
    expect(r.bodyFields.keys.toSet(), {'barcode', 'source', 'message', 'app'});
    expect(r.bodyFields['message'], 'Wrong size');
    final full = buildCorrectionRequest('037000811244', 'obf',
        const Correction(message: 'List is old', name: 'Crest Mouthwash', ingredients: 'Water, Glycerin'));
    expect(full.bodyFields.keys.toSet(), {'barcode', 'source', 'message', 'name', 'ingredients', 'app'});
  });

  test('never sends an empty message, a bad barcode, or an unknown source', () async {
    var calls = 0;
    final c = MockClient((_) async {
      calls++;
      return http.Response('{"ok":true,"ref":"C-AB123"}', 201);
    });
    expect(await sendCorrection('037000811244', 'ihp', const Correction(message: '  '), client: c), isNull);
    expect(await sendCorrection('12', 'ihp', const Correction(message: 'x'), client: c), isNull);
    expect(await sendCorrection('037000811244', 'walmart', const Correction(message: 'x'), client: c), isNull);
    expect(calls, 0);
    expect(await sendCorrection('037000811244', 'ihp', const Correction(message: 'x'), client: c), 'C-AB123');
  });

  test('a refused or failed request returns null', () async {
    final c = MockClient((_) async => http.Response('{"ok":false}', 429));
    expect(await sendCorrection('037000811244', 'fda', const Correction(message: 'x'), client: c), isNull);
  });
}
