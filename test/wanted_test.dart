// "Ask us to find it": the choice and its sheet, what is sent, the local list, the found-it check, and the home
// panel. Fake senders and http clients, no network.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ihateperfume/contribute.dart' show appVersion;
import 'package:ihateperfume/screens/no_list.dart';
import 'package:ihateperfume/screens/wanted.dart';
import 'package:ihateperfume/services.dart';
import 'package:ihateperfume/theme.dart';
import 'package:ihateperfume/wanted.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

const ask = 'ASK US TO FIND IT';

/// A fake sender that records what it was asked to send.
class FakeSend {
  final sent = <String>[];
  bool ok = true;
  Future<bool> call(String barcode, String? name) async {
    sent.add(barcode);
    if (ok) await Wanted.remember(barcode, name: name);
    return ok;
  }
}

Future<void> pumpAsk(WidgetTester t, FakeSend f, String barcode) async {
  await t.pumpWidget(app(AskToFind(key: ValueKey(barcode), barcode: barcode, send: f.call)));
  await t.pumpAndSettle();
}

/// ihateperfume.com answers each /products/{barcode} from [answers] (status, body); anything else is a 404.
MockClient products(Map<String, (int, Object?)> answers, List<String> asked) => MockClient((req) async {
      final b = req.url.pathSegments.last;
      asked.add(b);
      final a = answers[b];
      if (a == null) return http.Response('{"code":"not_found"}', 404);
      if (a.$1 < 0) throw const SocketException('offline');
      return http.Response.bytes(utf8.encode(jsonEncode(a.$2)), a.$1, headers: {'content-type': 'application/json'});
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Wanted.resetRun();
    Wanted.found.value = const [];
  });

  group('the choice', () {
    testWidgets('nothing is sent before a choice; closing the sheet sends nothing', (t) async {
      final f = FakeSend();
      await pumpAsk(t, f, '0123456789012');
      expect(f.sent, isEmpty);
      expect(find.text(ask), findsOneWidget);
      expect(find.text('We’ll try to find it. Photos get it added faster.'), findsOneWidget);
      await t.tap(find.text(ask));
      await t.pumpAndSettle();
      expect(find.text('HELP FILL THE GAPS.'), findsOneWidget);
      // Close it without choosing.
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(f.sent, isEmpty);
      expect(await Wanted.mode(), isNull);
      expect(find.text(ask), findsOneWidget);
    });

    testWidgets('"Send just this one": sends this one; next time the sheet asks again', (t) async {
      final f = FakeSend();
      await pumpAsk(t, f, '0123456789012');
      await t.tap(find.text(ask));
      await t.pumpAndSettle();
      await t.tap(find.text('SEND JUST THIS ONE'));
      await t.pumpAndSettle();
      expect(await Wanted.mode(), WantedMode.ask);
      expect(f.sent, ['0123456789012']);
      expect(find.text('Sent. We’ll look for it.'), findsOneWidget);

      // Another miss: nothing goes until the link is tapped, and then the sheet asks again.
      await pumpAsk(t, f, '11112222');
      expect(f.sent, ['0123456789012']);
      await t.tap(find.text(ask));
      await t.pumpAndSettle();
      expect(find.text('HELP FILL THE GAPS.'), findsOneWidget);
      expect(f.sent, ['0123456789012']); // still nothing until a choice
      await t.tap(find.text('SEND JUST THIS ONE'));
      await t.pumpAndSettle();
      expect(f.sent, ['0123456789012', '11112222']);
    });

    testWidgets('closing the sheet again sends nothing', (t) async {
      final f = FakeSend();
      await Wanted.setMode(WantedMode.ask);
      await pumpAsk(t, f, '0123456789012');
      await t.tap(find.text(ask));
      await t.pumpAndSettle();
      expect(find.text('HELP FILL THE GAPS.'), findsOneWidget);
      await t.tapAt(const Offset(10, 10)); // outside the sheet
      await t.pumpAndSettle();
      expect(f.sent, isEmpty);
    });

    testWidgets('"automatically": sends now, and future misses with no taps', (t) async {
      final f = FakeSend();
      await pumpAsk(t, f, '0123456789012');
      await t.tap(find.text(ask));
      await t.pumpAndSettle();
      await t.tap(find.text('SEND MISSING BARCODES AUTOMATICALLY'));
      await t.pumpAndSettle();
      expect(await Wanted.mode(), WantedMode.auto);
      expect(f.sent, ['0123456789012']);

      await pumpAsk(t, f, '11112222');
      expect(f.sent, ['0123456789012', '11112222']);
      expect(find.text('Sent. We’ll look for it.'), findsOneWidget);
      expect(find.text(ask), findsNothing);
    });

    testWidgets('"No thanks": nothing sent, and the link stays hidden', (t) async {
      final f = FakeSend();
      await pumpAsk(t, f, '0123456789012');
      await t.tap(find.text(ask));
      await t.pumpAndSettle();
      await t.tap(find.text('NO THANKS'));
      await t.pumpAndSettle();
      expect(await Wanted.mode(), WantedMode.off);
      expect(find.text(ask), findsNothing);
      await pumpAsk(t, f, '11112222');
      expect(find.text(ask), findsNothing);
      expect(f.sent, isEmpty);
    });

    testWidgets('a failed send says so quietly and keeps the link', (t) async {
      final f = FakeSend()..ok = false;
      await Wanted.setMode(WantedMode.ask);
      await pumpAsk(t, f, '0123456789012');
      await t.tap(find.text(ask));
      await t.pumpAndSettle();
      await t.tap(find.text('SEND JUST THIS ONE'));
      await t.pumpAndSettle();
      expect(find.text('Couldn’t send it. Try again later.'), findsOneWidget);
      expect(find.text(ask), findsOneWidget);
      expect(await Wanted.list(), isEmpty);
    });

    testWidgets('an invalid barcode shows no link and is never sent', (t) async {
      final f = FakeSend();
      await Wanted.setMode(WantedMode.auto);
      await pumpAsk(t, f, '123456');
      expect(f.sent, isEmpty);
      expect(find.text(ask), findsNothing);
    });

    testWidgets('Learn: the setting shows the choice and saves a change', (t) async {
      await Wanted.setMode(WantedMode.off);
      await t.pumpWidget(app(const WantedSetting()));
      await t.pumpAndSettle();
      expect(find.text('Missing barcodes'), findsOneWidget);
      bool selected(String label) =>
          (t.widget<Icon>(find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
                  matching: find.byType(Icon))))
              .icon ==
          Icons.radio_button_checked;
      expect(selected('Don’t send'), isTrue);
      expect(selected('Ask me each time'), isFalse);
      await t.tap(find.text('Ask me each time'));
      await t.pumpAndSettle();
      expect(selected('Ask me each time'), isTrue);
      expect(await Wanted.mode(), WantedMode.ask);
    });
  });

  group('sending', () {
    test('the request is exactly barcode and app, form encoded, to /wanted', () {
      final r = buildWantedRequest('0123456789012');
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://ihateperfume.com/wp-json/ihp-app/v1/wanted');
      expect(r.bodyFields, {'barcode': '0123456789012', 'app': appVersion});
      expect(r.body, 'barcode=0123456789012&app=${Uri.encodeQueryComponent(appVersion)}');
      expect(r.headers['User-Agent'], appUserAgent);
      expect(r.headers.keys.map((k) => k.toLowerCase()).toSet(), {'user-agent', 'content-type'});
    });

    test('success adds it to the local list; failure and bad barcodes don’t', () async {
      final bodies = <String>[];
      var status = 202;
      final c = MockClient((req) async {
        bodies.add(req.body);
        return http.Response('{"ok": true}', status);
      });
      expect(await Wanted.send('0123456789012', name: 'Acme Bags', client: c), isTrue);
      expect(bodies.single, 'barcode=0123456789012&app=${Uri.encodeQueryComponent(appVersion)}');
      expect((await Wanted.list()).single.name, 'Acme Bags');
      status = 429;
      expect(await Wanted.send('11112222', client: c), isFalse);
      expect(await Wanted.send('12ab5678', client: c), isFalse);
      expect(await Wanted.send('1234567', client: c), isFalse);
      expect(bodies.length, 2); // the bad barcodes never went
      expect(await Wanted.send('11112222', client: MockClient((_) async => throw const SocketException('x'))),
          isFalse);
      expect((await Wanted.list()).map((e) => e.barcode), ['0123456789012']);
    });

    test('the list keeps 100, newest first, and drops ones older than 180 days', () async {
      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 105; i++) {
        await Wanted.remember('${10000000 + i}', now: t0.add(Duration(minutes: i)));
      }
      var l = await Wanted.list(now: t0);
      expect(l.length, 100);
      expect(l.first.barcode, '10000104');
      expect(l.last.barcode, '10000005');
      // Asking again moves it to the front without a duplicate.
      await Wanted.remember('10000050', now: t0.add(const Duration(days: 10)));
      l = await Wanted.list(now: t0.add(const Duration(days: 10)));
      expect(l.length, 100);
      expect(l.first.barcode, '10000050');
      // 181 days later, only the one asked again is left.
      l = await Wanted.list(now: t0.add(const Duration(days: 181)));
      expect(l.map((e) => e.barcode), ['10000050']);
    });
  });

  group('found-it check', () {
    final day = DateTime(2026, 10, 4, 9);

    test('nothing in the list: no request at all', () async {
      final asked = <String>[];
      expect(await Wanted.checkFound(client: products({}, asked), now: day), isEmpty);
      expect(asked, isEmpty);
    });

    test('found ones leave the list and are remembered; not found and errors stay', () async {
      await Wanted.remember('11111111', now: day);
      await Wanted.remember('22222222', name: 'Asked name', now: day);
      await Wanted.remember('33333333', now: day);
      await Wanted.remember('44444444', now: day);
      final asked = <String>[];
      final c = products({
        '11111111': (200, {'name': 'Acme Lotion', 'ingredients': 'Water, Glycerin', 'says': 'fragrance-free'}),
        '22222222': (200, {'name': '', 'no_list': true, 'says': 'unscented', 'checked': '2026-10'}),
        '33333333': (-1, null), // unreachable
      }, asked);
      final hits = await Wanted.checkFound(client: c, now: day);
      expect(asked.toSet(), {'11111111', '22222222', '33333333', '44444444'});
      expect(hits.map((p) => p.name), containsAll(['Acme Lotion', 'Asked name']));
      expect((await Wanted.list(now: day)).map((e) => e.barcode).toSet(), {'33333333', '44444444'});
      expect(Wanted.found.value.length, 2);
      // Saved for the next start.
      Wanted.found.value = const [];
      await Wanted.loadFound();
      expect(Wanted.found.value.map((p) => p.barcode).toSet(), {'11111111', '22222222'});
      expect(Wanted.found.value.firstWhere((p) => p.barcode == '22222222').noList, isTrue);
    });

    test('at most once a day', () async {
      await Wanted.remember('11111111', now: day);
      final asked = <String>[];
      final c = products({}, asked);
      await Wanted.checkFound(client: c, now: day);
      expect(asked.length, 1);
      Wanted.resetRun(); // as if the app started again
      await Wanted.checkFound(client: c, now: day.add(const Duration(hours: 5)));
      expect(asked.length, 1);
      Wanted.resetRun();
      await Wanted.checkFound(client: c, now: day.add(const Duration(hours: 24)));
      expect(asked.length, 2);
    });

    test('at most 20 requests a day, the least recently checked first', () async {
      for (var i = 0; i < 30; i++) {
        await Wanted.remember('${20000000 + i}', now: day.subtract(Duration(minutes: 30 - i)));
      }
      final asked = <String>[];
      final c = products({}, asked);
      await Wanted.checkFound(client: c, now: day);
      expect(asked.length, 20);
      Wanted.resetRun();
      asked.clear();
      await Wanted.checkFound(client: c, now: day.add(const Duration(days: 1)));
      expect(asked.length, 20);
      // The 10 not checked on the first day go first on the second.
      final first10 = asked.take(10).toSet();
      expect(first10.length, 10);
      expect((await Wanted.list(now: day)).length, 30);
    });

    test('barcodes older than 180 days leave the list without a request', () async {
      await Wanted.remember('11111111', now: day.subtract(const Duration(days: 200)));
      final asked = <String>[];
      await Wanted.checkFound(client: products({}, asked), now: day);
      expect(asked, isEmpty);
      expect(await Wanted.list(now: day), isEmpty);
    });
  });

  group('home panel', () {
    testWidgets('shows the names, opens a product, and dismisses', (t) async {
      Wanted.found.value = const [
        Product('11111111', 'Acme Lotion', 'Water, Glycerin', 'ihp', ihp: IhpInfo(says: 'fragrance-free')),
        Product('22222222', 'Acme Bags', null, 'ihp', ihp: IhpInfo(says: 'unscented', noList: true)),
      ];
      await t.pumpWidget(app(const FoundPanel()));
      expect(find.text('We found 2 products you asked about.'), findsOneWidget);
      expect(find.text('ACME LOTION'), findsOneWidget);
      expect(find.text('ACME BAGS'), findsOneWidget);
      await t.tap(find.text('ACME BAGS'));
      await t.pumpAndSettle();
      expect(find.byType(NoListScreen), findsOneWidget);
      Navigator.of(t.element(find.byType(NoListScreen))).pop();
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Dismiss'));
      await t.pumpAndSettle();
      expect(find.textContaining('We found'), findsNothing);
      await Wanted.loadFound();
      expect(Wanted.found.value, isEmpty);
    });

    testWidgets('one product: singular', (t) async {
      Wanted.found.value = const [Product('11111111', '', 'Water', 'ihp')];
      await t.pumpWidget(app(const FoundPanel()));
      expect(find.text('We found 1 product you asked about.'), findsOneWidget);
      expect(find.text('BARCODE 11111111'), findsOneWidget);
    });
  });
}
