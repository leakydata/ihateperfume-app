// Data updates from the website, against a fake server: a changed file is downloaded, checked, saved as a complete
// set, and used; anything that doesn't check out is rejected and the current data stays.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ihateperfume/data_update.dart';
import 'package:ihateperfume/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

final assets = {for (final n in dataFiles) n: File('assets/data/$n').readAsBytesSync()};
final bundledVersion = (jsonDecode(utf8.decode(assets['decoder-data.json']!)) as Map)['v'] as String;

/// decoder-data.json with another "v".
Uint8List withVersion(String v) {
  final t = utf8.decode(assets['decoder-data.json']!);
  final i = t.lastIndexOf('"v":"$bundledVersion"');
  return utf8.encode(t.replaceRange(i, i + 6 + bundledVersion.length, '"v":"$v"'));
}

String sha(List<int> b) => sha256.convert(b).toString();

const base = 'https://ihateperfume.com/wp-json/ihp-app/v1';

Map<String, Object> manifest(Map<String, List<int>> files, {String host = 'ihateperfume.com'}) => {
      'v': '2099-10-12',
      'files': {
        for (final e in files.entries)
          e.key: {'url': 'https://$host/wp-json/ihp-app/v1/files/${e.key}', 'sha256': sha(e.value), 'bytes': e.value.length}
      },
      'finds': {'url': '$base/finds', 'updated': '2026-10-04T12:00:00Z'},
    };

/// A fake site: GET /data lists [files]; each file URL serves [serve] (default: [files]). Records every request.
MockClient site(Map<String, List<int>> files, List<http.BaseRequest> log,
        {Map<String, List<int>>? serve, String host = 'ihateperfume.com'}) =>
    MockClient((req) async {
      log.add(req);
      if (req.url.toString() == '$base/data') return http.Response(jsonEncode(manifest(files, host: host)), 200);
      final body = (serve ?? files)[req.url.pathSegments.last];
      return body == null ? http.Response('', 404) : http.Response.bytes(body, 200);
    });

void main() {
  late Directory tmp;
  DataStore store() => DataStore(tmp, (n) async => assets[n]!);
  Directory setsDir() => Directory('${tmp.path}/sets');
  List<Directory> sets() =>
      setsDir().existsSync() ? setsDir().listSync().whereType<Directory>().toList() : <Directory>[];
  List<String> paths(List<http.BaseRequest> log) => [for (final r in log) r.url.path];

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('ihp-data-');
    SharedPreferences.setMockInitialValues({});
    debugDataStore = store();
    await loadData();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void expectBundledKept() {
    expect(dataVersion, bundledVersion);
    expect(dataStatus.value.label, 'bundled $bundledVersion');
    expect(sets(), isEmpty);
    expect(tmp.listSync().where((e) => e.path.contains('tmp-')), isEmpty);
  }

  test('starts with the bundled data', () {
    expect(dataVersion, bundledVersion);
    expect(dataStatus.value.label, 'bundled $bundledVersion');
    expect(decoder.flaggedNames, isNotEmpty);
  });

  test('a changed file is downloaded, checked, saved, and used; the rest are kept', () async {
    final before = decoder;
    final log = <http.BaseRequest>[];
    final files = {...assets, 'decoder-data.json': withVersion('2099-10-12')};
    expect(await checkForDataUpdate(client: site(files, log)), DataCheck.updated);
    // Only what is listed is sent: a GET with the app's User-Agent, no query, no identifiers.
    expect(paths(log), ['/wp-json/ihp-app/v1/data', '/wp-json/ihp-app/v1/files/decoder-data.json']);
    for (final r in log) {
      expect(r.method, 'GET');
      expect(r.url.query, isEmpty);
      expect(r.headers.keys.map((k) => k.toLowerCase()), ['user-agent']);
      expect(r.headers.values.single, appUserAgent);
    }
    expect(identical(decoder, before), isFalse);
    expect(dataVersion, '2099-10-12');
    expect(dataStatus.value.label, 'updated 2099-10-12');
    expect(dataStatus.value.lastCheck, isNotNull);
    expect(sets(), hasLength(1));
    final saved = sets().single;
    for (final n in dataFiles) {
      expect(File('${saved.path}/$n').readAsBytesSync(), files[n], reason: n);
    }
    expect(File('${saved.path}/manifest.json').existsSync(), isTrue);

    // The next start uses the downloaded set.
    debugDataStore = store();
    await loadData();
    expect(dataVersion, '2099-10-12');
    expect(dataStatus.value.updated, isTrue);
    expect(dataStatus.value.lastCheck, isNotNull);

    // And a later update builds the new set from the downloaded one, then removes the old set.
    final log2 = <http.BaseRequest>[];
    final files2 = {...files, 'decoder.json': utf8.encode(utf8.decode(assets['decoder.json']!).replaceFirst('{', '{ '))};
    expect(await checkForDataUpdate(force: true, client: site(files2, log2)), DataCheck.updated);
    expect(paths(log2), ['/wp-json/ihp-app/v1/data', '/wp-json/ihp-app/v1/files/decoder.json']);
    expect(sets(), hasLength(1));
    expect(sets().single.path, isNot(saved.path));
    expect(dataVersion, '2099-10-12');
  });

  test('a file whose sha256 differs from the listing is rejected', () async {
    final listed = withVersion('2099-10-12');
    final served = Uint8List.fromList(listed)..[listed.length - 3] = 0x38; // same size, one digit changed
    final log = <http.BaseRequest>[];
    final result = await checkForDataUpdate(
        client: site({...assets, 'decoder-data.json': listed}, log, serve: {...assets, 'decoder-data.json': served}));
    expect(result, DataCheck.failed);
    expectBundledKept();
  });

  test('a file of another size is rejected', () async {
    final listed = withVersion('2099-10-12');
    final log = <http.BaseRequest>[];
    final result = await checkForDataUpdate(
        client: site({...assets, 'decoder-data.json': listed}, log,
            serve: {...assets, 'decoder-data.json': [...listed, 32]}));
    expect(result, DataCheck.failed);
    expectBundledKept();
  });

  test('data that does not parse is rejected, even with the right sha256', () async {
    final log = <http.BaseRequest>[];
    for (final bad in ['{"v":"2099-10-12"}', '{"cats":{},"items":[],"names":{},"patterns":[],"limits":[],"src":{},'
        '"facts":{},"v":"2099-10-12"}', 'not json']) {
      final result = await checkForDataUpdate(force: true, client: site({...assets, 'decoder-data.json': utf8.encode(bad)}, log));
      expect(result, DataCheck.failed, reason: bad);
      expectBundledKept();
    }
  });

  test('nothing is downloaded when nothing changed', () async {
    final before = decoder;
    final log = <http.BaseRequest>[];
    expect(await checkForDataUpdate(client: site(assets, log)), DataCheck.unchanged);
    expect(paths(log), ['/wp-json/ihp-app/v1/data']);
    expect(identical(decoder, before), isTrue);
    expect(dataStatus.value.lastCheck, isNotNull);
    expectBundledKept();
  });

  test('offline keeps the data, and does not retry until the next start', () async {
    final before = decoder;
    var calls = 0;
    final offline = MockClient((_) async {
      calls++;
      throw const SocketException('Failed host lookup');
    });
    expect(await checkForDataUpdate(client: offline), DataCheck.failed);
    expect(identical(decoder, before), isTrue);
    expect(dataStatus.value.lastCheck, isNull);
    expectBundledKept();
    expect(await checkForDataUpdate(client: offline), DataCheck.skipped);
    expect(calls, 1);
  });

  test('a server error keeps the data', () async {
    final error = MockClient((_) async => http.Response('oops', 500));
    expect(await checkForDataUpdate(client: error), DataCheck.failed);
    expectBundledKept();
  });

  test('download links must be https on ihateperfume.com', () async {
    final log = <http.BaseRequest>[];
    final files = {...assets, 'decoder-data.json': withVersion('2099-10-12')};
    expect(await checkForDataUpdate(client: site(files, log, host: 'example.com')), DataCheck.failed);
    expect(paths(log), ['/wp-json/ihp-app/v1/data']);
    expectBundledKept();
  });

  test('at most once a day, unless asked', () async {
    final log = <http.BaseRequest>[];
    expect(await checkForDataUpdate(client: site(assets, log)), DataCheck.unchanged);
    debugDataStore = store(); // as on the next start
    await loadData();
    expect(await checkForDataUpdate(client: site(assets, log)), DataCheck.skipped);
    expect(log, hasLength(1));
    expect(await checkForDataUpdate(force: true, client: site(assets, log)), DataCheck.unchanged);
    expect(log, hasLength(2));
  });

  group('loading at start', () {
    /// Save a set as the app would: the three files and a manifest of them.
    Directory saveSet(String name, Map<String, List<int>> files, {bool manifest = true}) {
      final d = Directory('${setsDir().path}/$name')..createSync(recursive: true);
      for (final e in files.entries) {
        File('${d.path}/${e.key}').writeAsBytesSync(e.value);
      }
      if (manifest) {
        File('${d.path}/manifest.json').writeAsStringSync(jsonEncode({
          'v': 'x',
          'files': {for (final e in files.entries) e.key: {'sha256': sha(e.value), 'bytes': e.value.length}}
        }));
      }
      return d;
    }

    Future<void> start() async {
      debugDataStore = store();
      await loadData();
    }

    test('the newest valid set', () async {
      saveSet('000001700000000', {...assets, 'decoder-data.json': withVersion('2099-01-01')});
      saveSet('000001800000000', {...assets, 'decoder-data.json': withVersion('2099-02-02')});
      await start();
      expect(dataVersion, '2099-02-02');
      expect(dataStatus.value.label, 'updated 2099-02-02');
    });

    test('a set with a changed file is skipped and removed, never mixed with another', () async {
      saveSet('000001700000000', {...assets, 'decoder-data.json': withVersion('2099-01-01')});
      final bad = saveSet('000001800000000', {...assets, 'decoder-data.json': withVersion('2099-02-02')});
      File('${bad.path}/inci-vocab.json').writeAsStringSync('[]');
      await start();
      expect(dataVersion, '2099-01-01');
      expect(bad.existsSync(), isFalse);
    });

    test('a set without its manifest or a file is skipped', () async {
      saveSet('000001800000000', {...assets, 'decoder-data.json': withVersion('2099-02-02')}, manifest: false);
      saveSet('000001900000000', {'decoder.json': assets['decoder.json']!, 'decoder-data.json': withVersion('2099-03-03')});
      await start();
      expect(dataVersion, bundledVersion);
      expect(sets(), isEmpty);
    });

    test('bundled data newer than the download wins (after an app update)', () async {
      saveSet('000001800000000', {...assets, 'decoder-data.json': withVersion('2000-01-01')});
      await start();
      expect(dataVersion, bundledVersion);
      expect(dataStatus.value.updated, isFalse);
      expect(sets(), isEmpty);
    });

    test('no support folder: the bundled data', () async {
      debugDataStore = DataStore(null, (n) async => assets[n]!);
      await loadData();
      expect(dataVersion, bundledVersion);
      expect(await checkForDataUpdate(client: MockClient((_) async => http.Response('', 200))), DataCheck.failed);
    });
  });

  test('the spelling index is rebuilt from new data', () async {
    final first = await spelling;
    expect(identical(await spelling, first), isTrue);
    final log = <http.BaseRequest>[];
    await checkForDataUpdate(client: site({...assets, 'decoder-data.json': withVersion('2099-10-12')}, log));
    expect(identical(await spelling, first), isFalse);
    expect((await spelling).suggest('Water, Lim0nene').single.to, 'Limonene');
    dropSpelling();
  });
}
