// TERMS.md and PRIVACY.md must say exactly what the app's legal screens say (lib/screens/legal.dart).
// After editing the Dart text, regenerate the files with:
//   UPDATE_LEGAL=1 flutter test test/legal_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ihateperfume/screens/legal.dart';

const draft = '**Draft — not yet reviewed by a lawyer.**\n\n';

String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  for (final (file, doc) in [('TERMS.md', termsDoc), ('PRIVACY.md', privacyDoc)]) {
    test('$file matches the in-app text', () {
      final f = File(file);
      final want = draft + legalMarkdown(doc);
      if (Platform.environment['UPDATE_LEGAL'] == '1') f.writeAsStringSync(want);
      final have = f.readAsStringSync();
      // Paragraph by paragraph, so a failure names the one that drifted.
      final a = have.split(RegExp(r'\n\s*\n')).map(norm).where((x) => x.isNotEmpty).toList();
      final b = want.split(RegExp(r'\n\s*\n')).map(norm).where((x) => x.isNotEmpty).toList();
      for (final x in b) {
        expect(a, contains(x), reason: 'In the app but not in $file');
      }
      for (final x in a) {
        expect(b, contains(x), reason: 'In $file but not in the app');
      }
      expect(a, b, reason: 'Same paragraphs, different order');
    });
  }

  test('key sentences are in the documents', () {
    final terms = norm(File('TERMS.md').readAsStringSync());
    final privacy = norm(File('PRIVACY.md').readAsStringSync());
    for (final s in [
      'not yet reviewed by a lawyer',
      'It is not medical advice and not a diagnosis',
      'call 911 or your local emergency number',
      'never says a product is “safe,”',
      'Always read the actual package',
      'THERE IS NO WARRANTY FOR THE PROGRAM',
      'Open Database License (ODbL)',
    ]) {
      expect(terms, contains(s));
    }
    for (final s in [
      'not yet reviewed by a lawyer',
      'We don’t collect any personal information.',
      'Only a barcode number is sent to look the product up, unless you choose to send us a product.',
      'We never store your IP address.',
      'Location and all other photo details are removed on your phone before anything is sent',
      'https://world.openbeautyfacts.org/privacy',
      'left out of Android backups and device-to-device transfers',
      'No analytics, no ads, no crash reporting, no accounts, and no tracking.',
    ]) {
      expect(privacy, contains(s));
    }
  });
}
