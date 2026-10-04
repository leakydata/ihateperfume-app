// Our own reviewed products (the 4th barcode source), recent scans of products with no list, and the
// fragrance-free finds with their offline copy. Fake http clients, no network.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ihateperfume/finds.dart';
import 'package:ihateperfume/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const finds = {
  'updated': '2026-10-04T12:00:00Z',
  'categories': ['Trash bags', 'Laundry'],
  'items': [
    {
      'name': 'Kitchen Bags',
      'brand': 'Acme',
      'category': 'Trash bags',
      'says': 'Unscented',
      'note': null,
      'checked': '2026-10',
      'evidence': 'package photo',
      'barcode': '0123456789012'
    },
    {'name': 'Tall Bags', 'brand': 'Acme', 'category': 'Trash bags', 'says': 'scented', 'note': 'Says “fresh scent” on the box', 'checked': '2026-09', 'evidence': 'maker site', 'barcode': null},
    {'name': 'Paper Towels', 'category': 'Paper', 'says': 'no scent listed', 'checked': '2026-10', 'evidence': 'package photo', 'barcode': 'x'},
    {'brand': 'No name, skipped'},
  ],
};

/// OBF, OPF, and openFDA know nothing; ihateperfume.com answers [status] with [body].
MockClient ours(int status, Object? body, List<Uri> calls) => MockClient((req) async {
      calls.add(req.url);
      if (req.url.host == 'ihateperfume.com') {
        return http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});
      }
      if (req.url.host == 'api.fda.gov') return http.Response('{"error": {"code": "NOT_FOUND"}}', 404);
      return http.Response('{"status": 0}', 200);
    });

void main() {
  group('our products', () {
    test('after the others miss, only the barcode goes to ihateperfume.com', () async {
      final calls = <Uri>[];
      final p = await lookUp('0123456789012',
          client: ours(
              200,
              {
                'barcode': '0123456789012',
                'name': 'Acme Lotion',
                'ingredients': 'Water, Glycerin',
                'no_list': false,
                'says': 'fragrance-free',
                'checked': '2026-10',
                'evidence': 'package photo'
              },
              calls));
      expect(p!.source, 'ihp');
      expect(p.ingredients, 'Water, Glycerin');
      expect(p.ihp!.says, 'fragrance-free');
      expect(calls.last.toString(), 'https://ihateperfume.com/wp-json/ihp-app/v1/products/0123456789012');
      expect(calls.last.hasQuery, isFalse);
      expect(ihpNote(p.ihp), 'Reviewed by I Hate Perfume from a package photo (Oct 2026).');
      expect(p.sourceName, 'I Hate Perfume');
    });

    test('no ingredient list: a no-list product', () async {
      final p = await lookUp('0123456789012',
          client: ours(
              200,
              {
                'barcode': '0123456789012',
                'name': 'Acme Bags',
                'ingredients': null,
                'no_list': true,
                'says': 'unscented',
                'checked': '2026-10',
                'evidence': 'maker site'
              },
              []));
      expect(p!.noList, isTrue);
      expect(p.ingredients, isNull);
      expect(ihpNote(p.ihp), 'Reviewed by I Hate Perfume from the maker’s site (Oct 2026).');
      expect(saysTag(p.ihp!.says), ('Says unscented', 0));
    });

    test('404 or an error is not found, never a failure', () async {
      expect(await lookUp('0123456789012', client: ours(404, {'code': 'not_found'}, [])), isNull);
      expect(await lookUp('0123456789012', client: ours(500, 'oops', [])), isNull);
      final (p, reached) = await lookUpIhp(
          '0123456789012', MockClient((_) async => throw const SocketException('offline')));
      expect((p, reached), (null, false));
    });

    test('not a barcode: not asked', () async {
      final calls = <Uri>[];
      await lookUpIhp('12ab', ours(200, {}, calls));
      await lookUpIhp('1234567', ours(200, {}, calls));
      expect(calls, isEmpty);
    });

    test('the says chips and dates', () {
      expect(saysTag('fragrance-free'), ('Says fragrance-free', 0));
      expect(saysTag('no scent listed'), ('No scent listed', 0));
      expect(saysTag('scented'), ('Scented', 3));
      expect(saysTag(null), isNull);
      expect(monthYear('2026-10'), 'Oct 2026');
      expect(monthYear('soon'), 'soon');
      expect(ihpNote(null), 'Reviewed by I Hate Perfume from a package photo or the maker’s site.');
    });
  });

  group('recent scans', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('products with no list are kept, each by its barcode', () async {
      const info = IhpInfo(says: 'unscented', checked: '2026-10', evidence: 'package photo', noList: true);
      await History.add(Scan('Acme Bags', '111111111111', '', 'ihp', DateTime(2026, 10, 4), 'Says unscented', 0, ihp: info));
      await History.add(Scan('Other Bags', '222222222222', '', 'ihp', DateTime(2026, 10, 5), 'Scented', 3,
          ihp: const IhpInfo(says: 'scented', noList: true)));
      final all = await History.all();
      expect(all.map((s) => s.name), ['Other Bags', 'Acme Bags']);
      expect(all.last.ihp!.says, 'unscented');
      expect(all.last.ihp!.noList, isTrue);
      expect(all.last.ihp!.checked, '2026-10');
      expect(all.last.text, '');
    });
  });

  group('finds', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('parsing', () {
      final f = parseFinds(jsonDecode(jsonEncode(finds)))!;
      expect(f.updated, DateTime.utc(2026, 10, 4, 12));
      expect(f.items.map((x) => x.name), ['Kitchen Bags', 'Tall Bags', 'Paper Towels']);
      expect(f.categories, ['Trash bags', 'Laundry', 'Paper']);
      expect(f.items[0].says, 'unscented');
      expect(f.items[0].checkedLine, 'Checked Oct 2026 · package photo');
      expect(f.items[1].checkedLine, 'Checked Sep 2026 · maker’s site');
      expect(f.items[1].note, 'Says “fresh scent” on the box');
      expect(f.items[2].barcode, isNull);
      expect(f.items[2].brand, '');
      expect(parseFinds({'nope': 1}), isNull);
      expect(parseFinds({'items': []})!.items, isEmpty);
    });

    test('kept on the phone and used offline', () async {
      expect(await FindsStore.cached(), isNull);
      final calls = <Uri>[];
      final got = await FindsStore.refresh(
          now: DateTime.utc(2026, 10, 4, 13),
          client: MockClient((req) async {
            calls.add(req.url);
            return http.Response.bytes(utf8.encode(jsonEncode(finds)), 200);
          }));
      expect(calls.single.toString(), 'https://ihateperfume.com/wp-json/ihp-app/v1/finds');
      expect(got.data.items, hasLength(3));

      // Offline: the refresh fails, the copy stays.
      await expectLater(FindsStore.refresh(client: MockClient((_) async => throw const SocketException('offline'))),
          throwsA(isA<FindsError>()));
      await expectLater(FindsStore.refresh(client: MockClient((_) async => http.Response('<html>', 200))),
          throwsA(isA<FindsError>()));
      await expectLater(FindsStore.refresh(client: MockClient((_) async => http.Response('', 503))),
          throwsA(isA<FindsError>()));
      final kept = (await FindsStore.cached())!;
      expect(kept.data.items.map((x) => x.name), ['Kitchen Bags', 'Tall Bags', 'Paper Towels']);
      expect(kept.fetched, DateTime.utc(2026, 10, 4, 13));
      expect(kept.updated, DateTime.utc(2026, 10, 4, 12));
    });

    test('an empty list is a real answer, not an error', () async {
      final got = await FindsStore.refresh(
          client: MockClient((_) async => http.Response('{"updated": null, "categories": [], "items": []}', 200)));
      expect(got.data.items, isEmpty);
      expect((await FindsStore.cached())!.data.items, isEmpty);
    });
  });
}
