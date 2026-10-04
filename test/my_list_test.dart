// "My list": matching a label against the user's own ingredients, groups, and words, and keeping the list.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ihateperfume/engine/decoder.dart';
import 'package:ihateperfume/my_list.dart';
import 'package:ihateperfume/report.dart';
import 'package:ihateperfume/screens/my_list.dart';
import 'package:ihateperfume/screens/result.dart';
import 'package:ihateperfume/services.dart' as services;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final d = Decoder.fromJson(File('assets/data/decoder.json').readAsStringSync(),
      File('assets/data/decoder-data.json').readAsStringSync(), File('assets/data/inci-vocab.json').readAsStringSync());
  services.decoder = d;

  ListEntry ing(String n, [Reaction r = Reaction.allergic]) => ListEntry(EntryKind.ingredient, n, r);
  ListCheck check(String label, List<ListEntry> list) => checkList(d, Report.build(d, label), list);

  group('ingredient', () {
    test('same name', () {
      final c = check('Water, Linalool, Glycerin', [ing('Linalool')]);
      expect(c.hits, hasLength(1));
      expect(c.hits.first.items, ['Linalool']);
      expect(c.hits.first.how, 'Same ingredient');
      expect(c.level, 3);
    });

    test('a synonym in the decoder data (HHCB is Hexamethylindanopyran)', () {
      expect(d.itemIndex('hhcb'), d.itemIndex('hexamethylindanopyran'));
      final c = check('Water, HHCB', [ing('Hexamethylindanopyran')]);
      expect(c.hits.single.items, ['HHCB']);
      expect(c.hits.single.how, 'Listed as “HHCB”');
    });

    test('parfum, fragrance, and perfume are the same declared mixture', () {
      expect(check('Water, Fragrance', [ing('Parfum')]).hits.single.how, 'Listed as “Fragrance”');
      expect(check('Water, Perfume', [ing('Fragrance')]).hits.single.items, ['Perfume']);
    });

    test('inside parentheses, like the decoder', () {
      final c = check('Water, Parfum (Fragrance), Glycerin', [ing('Fragrance')]);
      expect(c.hits.single.items, ['Parfum (Fragrance)']);
      expect(c.hits.single.how, 'Listed as “Parfum (Fragrance)”');
      expect(check('Aqua (Water), Linalool (from lavender)', [ing('Linalool')]).hits.single.items,
          ['Linalool (from lavender)']);
    });

    test('a misspelling read as the ingredient', () {
      final c = check('Water, Linalol, Glycerin', [ing('Linalool')]);
      expect(c.hits.single.items, ['Linalol']);
      expect(c.hits.single.how, 'Read as “Linalool” from “Linalol”');
    });

    test('no match', () {
      final c = check('Water, Glycerin', [ing('Linalool')]);
      expect(c.hits, isEmpty);
      expect(c.maybeHidden, isEmpty); // no fragrance declared
      expect(c.level, 0);
    });

    test('ingredientEntryFor finds the entry for an ingredient screen', () {
      final list = [ing('Fragrance', Reaction.irritates), ing('Linalool')];
      expect(ingredientEntryFor(d, list, 'Parfum')?.value, 'Fragrance');
      expect(ingredientEntryFor(d, list, 'Linalol', guess: 'Linalool')?.value, 'Linalool');
      expect(ingredientEntryFor(d, list, 'Glycerin'), isNull);
    });
  });

  group('groups and words', () {
    test('a decoder category', () {
      final c = check('Water, Linalool, Glycerin', [const ListEntry(EntryKind.group, 'cat:skin-sensitizer', Reaction.avoid)]);
      expect(c.hits.single.items, ['Linalool']);
      expect(c.hits.single.how, 'In group “${d.cat('skin-sensitizer').short}”');
      expect(c.level, 2);
    });

    test('fragrance, EU allergen, and plant oil groups', () {
      const label = 'Water, Parfum, Linalool, Rosmarinus Officinalis Leaf Oil';
      ListHit? hit(String id) =>
          check(label, [ListEntry(EntryKind.group, id, Reaction.tellMe)]).hits.firstOrNull;
      expect(hit('fragrance')!.items, ['Parfum']);
      expect(hit('allergen')!.items, contains('Linalool'));
      final r = Report.build(d, label).result;
      expect(r.plantOils, isNotEmpty);
      expect(hit('plant-oil')!.items, r.plantOils);
      expect(listGroups(d).map((g) => g.$1), containsAll(['fragrance', 'allergen', 'plant-oil', 'cat:pfas']));
      expect(groupLabel(d, 'cat:formaldehyde'), d.cat('formaldehyde').short);
    });

    test('name contains a word (normalized, at least 3 letters)', () {
      const label = 'Water, Cocamidopropyl Betaine, Coco-Glucoside, Glycerin';
      final c = check(label, [const ListEntry(EntryKind.word, 'coco', Reaction.irritates)]);
      expect(c.hits.single.items, ['Coco-Glucoside']);
      expect(c.hits.single.how, 'Contains “coco”');
      expect(check(label, [const ListEntry(EntryKind.word, 'COCO GLUC', Reaction.avoid)]).hits.single.items,
          ['Coco-Glucoside']);
      expect(check(label, [const ListEntry(EntryKind.word, 'co', Reaction.avoid)]).hits, isEmpty);
    });

    test('hits are worst reaction first, and chips get the worst reaction per item', () {
      final c = check('Water, Linalool, Limonene', [
        ing('Limonene', Reaction.tellMe),
        const ListEntry(EntryKind.group, 'cat:skin-sensitizer', Reaction.irritates),
        ing('Linalool', Reaction.allergic),
      ]);
      expect(c.hits.map((h) => h.entry.reaction), [Reaction.allergic, Reaction.irritates, Reaction.tellMe]);
      expect(c.reactionFor('Linalool'), Reaction.allergic);
      expect(c.reactionFor('Limonene'), Reaction.irritates);
      expect(c.reactionFor('Water'), isNull);
    });
  });

  group('could be inside Fragrance', () {
    test('a fragrance ingredient not named on a label that declares fragrance', () {
      final c = check('Water, Parfum, Glycerin', [ing('Linalool'), ing('Lavandula Angustifolia Oil'), ing('Methylisothiazolinone')]);
      expect(c.hits, isEmpty);
      expect(c.maybeHidden.map((e) => e.value), ['Linalool', 'Lavandula Angustifolia Oil']);
    });

    test('not when it is named, or when there is no fragrance', () {
      expect(check('Water, Parfum, Linalool', [ing('Linalool')]).maybeHidden, isEmpty);
      expect(check('Water, Glycerin', [ing('Linalool')]).maybeHidden, isEmpty);
    });
  });

  test('wording never says safe', () {
    final texts = [
      noneNamedNote,
      maybeHiddenNote,
      emptyListText,
      for (final r in Reaction.values) r.label,
      for (final k in EntryKind.values) k.label,
      for (final g in listGroups(d)) g.$2,
    ];
    for (final t in texts) {
      expect(t.toLowerCase(), isNot(contains('safe')), reason: t);
    }
    expect(noneNamedNote, 'None of your list is named on this label.');
  });

  group('persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('add, change, remove, and read back', () async {
      var bumps = 0;
      void listener() => bumps++;
      MyList.changes.addListener(listener);
      expect(await MyList.all(), isEmpty);
      await MyList.add(ing('Linalool'));
      await MyList.add(const ListEntry(EntryKind.group, 'cat:pfas', Reaction.avoid));
      await MyList.add(const ListEntry(EntryKind.word, 'coco', Reaction.tellMe));
      await MyList.add(ing('linalool', Reaction.irritates)); // same ingredient: replaces
      var list = await MyList.all();
      expect(list, hasLength(3));
      expect(list.first.reaction, Reaction.irritates);
      await MyList.update(list[1], Reaction.allergic);
      await MyList.remove(list[2]);
      list = await MyList.all();
      expect(list.map((e) => (e.kind, e.value, e.reaction)), [
        (EntryKind.ingredient, 'linalool', Reaction.irritates),
        (EntryKind.group, 'cat:pfas', Reaction.allergic),
      ]);
      expect(MyList.current, list);
      final stored = (await SharedPreferences.getInstance()).getString(MyList.key)!;
      expect(stored, contains('"k":"group"'));
      expect(bumps, 6);
      MyList.changes.removeListener(listener);
    });

    test('bad data reads as an empty list', () async {
      SharedPreferences.setMockInitialValues({MyList.key: 'not json'});
      expect(await MyList.all(), isEmpty);
      SharedPreferences.setMockInitialValues({
        MyList.key: '[{"k":"nope","v":"x"},{"k":"word","v":"coco","r":"avoid"}]'
      });
      expect((await MyList.all()).single.value, 'coco');
    });
  });

  test('share text', () {
    final t = shareText(d, [
      const ListEntry(EntryKind.word, 'coco', Reaction.tellMe),
      ing('Linalool'),
      const ListEntry(EntryKind.group, 'plant-oil', Reaction.avoid),
    ]);
    expect(t, 'My ingredient list (I Hate Perfume app)\n'
        '- Linalool: Allergic\n'
        '- Any scented plant oil (group): Avoid\n'
        '- Any name containing “coco”: Just tell me');
  });

  group('result screen', () {
    Widget app(Widget w) => MaterialApp(home: Scaffold(body: w));

    testWidgets('list box: hits, and the could-be-inside note', (t) async {
      final c = check('Water, Parfum (Fragrance), Linalool', [ing('Linalool'), ing('Limonene', Reaction.irritates)]);
      await t.pumpWidget(app(ListBox(check: c, hasList: true)));
      expect(find.text('ON YOUR LIST: 1'), findsOneWidget);
      expect(find.text('Linalool'), findsOneWidget);
      expect(find.text(maybeHiddenNote), findsOneWidget);
    });

    testWidgets('list box: nothing named, and nothing at all with an empty list', (t) async {
      final c = check('Water, Glycerin', [ing('Linalool')]);
      await t.pumpWidget(app(ListBox(check: c, hasList: true)));
      expect(find.text(noneNamedNote), findsOneWidget);
      await t.pumpWidget(app(ListBox(check: ListCheck.none, hasList: false)));
      expect(find.text(noneNamedNote), findsNothing);
    });

    testWidgets('the result shows the box and the chip', (t) async {
      SharedPreferences.setMockInitialValues({MyList.key: '[{"k":"ingredient","v":"Linalool","r":"allergic"}]'});
      await t.runAsync(() => MyList.all());
      await t.pumpWidget(const MaterialApp(home: ResultScreen(text: 'Water, Linalool, Glycerin', source: 'typed')));
      await t.pump();
      expect(find.text('ON YOUR LIST: 1'), findsOneWidget);
      expect(find.text('MY LIST: ALLERGIC'), findsOneWidget);
    });
  });

  testWidgets('my list screen: empty state, sections, search, and the reaction sheet', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.runAsync(() => MyList.all());
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: MyListScreen())));
    await t.pump();
    expect(find.text(emptyListText), findsOneWidget);
    await t.enterText(find.byType(TextField), 'linalo');
    await t.pump();
    expect(find.text('Linalool'), findsWidgets);
    expect(find.text('Any name containing “linalo”'), findsOneWidget);
    await t.tap(find.text('Linalool').first);
    await t.pumpAndSettle();
    expect(find.text('Allergic'), findsOneWidget);
    expect(find.text('ADD TO MY LIST'), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.text('Allergic'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(MyList.current.single.value, 'Linalool');
    expect(find.text('ALLERGIC'), findsWidgets); // section heading and tag
    expect(find.text('INGREDIENT'), findsOneWidget);
  });
}
