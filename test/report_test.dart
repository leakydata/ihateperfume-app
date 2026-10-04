// The screens' wording: the verdict line must read exactly like the website's, and every flag must name a source.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ihateperfume/engine/decoder.dart';
import 'package:ihateperfume/report.dart';
import 'package:ihateperfume/services.dart';

void main() {
  final decoder = Decoder.fromJson(File('assets/data/decoder.json').readAsStringSync(),
      File('assets/data/decoder-data.json').readAsStringSync(), File('assets/data/inci-vocab.json').readAsStringSync());
  final cases = (jsonDecode(File('test/parity/cases.json').readAsStringSync()) as List).cast<String>();
  final site = jsonDecode(File('test/parity/site_results.json').readAsStringSync()) as List;

  for (var i = 0; i < cases.length; i++) {
    test('case $i: verdict line matches the website, every flag has a source', () {
      final r = Report.build(decoder, cases[i]);
      expect(r.verdictLine, (site[i] as Map)['verdictText']);
      for (final row in r.rows) {
        for (final reason in row.reasons) {
          expect(reason.source, isNotEmpty, reason: '${row.item}: ${reason.title}');
        }
      }
      // Every item is either flagged or counted as unflagged.
      expect(r.rows.length + r.unflagged.length, r.result.items.toSet().length);
    });
  }

  test('fragrance on the label is red, with the hidden-mixture line', () {
    final r = Report.build(decoder, 'Water, Glycerin, Fragrance');
    expect(r.boxLevel, 3);
    expect(r.declared, 'Fragrance');
    expect(r.headline, '1 scent ingredient');
  });

  test('nothing found never says safe', () {
    final r = Report.build(decoder, 'Water, Glycerin');
    expect(r.headline.toLowerCase(), isNot(contains('safe')));
    expect(r.verdictLine, contains('not a guarantee'));
  });

  test('cleanOcr starts at "Ingredients:" and joins wrapped lines', () {
    expect(cleanOcr('Gentle wash\nINGREDIENTS: Water, Sodium Laureth\nSulfate, Methylisothia-\nzolinone, Parfum.'),
        'Water, Sodium Laureth Sulfate, Methylisothiazolinone, Parfum.');
    expect(cleanOcr('Water\nGlycerin\nParfum'), 'Water\nGlycerin\nParfum');
    // Read from a test label photo on the phone: the footer must not stick to the last ingredient.
    expect(cleanOcr('Directions: Apply to damp skin, rinse well.\nINGREDIENTS: Water, Glycerin, Lavandula '
            'Angustifolia Oil.\nMade in USA. Distributed by Example Co.'),
        'Water, Glycerin, Lavandula Angustifolia Oil.');
    expect(cleanOcr('Ingredients: Water, Parfum. Avoid contact with eyes'), 'Water, Parfum.');
    expect(cleanOcr('Ingredients: Alcohol Denat., Parfum, Aqua.'), 'Alcohol Denat., Parfum, Aqua.');
  });
}
