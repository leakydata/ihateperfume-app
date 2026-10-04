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
///
/// The products we reviewed ourselves (products.json, listed as "products" in GET /data) are kept the same way, on
/// their own: data/products/<time>/ holds products.json and its manifest.json. They are checked on the phone first
/// when a barcode is scanned, so a product we reviewed never sends its barcode anywhere. There is no bundled copy;
/// until the first download the list is empty. A missing "products" entry, or one that doesn't check out, keeps the
/// products the app has and never stops a decoder update.
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

  /// How many of our reviewed products are on the phone (checked before any lookup leaves it).
  final int products;

  const DataStatus(this.version, this.updated, this.lastCheck, {this.products = 0});

  DataStatus copyWith({String? version, bool? updated, DateTime? lastCheck, int? products}) => DataStatus(
      version ?? this.version, updated ?? this.updated, lastCheck ?? this.lastCheck,
      products: products ?? this.products);

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

/// Our reviewed products, as downloaded from the site: keyed by [barcodeKey].
class ProductSet {
  final Map<String, Product> byBarcode;
  final String sha256; // of products.json, '' when there is none
  final String? dir; // the set's folder, null when there is none
  const ProductSet(this.byBarcode, this.sha256, this.dir);
  static const empty = ProductSet({}, '', null);
  int get count => byBarcode.length;
}

/// What one check found. [products] is null when the products didn't change (or couldn't be updated).
class DataUpdate {
  final DataCheck check;
  final DataSet? set;
  final ProductSet? products;
  const DataUpdate(this.check, this.set, this.products);
}

/// One form for the same barcode: a 12-digit UPC-A and its 13-digit EAN form (a leading 0) match, and so does a
/// GTIN-14 that starts with 0.
String barcodeKey(String barcode) {
  final b = barcode.trim();
  if (!RegExp(r'^\d+$').hasMatch(b)) return b;
  if (b.length == 12) return '0$b';
  if (b.length == 14 && b.startsWith('0')) return b.substring(1);
  return b;
}

/// The folder of downloaded sets and the bundled files. Its own class so tests can use a temporary folder.
class DataStore {
  /// `<app support>/data`, or null when there is no such folder (then only the bundled data is used).
  final Directory? root;

  /// The bundled file's bytes.
  final Future<Uint8List> Function(String name) bundled;

  DataStore(this.root, this.bundled);

  Directory? get _sets => root == null ? null : Directory('${root!.path}/sets');
  Directory? get _productSets => root == null ? null : Directory('${root!.path}/products');

  /// The newest downloaded products that check out (size, sha256, parse), else none. Bad sets are removed.
  Future<ProductSet> loadProducts() async {
    for (final dir in await _setDirs(_productSets)) {
      try {
        final m = jsonDecode(await File('${dir.path}/manifest.json').readAsString());
        if (m is! Map) throw const FormatException('Bad manifest');
        final want = _parseEntry('products.json', m, needUrl: false);
        final path = '${dir.path}/products.json';
        final sha = want.sha256, size = want.bytes;
        final byBarcode = await Isolate.run(() => _parseProducts(File(path).readAsBytesSync(), sha, size));
        return ProductSet(byBarcode, sha, dir.path);
      } catch (_) {
        await _delete(dir);
      }
    }
    return ProductSet.empty;
  }

  /// Download, check, and save the products listed in a GET /data answer [j], if they differ from [current].
  /// Null when there is no "products" entry or it's unchanged. Throws if the new file doesn't check out (then nothing
  /// is saved).
  Future<ProductSet?> _updateProducts(Map j, ProductSet current, http.Client client) async {
    final entry = j['products'];
    if (entry == null) return null;
    final want = _parseEntry('products.json', entry);
    if (want.sha256 == current.sha256) return null;
    final bytes = await _download(client, want);
    final sha = want.sha256, size = want.bytes;
    final byBarcode = await Isolate.run(() => _parseProducts(bytes, sha, size));
    final stamp = DateTime.now().millisecondsSinceEpoch.toString().padLeft(15, '0');
    final tmp = Directory('${root!.path}/tmp-products-$stamp');
    try {
      await tmp.create(recursive: true);
      await File('${tmp.path}/products.json').writeAsBytes(bytes, flush: true);
      await File('${tmp.path}/manifest.json').writeAsString(jsonEncode({'sha256': sha, 'bytes': size}), flush: true);
      final sets = _productSets!;
      await sets.create(recursive: true);
      final dir = await tmp.rename('${sets.path}/$stamp');
      for (final d in await _setDirs(sets)) {
        if (d.path != dir.path) await _delete(d);
      }
      return ProductSet(byBarcode, sha, dir.path);
    } finally {
      await _delete(tmp);
    }
  }

  /// The newest valid downloaded set, unless the bundled data is newer; else the bundled data.
  Future<DataSet> load() async {
    String? bundledVersion;
    for (final dir in await _setDirs(_sets)) {
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

  /// Ask the site for its versions and update what differs: the decoder files (against [current]) and our reviewed
  /// products (against [products]), each on its own. Throws if the site can't be asked. A decoder set that doesn't
  /// check out makes the check [DataCheck.failed] and leaves no new set behind; products that don't check out are
  /// skipped. Neither stops the other.
  Future<DataUpdate> update(DataSet current, http.Client client, {ProductSet products = ProductSet.empty}) async {
    if (_sets == null) throw const FileSystemException('No folder for downloaded data');
    final res = await client.get(dataUri, headers: {'User-Agent': appUserAgent}).timeout(_timeout);
    if (res.statusCode != 200) throw HttpException('GET /data: ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    DataCheck check;
    DataSet? set;
    try {
      (check, set) = await _updateDecoder(j, current, client);
    } catch (e) {
      if (kDebugMode) debugPrint('Data update: $e');
      check = DataCheck.failed;
    }
    ProductSet? newProducts;
    try {
      if (j is Map) newProducts = await _updateProducts(j, products, client);
    } catch (e) {
      if (kDebugMode) debugPrint('Products update: $e');
    } finally {
      await _deleteStrays();
    }
    if (check == DataCheck.unchanged && newProducts != null) check = DataCheck.updated;
    return DataUpdate(check, set, newProducts);
  }

  Future<(DataCheck, DataSet?)> _updateDecoder(Object? j, DataSet current, http.Client client) async {
    final sets = _sets!;
    final want = _parseManifest(j);
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
      for (final d in await _setDirs(sets)) {
        if (d.path != dir.path) await _delete(d);
      }
      return (DataCheck.updated, DataSet(set.decoder, set.version, set.sha256, dir.path));
    } finally {
      await _delete(tmp);
      await _deleteStrays();
    }
  }

  /// Newest first.
  Future<List<Directory>> _setDirs(Directory? sets) async {
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
  return {for (final n in dataFiles) n: _parseEntry(n, files[n], needUrl: needUrl)};
}

/// One file's entry: {"url", "sha256", "bytes"} (no url in a saved manifest).
_Want _parseEntry(String n, Object? f, {bool needUrl = true}) {
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
  return _Want(u, sha.toLowerCase(), bytes);
}

/// Check products.json against its listed size and sha256, and parse it: {"updated", "items": [<GET
/// /products/{barcode} objects>]}. Items without a valid barcode, or that aren't a product, are skipped.
Map<String, Product> _parseProducts(Uint8List bytes, String sha, int size) {
  if (bytes.length != size || sha256.convert(bytes).toString() != sha) {
    throw const FormatException('products.json differs from its listing');
  }
  final j = jsonDecode(utf8.decode(bytes));
  if (j is! Map || j['items'] is! List) throw const FormatException('products.json has no items');
  final out = <String, Product>{};
  for (final item in j['items'] as List) {
    if (item is! Map) continue;
    final b = item['barcode'];
    if (b is! String || !RegExp(r'^\d{8,14}$').hasMatch(b)) continue;
    final p = parseIhpProduct(b, item);
    if (p != null) out[barcodeKey(b)] = p;
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
ProductSet _products = ProductSet.empty;

/// One of our reviewed products from the copy on the phone, or null. Never makes a request.
Product? localProduct(String barcode) {
  final p = _products.byBarcode[barcodeKey(barcode)];
  return p == null ? null : Product(barcode, p.name, p.ingredients, 'ihp', ihp: p.ihp);
}
Future<DataCheck>? _checking;
bool _triedThisRun = false;

/// Use this store instead of the app support folder and the bundled assets (tests).
@visibleForTesting
set debugDataStore(DataStore? s) {
  _store = s;
  _current = null;
  _products = ProductSet.empty;
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
  ProductSet products;
  try {
    products = await store.loadProducts();
  } catch (_) {
    products = ProductSet.empty;
  }
  _products = products;
  DateTime? last;
  try {
    last = DateTime.tryParse((await SharedPreferences.getInstance()).getString(_lastCheckKey) ?? '');
  } catch (_) {}
  dataStatus.value = DataStatus(set.version, set.dir != null, last, products: products.count);
}

void _use(DataSet set) {
  _current = set;
  decoder = set.decoder;
  dataVersion = set.version;
  dropSpelling(); // the spelling index is rebuilt from the new data when next needed
  dataStatus.value = dataStatus.value.copyWith(version: set.version, updated: set.dir != null);
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
    final u = await (await _theStore()).update(current, c, products: _products);
    if (u.products != null) {
      _products = u.products!;
      dataStatus.value = dataStatus.value.copyWith(products: _products.count);
    }
    if (u.check == DataCheck.failed) return DataCheck.failed;
    final now = DateTime.now();
    await prefs?.setString(_lastCheckKey, now.toIso8601String());
    dataStatus.value = dataStatus.value.copyWith(lastCheck: now);
    if (u.set != null && identical(_current, current)) _use(u.set!);
    return u.check;
  } catch (e) {
    if (kDebugMode) debugPrint('Data update: $e');
    return DataCheck.failed;
  } finally {
    if (client == null) c.close();
  }
}
