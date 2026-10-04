// The FDA drug label lookup and the maker links, with openFDA responses recorded in test/fixtures/fda (no network).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ihateperfume/services.dart';

String fixture(String name) => File('test/fixtures/fda/$name').readAsStringSync();

const notFound = '{"error": {"code": "NOT_FOUND", "message": "No matches found!"}}';

/// Open Beauty Facts and Open Products Facts know nothing; openFDA answers from [fda] (search → fixture file).
MockClient client(Map<String, String> fda, List<Uri> calls) => MockClient((req) async {
      calls.add(req.url);
      if (req.url.host != 'api.fda.gov') return http.Response('{"status": 0}', 200);
      final search = Uri.decodeQueryComponent(req.url.query.split('&').first.substring('search='.length));
      final f = fda[search];
      return f == null
          ? http.Response(notFound, 404)
          : http.Response.bytes(utf8.encode(fixture(f)), 200, headers: {'content-type': 'application/json'});
    });

void main() {
  test('barcode to the 13-digit UPC openFDA uses', () {
    expect(fdaUpc('079400017437'), '0079400017437'); // UPC-A
    expect(fdaUpc('3606000604520'), '3606000604520'); // EAN-13
    expect(fdaUpc('00079400017437'), '0079400017437'); // GTIN-14
    expect(fdaUpc('12345678'), isNull); // EAN-8
    expect(fdaUpc('12ab'), isNull);
  });

  test('NDC inside a UPC-A that starts with 3', () {
    expect(ndcCandidates('349035264569'), ['4903-5264-56', '49035-264-56', '49035-2645-6']);
    expect(ndcCandidates('0349035264569'), ['4903-5264-56', '49035-264-56', '49035-2645-6']);
    expect(ndcCandidates('079400017437'), isEmpty);
    expect(ndcCandidates('3606000604520'), isEmpty); // an EAN-13 from France, not an NDC
  });

  test('active ingredient names without headings, strengths, or purposes', () {
    expect(fdaActives('Drug Facts Active ingredient Aluminum Sesquichlorohydrate (16%)', 'Purpose antiperspirant'),
        ['Aluminum Sesquichlorohydrate']);
    const both = 'Active ingredients Purpose Avobenzone 3% Sunscreen Homosalate 10% Sunscreen Octisalate 5% Sunscreen '
        'Octocrylene 10% Sunscreen';
    expect(fdaActives(both, both), ['Avobenzone', 'Homosalate', 'Octisalate', 'Octocrylene']);
    expect(
        fdaActives('Active ingredients Purpose Titanium Dioxide (4.9%) Sunscreen Zinc Oxide (21.6%) Sunscreen', ''),
        ['Titanium Dioxide', 'Zinc Oxide']);
    expect(fdaActives('Active ingredients Avobenzone 2.7%, Homosalate 9.0%, Octisalate 4.5%', 'Purpose Sunscreen'),
        ['Avobenzone', 'Homosalate', 'Octisalate']);
    expect(fdaActives('Active ingredient Ethyl alcohol 70% v/v', 'Purpose Antimicrobial'), ['Ethyl alcohol']);
    expect(fdaActives('Active ingredient (in each tablet) Loratadine 10 mg', 'Purpose Antihistamine'),
        ['Loratadine 10 mg']);
  });

  test('inactive ingredients without the heading', () {
    expect(fdaInactive('Inactive Ingredients: Water, Glycerin.'), 'Water, Glycerin');
    expect(fdaInactive('Inactive ingredients water, fragrance'), 'water, fragrance');
    expect(fdaInactive(''), '');
  });

  test('a label becomes a product', () {
    final label = (jsonDecode(fixture('label_upc_0079400017437.json'))['results'] as List).first;
    final p = parseFdaLabel('079400017437', label as Map<String, dynamic>)!;
    expect(p.source, 'fda');
    expect(p.name, 'Degree Advanced Sexy Intrigue 72h Antiperspirant Deodorant');
    expect(p.ingredients, startsWith('Aluminum Sesquichlorohydrate, Cyclopentasiloxane, Stearyl Alcohol,'));
    expect(p.ingredients, contains('Fragrance (Parfum)'));
    expect(p.ingredients, endsWith('Limonene, Linalool'));

    // No inactive ingredient list: a name, but no ingredient list.
    final noList = parseFdaLabel('1', {
      'active_ingredient': ['Active ingredient Zinc oxide 20%'],
      'openfda': {
        'brand_name': ['Some Sunscreen']
      },
    })!;
    expect(noList.name, 'Some Sunscreen');
    expect(noList.ingredients, isNull);
  });

  test('looked up by UPC after Open Beauty Facts and Open Products Facts', () async {
    final calls = <Uri>[];
    final p = await lookUp('079400017437',
        client: client({'openfda.upc:"0079400017437"': 'label_upc_0079400017437.json'}, calls));
    expect(p!.source, 'fda');
    expect(p.ingredients, contains('Fragrance (Parfum)'));
    expect(calls.map((u) => u.host),
        ['world.openbeautyfacts.org', 'world.openproductsfacts.org', 'api.fda.gov']);
    // Only the barcode goes out.
    expect(calls.last.toString(), contains('0079400017437'));
  });

  test('looked up by the NDC in the UPC when the UPC isn’t listed', () async {
    final calls = <Uri>[];
    final p = await lookUp(
        '349035264569',
        client: client({
          'packaging.package_ndc:"4903-5264-56" packaging.package_ndc:"49035-264-56" packaging.package_ndc:"49035-2645-6"':
              'ndc_package_49035-264-56.json',
          'openfda.product_ndc:"49035-264"': 'label_product_ndc_49035-264.json',
        }, calls));
    expect(p!.name, 'Acne Cleanser');
    expect(p.ingredients, startsWith('Benzoyl peroxide, water, cetyl alcohol,'));
    expect(p.ingredients, contains('fragrance'));
    expect(calls.where((u) => u.host == 'api.fda.gov'), hasLength(3));
  });

  test('not found anywhere, and errors count as not found', () async {
    expect(await lookUp('012345678905', client: client({}, [])), isNull);
    final p = await lookUp('079400017437', client: MockClient((req) async {
      if (req.url.host == 'api.fda.gov') throw const SocketException('down');
      return http.Response('{"status": 0}', 200);
    }));
    expect(p, isNull);
  });

  test('nothing reachable is an error', () async {
    expect(() => lookUp('079400017437', client: MockClient((_) async => throw const SocketException('offline'))),
        throwsA(isA<LookupError>()));
  });

  test('maker links for P&G barcodes only', () {
    expect(makerPage('012044038918'), 'https://smartlabel.pg.com/en-us/00012044038918.html'); // Old Spice
    expect(makerPage('037000814252'), 'https://smartlabel.pg.com/en-us/00037000814252.html'); // Secret
    expect(makerPage('0030772094006'), 'https://smartlabel.pg.com/en-us/00030772094006.html'); // Dawn
    expect(makerPage('079400017437'), isNull); // Degree (Unilever)
    expect(makerPage('3606000604520'), isNull);
    expect(makerPage('12345678'), isNull);
  });
}
