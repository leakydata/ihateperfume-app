import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ihateperfume/main.dart';
import 'package:ihateperfume/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> launch(WidgetTester tester) async {
  final seen = await FirstRunNotice.seen();
  await tester.pumpWidget(MaterialApp(
    theme: appTheme(),
    home: NoticeGate(key: UniqueKey(), seen: seen, child: const Text('THE APP')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the first-run notice shows once', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await launch(tester);
    expect(find.text('BEFORE YOU START'), findsOneWidget);
    for (final p in FirstRunNotice.points) {
      expect(find.text(p), findsOneWidget);
    }
    expect(find.text('TERMS AND DISCLAIMER'), findsOneWidget);
    expect(find.text('PRIVACY POLICY'), findsOneWidget);
    expect(find.text('THE APP'), findsNothing);

    await tester.tap(find.text('GOT IT'));
    await tester.pumpAndSettle();
    expect(find.text('THE APP'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool(FirstRunNotice.prefsKey), isTrue);

    // Next launch: straight to the app.
    await launch(tester);
    expect(find.text('BEFORE YOU START'), findsNothing);
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('the notice links to the terms and back', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await launch(tester);
    await tester.tap(find.text('TERMS AND DISCLAIMER'));
    await tester.pumpAndSettle();
    expect(find.text('TERMS OF USE AND DISCLAIMER'), findsOneWidget);
    await tester.tap(find.text('BACK'));
    await tester.pumpAndSettle();
    expect(find.text('BEFORE YOU START'), findsOneWidget);
  });
}
