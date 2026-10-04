// Spelling suggestions for misread ingredient lists: fix real text recognition mistakes, leave real names alone.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ihateperfume/engine/decoder.dart';
import 'package:ihateperfume/engine/ocr_fix.dart';
import 'package:ihateperfume/screens/review.dart';
import 'package:ihateperfume/services.dart';

void main() {
  final decoder = Decoder.fromJson(File('assets/data/decoder.json').readAsStringSync(),
      File('assets/data/decoder-data.json').readAsStringSync(), File('assets/data/inci-vocab.json').readAsStringSync());
  final fix = OcrFix(decoder);

  /// item as written -> suggested replacement, for every suggestion in [text].
  Map<String, String> sug(String text) => {for (final s in fix.suggest(text)) s.from: s.to};

  test('item spans match Decoder.split', () {
    final cases = (jsonDecode(File('test/parity/cases.json').readAsStringSync()) as List).cast<String>();
    for (final t in [
      ...cases,
      'INGREDIENTS: Aqua; Glycerin.\n• Parfum*, , Limonene. ',
      '  inci : Water | Alcohol Denat.**  ',
    ]) {
      expect([for (final (s, e) in OcrFix.spans(t)) t.substring(s, e)], Decoder.split(t), reason: t);
    }
  });

  test('common text recognition mistakes get the real name', () {
    expect(sug('Water, Lim0nene, Methylparabn, Citric Acid, Sodium Laureth Sulfale, Parfurn'), {
      'Lim0nene': 'Limonene',
      'Methylparabn': 'Methylparaben',
      'Sodium Laureth Sulfale': 'Sodium Laureth Sulfate',
      'Parfurn': 'Parfum',
    });
    expect(
        sug('Cetearyl Alcohoi, Xanthan Gurn, Panthenoi, Sodiurn Benzoate, Benzyl Alc0hol, Cocamidopropyl Betain'), {
      'Cetearyl Alcohoi': 'Cetearyl Alcohol',
      'Xanthan Gurn': 'Xanthan Gum',
      'Panthenoi': 'Panthenol',
      'Sodiurn Benzoate': 'Sodium Benzoate',
      'Benzyl Alc0hol': 'Benzyl Alcohol',
      'Cocamidopropyl Betain': 'Cocamidopropyl Betaine',
    });
  });

  test('keeps the label style: caps stay caps, lowercase stays lowercase', () {
    expect(sug('AQUA, GLYCERlN, LINAL00L, CITRONELLOL'), {'GLYCERlN': 'GLYCERIN', 'LINAL00L': 'LINALOOL'});
    expect(sug('water, lim0nene'), {'lim0nene': 'limonene'});
  });

  test('parts in parentheses or after a slash are checked on their own', () {
    expect(sug('Aqua (Watre), Parfum/Fragrence'), {'Watre': 'Water', 'Fragrence': 'Fragrance'});
  });

  test('a missing comma between two known names', () {
    expect(sug('Water, Glycerin Parfum, Limonene'), {'Glycerin Parfum': 'Glycerin, Parfum'});
  });

  test('real names are never changed', () {
    // Citric Acid, Glycerin, a real unflagged ingredient, synonyms in parentheses, numbers, and plurals.
    expect(
        sug('Citric Acid, Glycerin, Butyrospermum Parkii Butter, Simmondsia Chinensis Seed Oil, Aqua (Water), '
            'Fragrance (Parfum), CI 77891, Glycerin 2%, PEG-40 Hydrogenated Castor Oil, Enzymes, Fragrance, Perfume'),
        isEmpty);
    // Every parity case except the one with deliberate misspellings.
    final cases = (jsonDecode(File('test/parity/cases.json').readAsStringSync()) as List).cast<String>();
    for (var i = 0; i < cases.length; i++) {
      expect(sug(cases[i]).keys, i == 2 ? ['Lim0nene', 'Methylparabn'] : isEmpty, reason: cases[i]);
    }
  });

  test('no guessing: a different number or an unknown word gets no suggestion', () {
    expect(sug('PEG-45 Hydrogenated Castor Oil, Optical Brightener, Colorant, Zq, 1234'), isEmpty);
  });

  test('apply replaces only the item, and only if the text still matches', () {
    const t = 'Water, Lim0nene, Parfurn';
    final s = fix.suggest(t);
    expect(OcrFix.apply(t, s.first), 'Water, Limonene, Parfurn');
    expect(OcrFix.applyAll(t, s), 'Water, Limonene, Parfum');
    expect(OcrFix.apply('Water, Lemon, Parfurn', s.first), 'Water, Lemon, Parfurn');
    expect(decoder.decode(OcrFix.applyAll(t, s)).items, ['Water', 'Limonene', 'Parfum']);
  });

  test('weighted distance: OCR confusions are cheap, other edits cost one', () {
    expect(OcrFix.wdist('lim0nene', 'limonene'), closeTo(.3, 1e-9));
    expect(OcrFix.wdist('parfurn', 'parfum'), closeTo(.3, 1e-9));
    expect(OcrFix.wdist('parfm', 'parfum'), 1);
    expect(OcrFix.wdist('parfmu', 'parfum'), 1); // transposition
    expect(OcrFix.wdist('peg 45', 'peg 40'), greaterThan(2));
  });

  /// "kind: from -> to" for every issue in [text].
  List<String> issues(String text) => [for (final i in fix.check(text)) '$i'];

  test('a real phone scan (Cetaphil body wash): every misread item gets the right fix', () {
    final text = cleanOcr(File('test/fixtures/ocr-cetaphil-body-wash.txt').readAsStringSync());
    expect(issues(text), [
      'suggestion: DIG0DIM m AURETH SULFOSUCCINATE -> DISODIUM LAURETH SULFOSUCCINATE',
      'suggestion: PANTHENOL [VITANMIN 85] GLYCOL DISTEARATE -> PANTHENOL [VITANMIN 85], GLYCOL DISTEARATE',
      'suggestion: ACRYLATES/CI0-30 ALKYL ACRYLATE CROSSPOLYMER -> ACRYLATES/C10-30 ALKYL ACRYLATE CROSSPOLYMER',
      'suggestion: SODUM HYDROKDE -> SODIUM HYDROXIDE',
    ]);
    // After the fixes, the misread common name in brackets is left for the user ("Vitamin B5" isn't a known name).
    final fixed = OcrFix.applyAll(text, fix.suggest(text));
    expect(issues(fixed), ['unknown: VITANMIN 85']);
    final clean = OcrFix.removeAll(fixed, fix.check(fixed));
    expect(clean, contains('ALOE BARBADENSIS LEAF JUICE POWDER, PANTHENOL, GLYCOL DISTEARATE, LAURYL LACTATE'));
    expect(fix.check(clean), isEmpty);
    expect(decoder.decode(clean).items.last, 'SODIUM HYDROXIDE');
  });

  test('the same scan without cleanup: directions and the footer are label text', () {
    final raw = File('test/fixtures/ocr-cetaphil-body-wash.txt').readAsStringSync();
    final all = fix.check(raw);
    final label = [for (final i in all) if (i.kind == IssueKind.labelText) i.from];
    expect(label, [
      'ECTIONS: Apply a liberal to moistened hands',
      'pouf or oth. Massage gently ito a Rinse and pat dry. For ideal re',
      '0299393816 GALDERMA Distributed by: Galderna laborsturies',
      'L2. Dallas',
      'TX 75201 USA All trademarks are the praperty of their respective owners Made in Germany Cetaphil.com P202418-0',
    ]);
    // A footer glued to a misread name: the name gets its fix, the rest is label text.
    expect(issues('Water, SODUM HYDROKDE 0299393816 GALDERMA Distributed by: Galderna'), [
      'suggestion: SODUM HYDROKDE -> SODIUM HYDROXIDE',
      'labelText: 0299393816 GALDERMA Distributed by: Galderna',
    ]);
  });

  test('a second scan of the same label: a missing comma before a slashed name, a barcode read with gaps', () {
    final text = File('test/fixtures/ocr-cetaphil-body-wash-2.txt').readAsStringSync();
    expect(issues(text), [
      'suggestion: LAURYL LACTATE ACRYLATES/CIO-30 ALKYL ACRYLATE CROSSPOLYMER -> '
          'LAURYL LACTATE, ACRYLATES/C10-30 ALKYL ACRYLATE CROSSPOLYMER',
      'unknown: SODIUM OCTRATE', // citrate or nitrate? No guessing.
      'labelText: 3 02993"93816 GALDERMA Distributed by: Galderma laboratories',
      'labelText: LL2 Dallas',
      'labelText: TX 75201 USA All trademarks are the property of their respective ewners Made in Germany '
          'cetaghil.oonm P202418-0',
    ]);
    final fixed = OcrFix.applyAll(text, fix.suggest(text));
    final clean = OcrFix.removeAll(fixed, [for (final i in fix.check(fixed)) if (i.kind == IssueKind.labelText) i]);
    expect(clean, contains('GLYCOL DISTEARATE, LAURYL LACTATE, ACRYLATES/C10-30 ALKYL ACRYLATE CROSSPOLYMER, CITRIC'));
    expect(issues(clean), ['unknown: SODIUM OCTRATE']);
    expect(decoder.decode(clean).items.last, 'SODIUM HYDROXIDE');
    // After the app's own cleanup (which cuts at "Distributed"), the barcode is still split off the name.
    expect(issues(cleanOcr(text)).last, 'labelText: 3 02993"93816 GALDERMA');
    // The same split with no slash; a one-word misread tail is left alone.
    expect(sug('Water, Lauryl Lactate Cetearyl Alcohoi'),
        {'Lauryl Lactate Cetearyl Alcohoi': 'Lauryl Lactate, Cetearyl Alcohol'});
    expect(issues('Water, Sodium Octrate'), ['unknown: Sodium Octrate']);
  });

  test('label text: addresses, numbers, codes, web addresses, companies, directions', () {
    expect(
        issues('Water, P500, 0299393816, Distributed by Example Co., Dallas, TX 75201, www.example.com, '
            'help@example.com, 1-800-555-1234, Example Laboratories, Apply to wet skin and rinse well, '
            'All trademarks are the property of their respective owners'),
        [
          'labelText: P500',
          'labelText: 0299393816',
          'labelText: Distributed by Example Co',
          'labelText: Dallas',
          'labelText: TX 75201',
          'labelText: www.example.com',
          'labelText: help@example.com',
          'labelText: 1-800-555-1234',
          'labelText: Example Laboratories',
          'labelText: Apply to wet skin and rinse well',
          'labelText: All trademarks are the property of their respective owners',
        ]);
    // An item with a known ingredient name in it is never label text.
    expect(issues('Rinse with Water, Sodium Hydroxide 0299393816'), [
      'unknown: Rinse with Water',
      'labelText: 0299393816',
    ]);
  });

  test('unknown: not a known name and no confident fix', () {
    expect(issues('Water, Optical Brightener, Zq, E330, Vitamin E, CI 77891, Glycerin 2%, Masking Fragrance'), [
      'unknown: Optical Brightener',
      'unknown: Zq',
      'unknown: E330',
      'unknown: Vitamin E',
    ]);
    // Common names in brackets after a known name are fine; parts of a known name are fine.
    expect(issues('Panthenol (Vitamin B5), Rosa Damascena (Rose) Flower Oil, Butyrospermum Parkii (Shea) Butter'),
        isEmpty);
    expect(issues('Tocopherol (Vitamin E) Glycerin'),
        ['suggestion: Tocopherol (Vitamin E) Glycerin -> Tocopherol (Vitamin E), Glycerin']);
  });

  test('removeAll takes the item and one separator, and skips text that changed', () {
    const t = 'Water, P500, Glycerin, Zq.';
    final all = fix.check(t);
    expect(all.map((i) => i.from), ['P500', 'Zq']);
    expect(OcrFix.removeAll(t, all), 'Water, Glycerin.');
    expect(OcrFix.removeAll(t, [all.first]), 'Water, Glycerin, Zq.');
    expect(OcrFix.removeAll('P500, Water', fix.check('P500, Water')), 'Water');
    expect(OcrFix.removeAll('Water, P501, Glycerin', all), 'Water, P501, Glycerin');
    const glued = 'Water, Sodium Hydroxide 0299393816 Galderma Distributed by: X';
    expect(OcrFix.removeAll(glued, fix.check(glued)), 'Water, Sodium Hydroxide');
    const bracket = 'Panthenol [Vitanmin 85], Glycerin';
    expect(OcrFix.removeAll(bracket, fix.check(bracket)), 'Panthenol, Glycerin');
    const lines = 'Water\nP500\nGlycerin';
    expect(OcrFix.removeAll(lines, fix.check(lines)), 'Water\nGlycerin');
  });

  test('a 30-item list takes well under 200 ms', () {
    const items = [
      'Aqua', 'Sodium Laureth Sulfale', 'Cocamidopropyl Betain', 'Glycerin', 'Parfurn', 'Lim0nene', 'Linal00l',
      'Citric Acid', 'Sodium Chloride', 'Methylparabn', 'Propylparaben', 'Tocopheryl Acetate', 'Panthenoi',
      'Xanthan Gurn', 'Cetearyl Alcohoi', 'Dimethicone', 'Hexyl Cinnamal', 'Benzyl Alc0hol', 'Phenoxyethanol',
      'Ethylhexylglycerin', 'Sodiurn Benzoate', 'Potassium Sorbate', 'Disodium EDTA', 'Polyquaternium-10',
      'Guar Hydroxypropyltrimonium Chloride', 'Citronell0l', 'Geraniol', 'Coumarin', 'Butylphenyl Methylpropional',
      'CI 19140',
    ];
    final text = items.join(', ');
    final sw = Stopwatch()..start();
    final cold = fix.suggest(text);
    final coldMs = sw.elapsedMicroseconds / 1000;
    sw.reset();
    fix.suggest(text);
    final warmMs = sw.elapsedMicroseconds / 1000;
    // ignore: avoid_print
    print('30 items: ${coldMs.toStringAsFixed(1)} ms first run, ${warmMs.toStringAsFixed(1)} ms after');
    expect(cold.length, greaterThanOrEqualTo(10));
    expect(coldMs, lessThan(200));
  });

  testWidgets('review screen lists suggestions and uses one on a tap', (tester) async {
    spelling = Future.value(fix);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ReviewScreen(text: 'Water, Lim0nene, Parfurn', kind: ReviewKind.photo)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2 ITEMS TO CHECK'), findsOneWidget);
    expect(find.text('PROBABLY MISREAD'), findsOneWidget);
    expect(find.text('Limonene'), findsOneWidget);
    await tester.tap(find.byKey(const Key('use-7')));
    await tester.pump(const Duration(milliseconds: 400));
    final field = tester.widget<TextField>(find.byKey(const Key('ingredients')));
    expect(field.controller!.text, 'Water, Limonene, Parfurn');
    expect(find.byKey(const Key('use-all')), findsNothing); // one left
    await tester.tap(find.text('USE IT'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(field.controller!.text, 'Water, Limonene, Parfum');
    expect(find.textContaining('TO CHECK'), findsNothing);
  });

  testWidgets('unrecognized items can be edited; label text can be removed', (tester) async {
    spelling = Future.value(fix);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    const text = 'Water, Qwzxv Blorp, Glycerin, Distributed by: Example Labs, Dallas, TX 75201';
    await tester.pumpWidget(const MaterialApp(home: ReviewScreen(text: text, kind: ReviewKind.photo)));
    await tester.pump(const Duration(milliseconds: 400));
    final field = tester.widget<TextField>(find.byKey(const Key('ingredients')));
    // Not recognized: Edit selects it in the box and changes nothing.
    expect(find.text('Qwzxv Blorp'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('edit-7')));
    await tester.tap(find.byKey(const Key('edit-7')));
    await tester.pump();
    expect(field.controller!.text, text);
    expect(field.controller!.selection.textInside(text), 'Qwzxv Blorp');
    // Label text: Remove all takes out the footer and leaves the ingredients.
    expect(find.byKey(const Key('remove-all')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('remove-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-all')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(field.controller!.text, 'Water, Qwzxv Blorp, Glycerin');
  });
}
