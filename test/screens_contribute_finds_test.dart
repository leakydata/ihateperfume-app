// The "Add it" and Finds screens render, and never show made-up products.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ihateperfume/screens/contribute.dart';
import 'package:ihateperfume/screens/finds.dart';
import 'package:ihateperfume/services.dart';
import 'package:ihateperfume/screens/no_list.dart';
import 'package:ihateperfume/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A phone-width screen tall enough to show the whole form.
/// The empty "more of the package" slot.
final addExtra =
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Add a photo: more of the package');

void tallPhone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 4500);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Widget app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

void main() {
  testWidgets('Add it: send stays off until there are photos', (t) async {
    await t.pumpWidget(MaterialApp(theme: appTheme(), home: const ContributeScreen(barcode: '0123456789012')));
    expect(find.text('Step 1 of 2'.toUpperCase()), findsOneWidget);
    expect(find.text('+ FRONT OF\nTHE PACKAGE'), findsOneWidget);
    expect(find.text('Barcode 0123456789012'.toUpperCase()), findsOneWidget);
    final send = t.widget<Btn>(find.byType(Btn));
    expect(send.text, 'Send it to us');
    expect(send.onTap, isNull);
    // Ticking "No ingredient list" shows the categories.
    await t.scrollUntilVisible(find.text('No ingredient list on it'), 100, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('No ingredient list on it'));
    await t.pump();
    await t.scrollUntilVisible(find.text('Pick a category'), 100, scrollable: find.byType(Scrollable).first);
    expect(find.text('Pick a category'), findsOneWidget);
  });

  testWidgets('Add it: the two main photos are enough; more photos stay folded away', (t) async {
    tallPhone(t);
    final photo = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));
    var picks = 0;
    await t.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: ContributeScreen(pickPhoto: () async {
          picks++;
          return photo;
        })));
    final addAnother = find.text('+ Add another (if the list wraps around)'.toUpperCase());
    const hint = 'Only if it helps: the back, the sides, or the bottom, especially anything that says “scented” or '
        '“unscented.”';
    // Extras collapsed by default; no "Add another" before the first ingredient photo.
    expect(find.text('Add more photos (optional)'.toUpperCase()), findsOneWidget);
    expect(find.text(hint), findsNothing);
    expect(addAnother, findsNothing);
    expect(find.text('Photograph the package, not people or anything personal.'), findsOneWidget);
    await t.tap(find.text('+ FRONT OF\nTHE PACKAGE'));
    await t.pump();
    expect(t.widget<Btn>(find.byType(Btn)).onTap, isNull);
    expect(addAnother, findsNothing);
    await t.tap(find.text('+ INGREDIENT\nLIST'));
    await t.pump();
    expect(picks, 2);
    // Send is on with just the two main photos; "Add another" shows up now.
    expect(t.widget<Btn>(find.byType(Btn)).onTap, isNotNull);
    expect(addAnother, findsOneWidget);
    await t.tap(addAnother);
    await t.pump();
    await t.tap(addAnother);
    await t.pump();
    expect(addAnother, findsNothing); // 3 is the most
    expect(find.bySemanticsLabel('Remove: Ingredient list 3'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Remove: Ingredient list 2'));
    await t.pump();
    expect(find.bySemanticsLabel('Remove: Ingredient list 3'), findsNothing);
    expect(addAnother, findsOneWidget);
    // Opening "more photos" shows the hint and one empty slot.
    await t.tap(find.text('Add more photos (optional)'.toUpperCase()));
    await t.pump();
    await t.scrollUntilVisible(find.text(hint), 100, scrollable: find.byType(Scrollable).first);
    expect(find.text(hint), findsOneWidget);
    expect(addExtra, findsOneWidget);
    expect(find.text('Photograph the package, not people or anything personal.'), findsOneWidget);
    // No ingredient list: the extra list photos go, "more photos" stays.
    await t.scrollUntilVisible(find.text('No ingredient list on it'), 100, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('No ingredient list on it'));
    await t.pump();
    expect(addAnother, findsNothing);
    expect(find.bySemanticsLabel('Remove: Ingredient list 1'), findsNothing);
    expect(find.text(hint), findsOneWidget);
    expect(t.widget<Btn>(find.byType(Btn)).onTap, isNotNull);
    expect(find.textContaining(RegExp(r'\bsafe\b', caseSensitive: false), findRichText: true), findsNothing);
  });

  testWidgets('Add it: the check step shows every photo, grouped', (t) async {
    tallPhone(t);
    final photo = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));
    await t.pumpWidget(MaterialApp(theme: appTheme(), home: ContributeScreen(pickPhoto: () async => photo)));
    await t.tap(find.text('+ FRONT OF\nTHE PACKAGE'));
    await t.pump();
    await t.tap(find.text('+ INGREDIENT\nLIST'));
    await t.pump();
    await t.tap(find.text('+ Add another (if the list wraps around)'.toUpperCase()));
    await t.pump();
    await t.tap(find.text('Add more photos (optional)'.toUpperCase()));
    await t.pump();
    await t.scrollUntilVisible(addExtra, 100,
        scrollable: find.byType(Scrollable).first);
    await t.tap(addExtra);
    await t.pump();
    await t.tap(find.byType(Btn));
    await t.pump();
    expect(find.text('Step 2 of 2'.toUpperCase()), findsOneWidget);
    expect(find.text('FRONT'), findsOneWidget);
    expect(find.text('INGREDIENT LIST'), findsOneWidget);
    expect(find.text('MORE OF THE PACKAGE'), findsOneWidget);
    expect(find.textContaining('LIST 1 ·'), findsOneWidget);
    expect(find.textContaining('LIST 2 ·'), findsOneWidget);
    expect(find.textContaining('MORE 1 ·'), findsOneWidget);
    expect(find.textContaining('4 PHOTOS ·'), findsOneWidget);
    expect(find.textContaining('Only these photos and details are sent'), findsOneWidget);
  });

  testWidgets('Finds: an empty list says so, from the offline copy', (t) async {
    SharedPreferences.setMockInitialValues({
      'finds-cache': '{"fetched": "2026-10-04T13:00:00Z", "body": {"updated": "2026-10-04T12:00:00Z", '
          '"categories": [], "items": []}}',
    });
    await t.pumpWidget(app(FindsScreen(visible: ValueNotifier(true))));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    expect(find.text('FRAGRANCE-FREE FINDS'), findsOneWidget);
    expect(find.textContaining('No finds yet. Be the first', findRichText: true), findsOneWidget);
    expect(find.textContaining('Last updated Oct 4, 2026'), findsOneWidget);
  });

  testWidgets('No list: what the package says, and unscented isn’t fragrance-free', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: const NoListScreen(
            name: 'Acme Bags',
            barcode: '0123456789012',
            info: IhpInfo(says: 'unscented', checked: '2026-10', evidence: 'package photo', noList: true))));
    expect(find.text('SAYS UNSCENTED'), findsOneWidget);
    expect(find.textContaining('Reviewed by I Hate Perfume from a package photo (Oct 2026).'), findsOneWidget);
    expect(find.textContaining('Look for “fragrance-free,” not “unscented.”', findRichText: true), findsOneWidget);
    expect(find.textContaining(RegExp(r'\bsafe\b', caseSensitive: false), findRichText: true), findsNothing);
  });
}
