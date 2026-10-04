// "Wrong or missing ingredients? Report it": what is sent (only on "Just report"), the sheet, and the remembered
// state. Fake http clients and fakes for the "Add it" flow, no network.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ihateperfume/contribute.dart' show appVersion;
import 'package:ihateperfume/engine/decoder.dart';
import 'package:ihateperfume/list_report.dart';
import 'package:ihateperfume/screens/no_list.dart';
import 'package:ihateperfume/screens/report_list.dart';
import 'package:ihateperfume/screens/result.dart';
import 'package:ihateperfume/services.dart' as services;
import 'package:ihateperfume/services.dart' show IhpInfo, appUserAgent;
import 'package:ihateperfume/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: SingleChildScrollView(child: child)));

const link = 'Wrong or missing ingredients? Report it';

/// ihateperfume.com, answering every report with [status]. Records each request.
MockClient server(List<http.Request> log, {int status = 202}) => MockClient((req) async {
      log.add(req);
      if (status < 0) throw const SocketException('offline');
      return http.Response('{"ok": true}', status);
    });

/// The real sender over a fake server, plus a record of "Add photos".
class Fakes {
  final requests = <http.Request>[];
  final photos = <(String, String?, bool)>[];
  int status = 202;
  Future<bool> send(String barcode, String source, ReportReason reason) =>
      ListReports.send(barcode, source, reason, client: server(requests, status: status));
  Future<void> addPhotos(BuildContext context, String barcode, String? name, bool noList) async =>
      photos.add((barcode, name, noList));
}

Future<void> pumpLink(WidgetTester t, Fakes f, {String barcode = '0123456789012', String source = 'obf'}) async {
  await t.pumpWidget(app(ReportListLink(
      key: ValueKey('$barcode|$source'),
      barcode: barcode,
      source: source,
      name: 'Acme Soap',
      send: f.send,
      addPhotos: f.addPhotos)));
  await t.pumpAndSettle();
}

Future<void> openSheet(WidgetTester t) async {
  await t.tap(find.textContaining('Report it', findRichText: true));
  await t.pumpAndSettle();
  expect(find.text('REPORT THIS LIST'), findsOneWidget);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the request', () {
    test('exactly barcode, source, reason, and app, form encoded, to /reports', () {
      final r = buildReportRequest('0123456789012', 'opf', ReportReason.wrongProduct);
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://ihateperfume.com/wp-json/ihp-app/v1/reports');
      expect(r.headers['content-type'], startsWith('application/x-www-form-urlencoded'));
      expect(r.headers['User-Agent'], appUserAgent);
      expect(r.headers.keys.map((k) => k.toLowerCase()).toSet(), {'user-agent', 'content-type'});
      expect(r.bodyFields,
          {'barcode': '0123456789012', 'source': 'opf', 'reason': 'wrong_product', 'app': appVersion});
    });

    test('reason keys', () {
      expect([for (final r in ReportReason.values) r.key], ['not_ingredients', 'wrong_product', 'missing', 'other']);
    });

    test('success is remembered; failure, offline, bad barcodes, and unknown sources aren’t', () async {
      final log = <http.Request>[];
      expect(await ListReports.send('0123456789012', 'fda', ReportReason.missing, client: server(log)), isTrue);
      expect(log.single.bodyFields,
          {'barcode': '0123456789012', 'source': 'fda', 'reason': 'missing', 'app': appVersion});
      expect(await ListReports.isReported('0123456789012', 'fda'), isTrue);
      expect(await ListReports.isReported('0123456789012', 'obf'), isFalse);

      expect(await ListReports.send('11112222', 'obf', ReportReason.other, client: server(log, status: 429)), isFalse);
      expect(await ListReports.send('11112222', 'obf', ReportReason.other, client: server(log, status: -1)), isFalse);
      expect(await ListReports.isReported('11112222', 'obf'), isFalse);
      log.clear();
      expect(await ListReports.send('123', 'obf', ReportReason.other, client: server(log)), isFalse);
      expect(await ListReports.send('0123456789012', 'photo', ReportReason.other, client: server(log)), isFalse);
      expect(log, isEmpty);
    });

    test('the report source: the result’s own, else the lookup’s, else none', () {
      expect(reportSourceFor('obf', null), 'obf');
      expect(reportSourceFor('ihp', 'obf'), 'ihp');
      expect(reportSourceFor('photo', 'opf'), 'opf');
      expect(reportSourceFor('typed', 'fda'), 'fda');
      expect(reportSourceFor('photo', null), isNull);
      expect(reportSourceFor('typed', 'photo'), isNull);
    });
  });

  group('the link and sheet', () {
    testWidgets('closing the sheet sends nothing', (t) async {
      final f = Fakes();
      await pumpLink(t, f);
      expect(find.textContaining(link, findRichText: true), findsOneWidget);
      await openSheet(t);
      expect(find.text('Tell us what’s wrong. Photos fix it fastest.'), findsOneWidget);
      for (final r in ReportReason.values) {
        expect(find.text(r.label), findsOneWidget);
      }
      expect(find.text('“Just report” sends only the barcode, where the list came from, and the reason.'),
          findsOneWidget);
      await t.tap(find.text(ReportReason.missing.label));
      await t.pump();
      await t.tapAt(const Offset(10, 10)); // outside the sheet
      await t.pumpAndSettle();
      expect(find.text('REPORT THIS LIST'), findsNothing);
      expect(f.requests, isEmpty);
      expect(f.photos, isEmpty);
      expect(find.textContaining(link, findRichText: true), findsOneWidget);
    });

    testWidgets('"Add photos" opens the Add it flow and sends nothing', (t) async {
      final f = Fakes();
      await pumpLink(t, f);
      await openSheet(t);
      await t.tap(find.text(ReportReason.notIngredients.label));
      await t.pump();
      await t.tap(find.text('ADD PHOTOS (FASTEST FIX)'));
      await t.pumpAndSettle();
      expect(find.text('REPORT THIS LIST'), findsNothing);
      expect(f.photos, [('0123456789012', 'Acme Soap', false)]);
      expect(f.requests, isEmpty);
      expect(await ListReports.isReported('0123456789012', 'obf'), isFalse);
    });

    testWidgets('"Just report" waits for a reason, sends exactly that, and is remembered', (t) async {
      final f = Fakes();
      await pumpLink(t, f, source: 'ihp');
      await openSheet(t);
      final just = find.widgetWithText(Btn, 'JUST REPORT');
      expect(t.widget<Btn>(just).onTap, isNull);
      await t.tap(find.text(ReportReason.wrongProduct.label));
      await t.pump();
      expect(t.widget<Btn>(just).onTap, isNotNull);
      await t.tap(just);
      await t.pumpAndSettle();
      expect(f.requests, hasLength(1));
      expect(f.requests.single.url.path, '/wp-json/ihp-app/v1/reports');
      expect(f.requests.single.bodyFields,
          {'barcode': '0123456789012', 'source': 'ihp', 'reason': 'wrong_product', 'app': appVersion});
      expect(find.text('Thanks. We’ll check it.'), findsOneWidget);
      expect(f.photos, isEmpty);

      // Later (a new screen): "Reported. Thanks." and no link.
      await t.pumpWidget(const SizedBox());
      await pumpLink(t, f, source: 'ihp');
      expect(find.text('Reported. Thanks.'), findsOneWidget);
      expect(find.textContaining(link, findRichText: true), findsNothing);
      // Another source for the same barcode can still be reported.
      await pumpLink(t, f, source: 'obf');
      expect(find.textContaining(link, findRichText: true), findsOneWidget);
    });

    testWidgets('a failed report says so quietly and keeps the link', (t) async {
      final f = Fakes()..status = 500;
      await pumpLink(t, f);
      await openSheet(t);
      await t.tap(find.text(ReportReason.other.label));
      await t.pump();
      await t.tap(find.widgetWithText(Btn, 'JUST REPORT'));
      await t.pumpAndSettle();
      expect(find.text('Couldn’t send it. Try again later.'), findsOneWidget);
      expect(find.textContaining(link, findRichText: true), findsOneWidget);
      expect(await ListReports.isReported('0123456789012', 'obf'), isFalse);
    });

    testWidgets('no link for a bad barcode or an unknown source', (t) async {
      final f = Fakes();
      await pumpLink(t, f, barcode: '1234567');
      expect(find.textContaining(link, findRichText: true), findsNothing);
      await pumpLink(t, f, source: 'photo');
      expect(find.textContaining(link, findRichText: true), findsNothing);
    });
  });

  group('on the result screens', () {
    setUpAll(() {
      services.decoder = Decoder.fromJson(File('assets/data/decoder.json').readAsStringSync(),
          File('assets/data/decoder-data.json').readAsStringSync(), File('assets/data/inci-vocab.json').readAsStringSync());
    });

    void tallPhone(WidgetTester t) {
      t.view.physicalSize = const Size(2400, 6000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
    }

    Future<void> pumpResult(WidgetTester t, String source, {String? barcode, String? lookupSource}) async {
      await t.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: ResultScreen(text: 'Water, Glycerin', barcode: barcode, source: source, lookupSource: lookupSource)));
      await t.pumpAndSettle();
    }

    final reportLink = find.textContaining(link, findRichText: true);

    testWidgets('a database list with a barcode has the link; photo and typed lists only after a lookup', (t) async {
      tallPhone(t);
      await pumpResult(t, 'obf', barcode: '0123456789012');
      expect(reportLink, findsOneWidget);
      await pumpResult(t, 'photo', barcode: '0123456789013');
      expect(reportLink, findsNothing);
      expect(find.textContaining('Send it to us', findRichText: true), findsOneWidget);
      await pumpResult(t, 'photo', barcode: '0123456789014', lookupSource: 'opf');
      expect(reportLink, findsOneWidget);
      await pumpResult(t, 'typed');
      expect(reportLink, findsNothing);
    });

    testWidgets('the no-list screen has the link', (t) async {
      tallPhone(t);
      await t.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: const NoListScreen(
              name: 'Acme Bags', barcode: '0123456789012', info: IhpInfo(says: 'unscented', noList: true))));
      await t.pumpAndSettle();
      expect(reportLink, findsOneWidget);
    });
  });
}
