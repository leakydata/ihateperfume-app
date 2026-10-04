// The spelling index built in another isolate from the loaded decoder gives the same results as one built in
// place, in compact arrays. Memory before and after: tool/memory_bench.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ihateperfume/engine/decoder.dart';
import 'package:ihateperfume/engine/ocr_fix.dart';

void main() {
  final decoder = Decoder.fromJson(File('assets/data/decoder.json').readAsStringSync(),
      File('assets/data/decoder-data.json').readAsStringSync(), File('assets/data/inci-vocab.json').readAsStringSync());

  test('built in another isolate: same issues and suggestions as built in place', () async {
    final here = OcrFix(decoder);
    final there = await OcrFix.build(decoder);
    final cases = [
      ...(jsonDecode(File('test/parity/cases.json').readAsStringSync()) as List).cast<String>(),
      'Water, Lim0nene, Methylparabn, Citric Acid, Sodium Laureth Sulfale, Parfurn, GLYCERlN, LINAL00L',
      'Aqua (Watre), Parfum/Fragrence, Glycerin Parfum, Sodium Hydroxide 0299393816 Galderma Distributed by: X',
    ];
    for (final t in cases) {
      expect(there.check(t).map((i) => '$i ${i.start}-${i.end}').toList(),
          here.check(t).map((i) => '$i ${i.start}-${i.end}').toList(),
          reason: t);
    }
    expect(there.isKnown('limonene'), isTrue);
    expect(there.isKnown('fragrance'), isTrue);
    expect(there.isKnown(''), isFalse);
    expect(there.pretty('peg 40 hydrogenated castor oil'), 'PEG-40 Hydrogenated Castor Oil');
  });

  test('the index is compact', () async {
    final fix = await OcrFix.build(decoder);
    // The trigram postings at 2 bytes each in one array, plus the offsets: about 2 MB.
    expect(fix.arrayBytes, lessThan(3 << 20));
    final text = List.filled(3, 'Water, Lim0nene, Methylparabn, Citric Acid, Sodium Laureth Sulfale, Parfurn, Glycerin, '
            'Cetearyl Alcohoi, Xanthan Gurn, Panthenoi')
        .join(', ');
    fix.suggest(text);
    final sw = Stopwatch()..start();
    fix.suggest(text);
    expect(sw.elapsedMilliseconds, lessThan(50));
  });
}
