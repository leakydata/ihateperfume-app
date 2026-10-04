// The "Add it" and Finds screens render, and never show made-up products.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ihateperfume/screens/contribute.dart';
import 'package:ihateperfume/screens/finds.dart';
import 'package:ihateperfume/services.dart';
import 'package:ihateperfume/screens/no_list.dart';
import 'package:ihateperfume/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
