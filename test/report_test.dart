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

  test('cleanOcr finds a misread heading', () {
    for (final h in ['IMGREDIENTS:', 'INGREDlENTS;', 'lNGREDIENTS:', '1NGREDIENTS.', 'INGREDIENTES:', 'Ingrédients :',
      'Ingredient:', 'INCI:']) {
      expect(cleanOcr('Gentle wash. Use daily\n$h Water, Parfum'), 'Water, Parfum', reason: h);
    }
    expect(cleanOcr('Directions: Use daily, rinse. Water, Parfum'), 'Directions: Use daily, rinse. Water, Parfum');
  });

  test('cleanOcr ends the list at label text even with no period before it', () {
    expect(cleanOcr('Ingredients: Water, Glycerin, Parfum Made in USA'), 'Water, Glycerin, Parfum');
    expect(cleanOcr('Ingredients: Water, Glycerin www.example.com'), 'Water, Glycerin');
    expect(cleanOcr('Ingredients: Water, Glycerin Questions? 1-800-555-1234'), 'Water, Glycerin');
    expect(cleanOcr('Ingredients: Water, Glycerin Dist. by Example, Dallas, TX 75201'), 'Water, Glycerin');
    expect(cleanOcr('Ingredients: Water, Glycerin, Parfum 0123456789'), 'Water, Glycerin, Parfum');
    expect(cleanOcr('Water\nGlycerin\nParfum\nMade in USA'), 'Water\nGlycerin\nParfum');
    // Never inside the first item.
    expect(cleanOcr('Ingredients: Water Distributed by X, Glycerin'), 'Water Distributed by X, Glycerin');
    // A color index number is not a zip code.
    expect(cleanOcr('Ingredients: Water, Mica, CI 77891, Parfum'), 'Water, Mica, CI 77891, Parfum');
  });

  test('cleanOcr on a real phone scan: starts at the first ingredient, drops the footer', () {
    final t = cleanOcr(File('test/fixtures/ocr-cetaphil-body-wash.txt').readAsStringSync());
    expect(t, startsWith('WATER, GLYCERIN, SODIUM LAURETH SULFATE'));
    expect(t, endsWith('POLYQUATERNIUM-10, SODUM HYDROKDE'));
  });
}
