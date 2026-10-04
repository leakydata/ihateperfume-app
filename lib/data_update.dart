/// Ingredient data updates from ihateperfume.com, without a store release.
///
/// The app ships decoder.json, decoder-data.json, and inci-vocab.json (assets/data). At most once a day, a few
/// seconds after the app is up, it asks the site which versions are current (GET /data, see docs/app-api.md). The
/// request carries no identifiers: no account, no device ID, no cookies, only the app's User-Agent. A file is
/// downloaded only when its sha256 differs from the copy in use; every new set is checked (size, sha256, and a full
/// parse) before it is saved and used. On any error the app keeps the data it has.
///
/// Downloaded data lives in the app's support folder as complete sets: data/sets/<time>/ holds all three files and
/// a manifest.json with their sizes and sha256. A set is written under data/tmp-<time>/ and renamed into place only
/// when complete, so a set dir is never half written. On start the newest set that checks out is used, unless the
/// bundled data is newer (after an app update); otherwise the bundled data.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/decoder.dart';
import 'services.dart';

/// The data files, in the order Decoder.fromJson takes them.
const dataFiles = ['decoder.json', 'decoder-data.json', 'inci-vocab.json'];

/// Where the app asks for the current data versions.
final dataUri = Uri.parse('https://ihateperfume.com/wp-json/ihp-app/v1/data');

const _timeout = Duration(seconds: 10);
const _maxBytes = 8 << 20; // no data file comes near this (inci-vocab.json is about 1 MB)
const _checkEvery = Duration(hours: 23); // "once a day", without drifting later each day
const _lastCheckKey = 'data-last-check';

/// The data in use, for the home footer and the Learn screen.
class DataStatus {
  /// decoder-data.json "v", e.g. 2026-09-27.
  final String version;

  /// True when the data was downloaded from the site (an update), false for the data bundled with the app.
  final bool updated;

  /// The last time the site answered a check (null if it never has).
  final DateTime? lastCheck;

  const DataStatus(this.version, this.updated, this.lastCheck);

  /// "bundled 2026-09-27" or "updated 2026-10-12".
  String get label => '${updated ? 'updated' : 'bundled'} $version';

  @override
  String toString() => label;
}

final dataStatus = ValueNotifier(const DataStatus('', false, null));

enum DataCheck {
  /// New data was downloaded, checked, saved, and is now in use.
  updated,

  /// The site has the same data.
  unchanged,

  /// Not checked: already checked today (or tried since the app started).
  skipped,

  /// Offline, or the site's data didn't check out. The current data stays.
  failed,
}

/// One complete, parsed set of the three files.
class DataSet {
  final Decoder decoder;
  final String version;
  final Map<String, String> sha256; // file name -> hex digest
  final String? dir; // the set's folder, null for the bundled data
  const DataSet(this.decoder, this.version, this.sha256, this.dir);
}

/// The folder of downloaded sets and the bundled files. Its own class so tests can use a temporary folder.
class DataStore {
  /// `<app support>/data`, or null when there is no such folder (then only the bundled data is used).
  final Directory? root;

  /// The bundled file's bytes.
  final Future<Uint8List> Function(String name) bundled;

  DataStore(this.root, this.bundled);

  Directory? get _sets => root == null ? null : Directory('${root!.path}/sets');

  /// The newest valid downloaded set, unless the bundled data is newer; else the bundled data.
  Future<DataSet> load() async {
    String? bundledVersion;
    for (final dir in await _setDirs()) {
      try {
        final s = await _open(dir.path, _readManifest(dir.path));
        final bv = bundledVersion ??= await _bundledVersion();
        if (s.version.compareTo(bv) < 0) {
          // The app was updated with newer data than this download.
          await _delete(dir);
          continue;
        }
        return s;
      } catch (_) {
        await _delete(dir); // missing, changed, or unreadable: never use part of a set
      }
    }
    return openBundled();
  }

  Future<String> _bundledVersion() async {
    final b = await bundled('decoder-data.json');
    return Isolate.run(() => _version(b));
  }

  Future<DataSet> openBundled() async {
    final bytes = [for (final n in dataFiles) await bundled(n)];
    final (decoder, version, sha) = await Isolate.run(() => _parse(bytes, null));
    return DataSet(decoder, version, sha, null);
  }

  /// Ask the site for its versions and, if any file differs from [current], download, check, save, and return the
  /// new set. Returns (unchanged, null) when nothing differs. Throws on any error, leaving no new set behind.
  Future<(DataCheck, DataSet?)> update(DataSet current, http.Client client) async {
    final sets = _sets;
    if (sets == null) throw const FileSystemException('No folder for downloaded data');
    final res = await client.get(dataUri, headers: {'User-Agent': appUserAgent}).timeout(_timeout);
    if (res.statusCode != 200) throw HttpException('GET /data: ${res.statusCode}');
    final want = _parseManifest(jsonDecode(utf8.decode(res.bodyBytes)));
    final changed = [for (final n in dataFiles) if (want[n]!.sha256 != current.sha256[n]) n];
    if (changed.isEmpty) return (DataCheck.unchanged, null);

    final stamp = DateTime.now().millisecondsSinceEpoch.toString().padLeft(15, '0');
    final tmp = Directory('${root!.path}/tmp-$stamp');
    try {
      await tmp.create(recursive: true);
      for (final n in dataFiles) {
        final out = File('${tmp.path}/$n');
        if (changed.contains(n)) {
          await out.writeAsBytes(await _download(client, want[n]!), flush: true);
        } else if (current.dir != null) {
          await File('${current.dir}/$n').copy(out.path);
        } else {
          await out.writeAsBytes(await bundled(n), flush: true);
        }
      }
      // Every file of the new set, downloaded or kept, must be what the site lists, and the set must parse.
      final expect = {for (final n in dataFiles) n: (want[n]!.sha256, want[n]!.bytes)};
      final set = await _open(tmp.path, expect);
      await File('${tmp.path}/manifest.json').writeAsString(
          jsonEncode({
            'v': set.version,
            'files': {for (final n in dataFiles) n: {'sha256': want[n]!.sha256, 'bytes': want[n]!.bytes}},
          }),
          flush: true);
      await sets.create(recursive: true);
      final dir = await tmp.rename('${sets.path}/$stamp');
      // Keep only the new set (and nothing half written).
      for (final d in await _setDirs()) {
        if (d.path != dir.path) await _delete(d);
      }
      return (DataCheck.updated, DataSet(set.decoder, set.version, set.sha256, dir.path));
    } finally {
      await _delete(tmp);
      await _deleteStrays();
    }
  }

  /// Newest first.
  Future<List<Directory>> _setDirs() async {
    final sets = _sets;
    if (sets == null || !await sets.exists()) return [];
    final dirs = await sets.list().where((e) => e is Directory).cast<Directory>().toList();
    dirs.sort((a, b) => _name(b).compareTo(_name(a)));
    return dirs;
  }

  Future<void> _deleteStrays() async {
    final r = root;
    if (r == null || !await r.exists()) return;
    await for (final e in r.list()) {
      if (e is Directory && _name(e).startsWith('tmp-')) await _delete(e);
    }
  }

  static String _name(FileSystemEntity e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last;

  static Future<void> _delete(Directory d) async {
    try {
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  static Map<String, (String, int)> _readManifest(String dir) {
    final m = _parseManifest(jsonDecode(File('$dir/manifest.json').readAsStringSync()), needUrl: false);
    return {for (final n in dataFiles) n: (m[n]!.sha256, m[n]!.bytes)};
  }

  /// Read, check, and parse a set's files in another isolate.
  static Future<DataSet> _open(String dir, Map<String, (String, int)> expect) async {
    final (decoder, version, sha) = await Isolate.run(() {
      final bytes = [for (final n in dataFiles) File('$dir/$n').readAsBytesSync()];
      return _parse(bytes, [for (final n in dataFiles) expect[n]!]);
    });
    return DataSet(decoder, version, sha, dir);
  }

  Future<Uint8List> _download(http.Client client, _Want w) async {
    final req = http.Request('GET', w.url)..headers['User-Agent'] = appUserAgent;
    final res = await client.send(req).timeout(_timeout);
    if (res.statusCode != 200) throw HttpException('${w.url.path}: ${res.statusCode}');
    final b = BytesBuilder(copy: false);
    await for (final chunk in res.stream.timeout(_timeout)) {
      b.add(chunk);
      if (b.length > w.bytes) throw HttpException('${w.url.path}: larger than listed');
    }
    final bytes = b.takeBytes();
    if (bytes.length != w.bytes) throw HttpException('${w.url.path}: ${bytes.length} bytes, listed ${w.bytes}');
    if (sha256.convert(bytes).toString() != w.sha256) throw HttpException('${w.url.path}: sha256 differs');
    return bytes;
  }
}

class _Want {
  final Uri url;
  final String sha256;
  final int bytes;
  const _Want(this.url, this.sha256, this.bytes);
}

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// The files of a GET /data answer (or a saved manifest). Download URLs must be https on the site's own host.
Map<String, _Want> _parseManifest(Object? j, {bool needUrl = true}) {
  if (j is! Map || j['files'] is! Map) throw const FormatException('No files');
  final files = j['files'] as Map;
  final out = <String, _Want>{};
  for (final n in dataFiles) {
    final f = files[n];
    if (f is! Map) throw FormatException('No $n');
    final sha = f['sha256'], bytes = f['bytes'], url = f['url'];
    if (sha is! String || !_hex64.hasMatch(sha.toLowerCase())) throw FormatException('$n: bad sha256');
    if (bytes is! int || bytes <= 0 || bytes > _maxBytes) throw FormatException('$n: bad size');
    var u = Uri();
    if (needUrl) {
      if (url is! String) throw FormatException('$n: no url');
      u = dataUri.resolve(url);
      if (u.scheme != 'https' || u.host != dataUri.host) throw FormatException('$n: url not on ${dataUri.host}');
    }
    out[n] = _Want(u, sha.toLowerCase(), bytes);
  }
  return out;
}

/// Check (when [expect] is given: sizes and sha256) and parse the three files. Throws if anything is off.
(Decoder, String, Map<String, String>) _parse(List<Uint8List> bytes, List<(String, int)>? expect) {
  final sha = <String, String>{};
  for (var i = 0; i < dataFiles.length; i++) {
    final h = sha256.convert(bytes[i]).toString();
    if (expect != null && (bytes[i].length != expect[i].$2 || h != expect[i].$1)) {
      throw FormatException('${dataFiles[i]} differs from its manifest');
    }
    sha[dataFiles[i]] = h;
  }
  final text = [for (final b in bytes) utf8.decode(b)];
  final decoder = Decoder.fromJson(text[0], text[1], text[2]);
  final version = _versionOf(text[1]);
  // A set that parses but finds nothing is broken too.
  if (decoder.flaggedNames.isEmpty || decoder.vocab.isEmpty || decoder.allergenNames.isEmpty) {
    throw const FormatException('Empty data');
  }
  return (decoder, version, sha);
}

String _version(Uint8List decoderData) => _versionOf(utf8.decode(decoderData));

String _versionOf(String decoderData) {
  final v = (jsonDecode(decoderData) as Map)['v'];
  if (v is! String || v.isEmpty) throw const FormatException('decoder-data.json has no "v"');
  return v;
}

// ---------- the app's data: load at start, check once a day ----------

DataStore? _store;
DataSet? _current;
Future<DataCheck>? _checking;
bool _triedThisRun = false;

/// Use this store instead of the app support folder and the bundled assets (tests).
@visibleForTesting
set debugDataStore(DataStore? s) {
  _store = s;
  _current = null;
  _loading = null;
  _checking = null;
  _triedThisRun = false;
}

Future<DataStore> _theStore() async {
  if (_store != null) return _store!;
  Directory? root;
  try {
    root = Directory('${(await getApplicationSupportDirectory()).path}/data');
  } catch (_) {} // no support folder: bundled data only
  return _store = DataStore(root, (n) async {
    final d = await rootBundle.load('assets/data/$n');
    return d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
  });
}

Future<void>? _loading;

/// Load the newest valid data (downloaded or bundled) and put it in use. Called once at start (the splash waits).
/// Bundled assets are read without the asset cache, so their text isn't kept in memory after parsing.
Future<void> loadData() => _loading = _load();

Future<void> _load() async {
  final store = await _theStore();
  DataSet set;
  try {
    set = await store.load();
  } catch (_) {
    set = await store.openBundled();
  }
  _use(set);
  DateTime? last;
  try {
    last = DateTime.tryParse((await SharedPreferences.getInstance()).getString(_lastCheckKey) ?? '');
  } catch (_) {}
  dataStatus.value = DataStatus(set.version, set.dir != null, last);
}

void _use(DataSet set) {
  _current = set;
  decoder = set.decoder;
  dataVersion = set.version;
  dropSpelling(); // the spelling index is rebuilt from the new data when next needed
  dataStatus.value = DataStatus(set.version, set.dir != null, dataStatus.value.lastCheck);
}

/// Check a few seconds after the app is up (never blocks it), at most once a day.
void scheduleDataUpdateCheck({Duration after = const Duration(seconds: 5)}) {
  Timer(after, () => checkForDataUpdate());
}

/// Check the site for newer data and use it. Without [force], at most once a day and once per app run after a
/// failed try. Never throws: on any error the current data stays.
Future<DataCheck> checkForDataUpdate({bool force = false, http.Client? client}) =>
    _checking ??= _check(force, client).whenComplete(() => _checking = null);

Future<DataCheck> _check(bool force, http.Client? client) async {
  if (_current == null) await _loading?.catchError((_) {});
  final current = _current;
  if (current == null) return DataCheck.skipped; // never loaded
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {}
  if (!force) {
    final last = DateTime.tryParse(prefs?.getString(_lastCheckKey) ?? '');
    if (_triedThisRun || (last != null && DateTime.now().difference(last).abs() < _checkEvery)) {
      return DataCheck.skipped;
    }
  }
  _triedThisRun = true;
  final c = client ?? http.Client();
  try {
    final (result, set) = await (await _theStore()).update(current, c);
    final now = DateTime.now();
    await prefs?.setString(_lastCheckKey, now.toIso8601String());
    dataStatus.value = DataStatus(dataStatus.value.version, dataStatus.value.updated, now);
    if (set != null && identical(_current, current)) _use(set);
    return result;
  } catch (e) {
    if (kDebugMode) debugPrint('Data update: $e');
    return DataCheck.failed;
  } finally {
    if (client == null) c.close();
  }
}
