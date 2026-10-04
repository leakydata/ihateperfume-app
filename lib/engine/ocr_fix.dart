/// Spelling suggestions for ingredient lists, mostly for text recognition mistakes ("Lim0nene", "Parfurn").
///
/// For each item that isn't a known ingredient name, find the closest real name. Nothing is changed here:
/// the review screen shows each suggestion and the user taps to use it. Runs on the phone; the decoder's
/// matching is untouched.
library;

import 'dart:typed_data';

import 'decoder.dart';

/// One suggested fix: replace text[start, end) ([from]) with [to].
class Suggestion {
  final int start;
  final int end;
  final String from;
  final String to;
  final double cost; // weighted edits (OCR confusions are cheap)
  const Suggestion(this.start, this.end, this.from, this.to, this.cost);
  @override
  String toString() => '$from -> $to (${cost.toStringAsFixed(2)})';
}

class OcrFix {
  final List<String> _names; // normalized known names
  final Set<String> _known;
  final List<int> _group; // same value = same flagged ingredient (ties between them are fine)
  final Map<String, String> _display; // normalized -> as written, for flagged names and allergens
  final List<Int32List?> _postings; // trigram -> name indexes
  final Int32List _count;

  OcrFix._(this._names, this._known, this._group, this._display, this._postings) : _count = Int32List(_names.length);

  /// Build the index once (about 32,000 names).
  factory OcrFix(Decoder d) {
    final display = <String, String>{};
    for (final n in [...d.flaggedNames, ...d.allergenNames]) {
      final k = Decoder.norm(n);
      if (k.isNotEmpty && n.contains(RegExp('[A-Z]'))) display.putIfAbsent(k, () => n);
    }
    final known = <String>{
      ...d.vocab,
      ...d.knownNames,
      for (final n in [...d.flaggedNames, ...d.allergenNames]) Decoder.norm(n),
      // The decoder's own fragrance words.
      'fragrance', 'parfum', 'perfume', 'aroma', 'flavor', 'flavour', 'essential oil', 'essential oils',
    }..remove('');
    final names = known.toList();
    final group = <int>[for (var i = 0; i < names.length; i++) d.itemIndex(names[i]) ?? -1 - i];
    final lists = List<List<int>?>.filled(_gramSpace, null);
    for (var i = 0; i < names.length; i++) {
      for (final g in _grams(names[i])) {
        final l = lists[g] ??= <int>[];
        if (l.isEmpty || l.last != i) l.add(i);
      }
    }
    final postings = [for (final l in lists) l == null ? null : Int32List.fromList(l)];
    return OcrFix._(names, known, group, display, postings);
  }

  bool isKnown(String normalized) => _known.contains(normalized);

  // ---------- splitting with positions (mirrors Decoder.split) ----------

  static final _sep = RegExp(r'[,;\n•·●|]+');
  static final _prefix = RegExp(r'^\s*(ingredients?|inci)\s*:\s*', caseSensitive: false);
  static final _tail = RegExp(r'[.*\s]+$');

  /// The items of [text] as (start, end) spans; their text equals Decoder.split(text).
  static List<(int, int)> spans(String text) {
    final out = <(int, int)>[];
    void seg(int s, int e) {
      final p = _prefix.firstMatch(text.substring(s, e));
      if (p != null) s += p.end;
      final t = _tail.firstMatch(text.substring(s, e));
      if (t != null) e = s + t.start;
      while (s < e && _isSpace(text.codeUnitAt(s))) {
        s++;
      }
      while (e > s && _isSpace(text.codeUnitAt(e - 1))) {
        e--;
      }
      if (s < e) out.add((s, e));
    }

    var pos = 0;
    for (final m in _sep.allMatches(text)) {
      seg(pos, m.start);
      pos = m.end;
    }
    seg(pos, text.length);
    return out;
  }

  static bool _isSpace(int c) => c == 32 || (c >= 9 && c <= 13) || c == 0xA0;

  // ---------- suggestions ----------

  static final _parts = RegExp(r'[^()\[\]/]+');
  static final _numbersOnly = RegExp(r'^[0-9 ]+$');
  static final _trailingNumbers = RegExp(r'( [0-9]+)+$');

  /// Suggestions for every item in [text] that isn't a known name, in text order.
  List<Suggestion> suggest(String text) {
    final out = <Suggestion>[];
    for (final (s, e) in spans(text)) {
      final item = text.substring(s, e);
      if (_skip(Decoder.norm(item))) continue;
      if (item.contains(RegExp(r'[()\[\]/]'))) {
        // "Aqua (Watre)", "Water/Aqua/Eau": check each part on its own.
        for (final m in _parts.allMatches(item)) {
          var ps = m.start, pe = m.end;
          while (ps < pe && _isSpace(item.codeUnitAt(ps))) {
            ps++;
          }
          while (pe > ps && _isSpace(item.codeUnitAt(pe - 1))) {
            pe--;
          }
          if (ps < pe) _one(text, s + ps, s + pe, out);
        }
      } else {
        _one(text, s, e, out);
      }
    }
    return out;
  }

  /// Known, too short, a number, or "Glycerin 2%": nothing to suggest.
  bool _skip(String k) {
    if (k.replaceAll(RegExp('[^a-z]'), '').length < 4) return true;
    if (_numbersOnly.hasMatch(k)) return true;
    if (_known.contains(k)) return true;
    final bare = k.replaceFirst(_trailingNumbers, '');
    if (bare != k && _known.contains(bare)) return true;
    // Plural or singular of a known name ("Enzymes", "Fragrances").
    if (k.endsWith('s') && _known.contains(k.substring(0, k.length - 1))) return true;
    if (_known.contains('${k}s')) return true;
    return false;
  }

  void _one(String text, int s, int e, List<Suggestion> out) {
    final raw = text.substring(s, e);
    final k = Decoder.norm(raw);
    if (_skip(k)) return;
    final best = _best(k);
    final two = best != null && best.$2 <= .5 ? null : _splitTwo(k);
    if (two != null) {
      out.add(Suggestion(s, e, raw, '${_styled(two.$1, raw)}, ${_styled(two.$2, raw)}', 1));
    } else if (best != null) {
      final to = _styled(best.$1, raw);
      if (to != raw) out.add(Suggestion(s, e, raw, to, best.$2));
    }
  }

  /// A missing comma: "Glycerin Parfum" is two known names.
  (String, String)? _splitTwo(String k) {
    for (var i = k.indexOf(' '); i > 0; i = k.indexOf(' ', i + 1)) {
      final a = k.substring(0, i), b = k.substring(i + 1);
      if (a.length >= 3 && b.length >= 3 && _known.contains(a) && _known.contains(b)) return (a, b);
    }
    return null;
  }

  /// The closest known name, if it is close enough and clearly closer than any other ingredient.
  (String, double)? _best(String k) {
    final q = <int>{..._grams(k), ..._grams(_foldDigits(k)), ..._grams(k.replaceAll('rn', 'm'))};
    final own = _grams(k).length;
    final touched = <int>[];
    for (final g in q) {
      final p = _postings[g];
      if (p == null) continue;
      for (final i in p) {
        if (_count[i]++ == 0) touched.add(i);
      }
    }
    final minShared = (own * .3).ceil();
    final slack = k.length * .35 < 3 ? 3 : (k.length * .35).round();
    final cands = <int>[];
    for (final i in touched) {
      if (_count[i] >= minShared && (_names[i].length - k.length).abs() <= slack) cands.add(i);
    }
    final shared = {for (final i in cands) i: _count[i]};
    for (final i in touched) {
      _count[i] = 0;
    }
    cands.sort((a, b) => shared[b]! - shared[a]!);
    if (cands.length > 60) cands.length = 60;

    var bestI = -1;
    var bestD = double.infinity, secondD = double.infinity;
    for (final i in cands) {
      final d = wdist(k, _names[i], secondD);
      if (d < bestD) {
        if (bestI >= 0 && _group[bestI] != _group[i]) secondD = bestD;
        bestD = d;
        bestI = i;
      } else if (d < secondD && _group[i] != _group[bestI]) {
        secondD = d;
      }
    }
    if (bestI < 0) return null;
    final name = _names[bestI];
    final longest = name.length > k.length ? name.length : k.length;
    if (bestD > 3 || bestD > longest * .25) return null;
    if (secondD - bestD < .6) return null; // two different ingredients about as close: don't guess
    return (name, bestD);
  }

  // ---------- trigrams ----------

  static const _gramSpace = 40 * 40 * 40;

  static int _code(int c) {
    if (c == 32) return 1;
    if (c >= 97 && c <= 122) return c - 95; // a-z: 2..27
    if (c >= 48 && c <= 57) return c - 20; // 0-9: 28..37
    return 38;
  }

  static List<int> _grams(String s) {
    final c = [0, for (final u in s.codeUnits) _code(u), 0];
    return [for (var i = 0; i + 2 < c.length; i++) (c[i] * 40 + c[i + 1]) * 40 + c[i + 2]];
  }

  static String _foldDigits(String s) => s.replaceAllMapped(RegExp('[0158]'), (m) {
        return const {'0': 'o', '1': 'l', '5': 's', '8': 'b'}[m[0]]!;
      });

  // ---------- weighted edit distance ----------

  static const _cheap = .3;
  static final Set<int> _confusable = () {
    const pairs = ['0o', '1l', '1i', 'il', '5s', '8b', 'ec', 'tf', 'uv', '6b', '9g', '2z', '0d'];
    return {
      for (final p in pairs) ...[p.codeUnitAt(0) << 8 | p.codeUnitAt(1), p.codeUnitAt(1) << 8 | p.codeUnitAt(0)]
    };
  }();
  // Two letters read as one: rn/m, cl/d, vv/w, li/h, ii/u.
  static final Set<int> _merged = {
    for (final p in ['rnm', 'cld', 'vvw', 'lih', 'iiu'])
      p.codeUnitAt(0) << 16 | p.codeUnitAt(1) << 8 | p.codeUnitAt(2)
  };

  static bool _digit(int c) => c >= 48 && c <= 57;

  static double _sub(int a, int b) {
    if (a == b) return 0;
    if (_confusable.contains(a << 8 | b)) return _cheap;
    if (_digit(a) && _digit(b)) return 3; // never turn one number into another (PEG-40 vs PEG-45)
    return 1;
  }

  static double _indel(int c) => c == 32 ? _cheap : (_digit(c) ? 2 : 1);

  /// Edit distance from [a] (as read) to [b] (a real name) with OCR-aware costs and transpositions.
  /// Returns at least [cap] early once every path costs more than [cap].
  static double wdist(String a, String b, [double cap = double.infinity]) {
    final n = a.length, m = b.length;
    var p2 = Float64List(m + 1), p1 = Float64List(m + 1), cur = Float64List(m + 1);
    for (var j = 1; j <= m; j++) {
      p1[j] = p1[j - 1] + _indel(b.codeUnitAt(j - 1));
    }
    for (var i = 1; i <= n; i++) {
      final ai = a.codeUnitAt(i - 1);
      cur[0] = p1[0] + _indel(ai);
      var rowMin = cur[0];
      for (var j = 1; j <= m; j++) {
        final bj = b.codeUnitAt(j - 1);
        var v = p1[j - 1] + _sub(ai, bj);
        final del = p1[j] + _indel(ai);
        if (del < v) v = del;
        final ins = cur[j - 1] + _indel(bj);
        if (ins < v) v = ins;
        if (i > 1 && j > 1) {
          final ap = a.codeUnitAt(i - 2), bp = b.codeUnitAt(j - 2);
          if (ai == bp && ap == bj && ai != bj && p2[j - 2] + 1 < v) v = p2[j - 2] + 1;
        }
        if (i > 1 && _merged.contains(a.codeUnitAt(i - 2) << 16 | ai << 8 | bj) && p2[j - 1] + _cheap < v) {
          v = p2[j - 1] + _cheap;
        }
        if (j > 1 && _merged.contains(b.codeUnitAt(j - 2) << 16 | bj << 8 | ai) && p1[j - 2] + _cheap < v) {
          v = p1[j - 2] + _cheap;
        }
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > cap) return rowMin;
      final t = p2;
      p2 = p1;
      p1 = cur;
      cur = t;
    }
    return p1[m];
  }

  // ---------- display ----------

  static const _upper = {'peg', 'ppg', 'ci', 'edta', 'dmdm', 'dea', 'mea', 'tea', 'mipa', 'bht', 'bha', 'pvp', 'pca', 'hcl', 'pg', 'sd', 'aha', 'uv', 'fd', 'hc'};

  /// A normalized name as it is usually written: "PEG-40 Hydrogenated Castor Oil", "Sodium Laureth Sulfate".
  String pretty(String k) {
    final shown = _display[k];
    if (shown != null) return shown;
    final w = k.split(' ');
    final b = StringBuffer();
    for (var i = 0; i < w.length; i++) {
      final t = w[i];
      if (i > 0) {
        final prev = w[i - 1];
        final hyphen = _digit(t.codeUnitAt(0)) &&
            !_digit(prev.codeUnitAt(0)) &&
            (prev == 'peg' || prev == 'ppg' || prev.endsWith('eth') || prev.endsWith('quaternium'));
        b.write(hyphen ? '-' : ' ');
      }
      if (_upper.contains(t) || (t.length <= 3 && !t.contains(RegExp('[aeiouy]')))) {
        b.write(t.toUpperCase());
      } else {
        b.write(t[0].toUpperCase() + t.substring(1));
      }
    }
    return b.toString();
  }

  /// Keep the writer's style: ALL CAPS stays caps, all lowercase stays lowercase, otherwise the usual way.
  String _styled(String k, String raw) {
    final letters = raw.replaceAll(RegExp('[^A-Za-z]'), '');
    // Mostly caps counts as caps: text recognition often reads a capital I as a lowercase l ("GLYCERlN").
    final caps = letters.replaceAll(RegExp('[^A-Z]'), '').length;
    if (letters.length > 1 && caps >= letters.length * .75) return pretty(k).toUpperCase();
    if (letters.isNotEmpty && letters == letters.toLowerCase()) return pretty(k).toLowerCase();
    return pretty(k);
  }

  /// Apply one suggestion; returns [text] unchanged if it no longer matches.
  static String apply(String text, Suggestion s) {
    if (s.end > text.length || text.substring(s.start, s.end) != s.from) return text;
    return text.replaceRange(s.start, s.end, s.to);
  }

  /// Apply several suggestions (from the same text) at once.
  static String applyAll(String text, List<Suggestion> all) {
    final sorted = [...all]..sort((a, b) => b.start - a.start);
    for (final s in sorted) {
      text = apply(text, s);
    }
    return text;
  }
}
