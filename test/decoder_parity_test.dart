// The app's decoder must give the same answers as the website's. Ground truth: test/parity/site_results.json,
// produced by running test/parity/cases.json through the live ihateperfume.com decoder (site_results.js).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ihateperfume/engine/decoder.dart';

void main() {
  final decoder = Decoder.fromJson(File('assets/data/decoder.json').readAsStringSync(),
      File('assets/data/decoder-data.json').readAsStringSync(), File('assets/data/inci-vocab.json').readAsStringSync());
  final cases = (jsonDecode(File('test/parity/cases.json').readAsStringSync()) as List).cast<String>();
  final site = jsonDecode(File('test/parity/site_results.json').readAsStringSync()) as List;

  for (var i = 0; i < cases.length; i++) {
    test('case $i matches the website', () {
      final want = site[i] as Map<String, dynamic>;
      final r = decoder.decode(cases[i]);
      expect(r.verdict.name, want['verdict'], reason: 'verdict');
      expect(r.fragrance.map((f) => f.item).toList(), want['fragrance'], reason: 'fragrance declared');
      expect(r.allergens.map((a) => a.item).toList(), want['allergens'], reason: 'named allergens');
      expect(r.plantOils, want['plantOils'], reason: 'plant oils');
      final shown = decoder.shown(r);
      final wantFlags = (want['flags'] as List).cast<Map<String, dynamic>>();
      expect(shown.map((x) => x.item).toList(), wantFlags.map((f) => f['item']).toList(), reason: 'flag list order');
      for (var j = 0; j < shown.length; j++) {
        final cats = <String>[];
        for (final f in shown[j].flags) {
          if (!cats.contains(f.cat)) cats.add(f.cat);
        }
        cats.sort((a, b) => decoder.cat(b).level - decoder.cat(a).level);
        expect(cats.map((c) => decoder.cat(c).short).toList(), wantFlags[j]['chips'], reason: 'chips for ${shown[j].item}');
        final g = wantFlags[j]['guess'] as String?;
        expect(shown[j].guess, g == null ? null : RegExp('“(.+)”').firstMatch(g)!.group(1), reason: 'typo guess');
      }
    });
  }
}
