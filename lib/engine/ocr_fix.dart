/// Spelling suggestions for ingredient lists, mostly for text recognition mistakes ("Lim0nene", "Parfurn").
///
/// For each item that isn't a known ingredient name, find the closest real name, or say it looks like label
/// text (an address, a lot number, directions) or is unknown. Nothing is changed here: the review screen shows
/// each issue and the user taps to fix or remove it. Runs on the phone; the decoder's matching is untouched.
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

/// What an item that isn't a known name probably is.
enum IssueKind {
  /// A misread name with one confident fix ([Issue.to]).
  suggestion,

  /// Not a name we know and no confident fix: the user should check it.
  unknown,

  /// Not an ingredient at all: an address, a lot number, directions, and so on.
  labelText,
}

/// An item (or part of one) in text[start, end) ([from]) that isn't a known name.
class Issue {
  final int start;
  final int end;
  final String from;
  final String? to; // only for IssueKind.suggestion
  final IssueKind kind;
  const Issue(this.start, this.end, this.from, this.to, this.kind);
  @override
  String toString() => '${kind.name}: $from${to == null ? '' : ' -> $to'}';
}

class _Fix extends Issue {
  final double cost;
  const _Fix(int start, int end, String from, String to, this.cost)
      : super(start, end, from, to, IssueKind.suggestion);
}

class OcrFix {
  final List<String> _names; // normalized known names
  final Set<String> _known;
  final List<int> _group; // same value = same flagged ingredient (ties between them are fine)
  final Map<String, String> _display; // normalized -> as written, for flagged names and allergens
  final List<Int32List?> _postings; // trigram -> name indexes
  final Int32List _count;

  final Set<String> _words; // every word of a known name ("vitamin", "shea", "rose")

  OcrFix._(this._names, this._known, this._group, this._display, this._postings)
      : _count = Int32List(_names.length),
        _words = {for (final n in _names) ...n.split(' '), ..._commonWords};

  // Common names labels put in brackets after the INCI name, which INCI names themselves don't use.
  static const _commonWords = {
    'vitamin', 'vitamins', 'provitamin', 'a', 'b1', 'b2', 'b3', 'b5', 'b6', 'b7', 'b12', 'c', 'd', 'd3', 'e', 'k',
    'eau', 'agua', 'acqua', 'wasser',
  };

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

  // ---------- checking every item ----------

  static final _parts = RegExp(r'[^()\[\]/]+');
  static final _hasParts = RegExp(r'[()\[\]/]');
  static final _bracketGroup = RegExp(r'\([^()]*\)|\[[^\[\]]*\]');
  static final _afterBracket = RegExp(r'^(.*[)\]])\s+([^()\[\]/]+)$');
  static final _numbersOnly = RegExp(r'^[0-9 ]+$');
  static final _trailingNumbers = RegExp(r'( [0-9]{1,4})+$'); // "Glycerin 2%", not a lot number
  static final _ciNumber = RegExp(r'^ci [0-9]{5}$');
  static final _fragranceWord = RegExp(r'\b(fragrances?|parfums?|perfumes?|aroma|flavou?rs?|essential oils?|masking)\b');

  /// Suggestions for every item in [text] that isn't a known name, in text order.
  List<Suggestion> suggest(String text) => [
        for (final i in check(text))
          if (i is _Fix) Suggestion(i.start, i.end, i.from, i.to!, i.cost)
      ];

  /// Every item in [text] (or part of one) that isn't a known name, in text order: a confident fix, label text
  /// that isn't an ingredient, or unknown.
  List<Issue> check(String text) {
    final out = <Issue>[];
    var lastKnownEnd = -1; // end of the last item that matched a known name
    for (final (s, e) in spans(text)) {
      final before = out.length;
      _item(text, s, e, out);
      if (out.length == before) lastKnownEnd = e;
    }
    // A footer runs to the end of the text: once label text starts after the last known ingredient, the
    // unrecognized pieces that follow ("Dallas" between "Distributed by…" and "TX 75201") are label text too.
    final first = out.indexWhere((i) => i.kind == IssueKind.labelText && i.start > lastKnownEnd);
    if (first >= 0) {
      for (var j = first + 1; j < out.length; j++) {
        final i = out[j];
        if (i.kind == IssueKind.unknown) out[j] = Issue(i.start, i.end, i.from, null, IssueKind.labelText);
      }
    }
    return out;
  }

  void _item(String text, int s, int e, List<Issue> out) {
    final item = text.substring(s, e);
    final k = Decoder.norm(item);
    if (k.isEmpty || _recognized(k)) return;
    if (!item.contains(_hasParts)) {
      _span(text, s, e, out, label: true);
      return;
    }
    // A missing comma after brackets: "Panthenol [Vitamin B5] Glycol Distearate".
    final mc = _afterBracket.firstMatch(item);
    if (mc != null) {
      final head = mc[1]!.trimRight(), tail = mc[2]!.trim();
      final headBare = Decoder.norm(head.replaceAll(_bracketGroup, ' '));
      final tk = Decoder.norm(tail);
      if (headBare.isNotEmpty &&
          _recognized(headBare) &&
          _known.contains(tk) &&
          _letters(tk) >= 4 &&
          !_continues.contains(tk.split(' ').first) &&
          !_recognized(Decoder.norm(item.replaceAll(_bracketGroup, ' ')))) {
        out.add(_Fix(s, e, item, '$head, $tail', 1));
        return;
      }
    }
    // "Aqua (Watre)", "Water/Aqua/Eau": check each part on its own.
    final parts = <Issue>[];
    // A known name with a common name in brackets ("Rosa Damascena (Rose) Flower Oil", "Panthenol [Vitanmin 85]"):
    // only a confident fix, or a part with a word that is in no known name.
    final bareKnown = _recognized(Decoder.norm(item.replaceAll(_bracketGroup, ' ')));
    for (final m in _parts.allMatches(item)) {
      var ps = m.start, pe = m.end;
      while (ps < pe && _isSpace(item.codeUnitAt(ps))) {
        ps++;
      }
      while (pe > ps && _isSpace(item.codeUnitAt(pe - 1))) {
        pe--;
      }
      if (ps < pe) _span(text, s + ps, s + pe, parts, label: false);
    }
    if (bareKnown) parts.removeWhere((p) => p.kind != IssueKind.suggestion && _knownWords(Decoder.norm(p.from)));
    if (parts.isEmpty) return;
    // A part that makes no sense alone ("Acrylates/CI0-30 Alkyl Acrylate Crosspolymer"): try the whole name.
    if (item.contains('/') && parts.any((p) => p.kind != IssueKind.suggestion)) {
      final f = _fix(item, k);
      if (f != null && f.$1 != item) {
        out.add(_Fix(s, e, item, f.$1, f.$2));
        return;
      }
    }
    // A missing comma before a slashed name: "Lauryl Lactate Acrylates/CI0-30 Alkyl Acrylate Crosspolymer".
    if (parts.any((p) => p.kind != IssueKind.suggestion)) {
      final f = _headTail(item);
      if (f != null) {
        out.add(_Fix(s, e, item, f.$1, f.$2));
        return;
      }
    }
    out.addAll(parts);
  }

  // Words that carry on a name after brackets ("Rosa Damascena (Rose) Flower Oil"), so no missing comma there.
  static const _continues = {
    'oil', 'oils', 'extract', 'butter', 'flower', 'leaf', 'seed', 'root', 'fruit', 'water', 'juice', 'powder', 'wax',
    'peel', 'bark', 'kernel', 'nut', 'stem', 'callus', 'cell', 'culture', 'ferment', 'filtrate', 'lysate', 'hydrolysate',
    'essential', 'absolute', 'distillate', 'flour', 'protein', 'acid', 'esters', 'blossom', 'berry', 'sprout',
  };

  /// One item or part with no brackets.
  void _span(String text, int s, int e, List<Issue> out, {required bool label}) {
    final raw = text.substring(s, e);
    final k = Decoder.norm(raw);
    if (k.isEmpty || _recognized(k)) return;
    if (_letters(k) < 4) {
      // "P500", "0299393816", "Zq".
      if (_numbersOnly.hasMatch(k) || (_looksLikeLabel(raw) && !_eNumber.hasMatch(raw.trim()))) {
        out.add(Issue(s, e, raw, null, IssueKind.labelText));
      } else if (!_knownWords(k)) {
        out.add(Issue(s, e, raw, null, IssueKind.unknown));
      }
      return;
    }
    // A name with label text glued on: "Sodium Hydroxide 0299393816 Galderma Distributed by: ...".
    if (label) {
      final p = _labelStart(raw);
      if (p != null && p > 0) {
        var he = p;
        while (he > 0 && (_isSpace(raw.codeUnitAt(he - 1)) || raw[he - 1] == ':')) {
          he--;
        }
        final head = raw.substring(0, he), hk = Decoder.norm(head);
        final tail = raw.substring(p), tk = Decoder.norm(tail);
        if (_letters(hk) >= 4 && !_containsKnown(tk)) {
          final f = _recognized(hk) ? null : _fix(head, hk);
          if (_recognized(hk) || f != null) {
            if (f != null && f.$1 != head) out.add(_Fix(s, s + he, head, f.$1, f.$2));
            out.add(Issue(s + p, e, tail, null, IssueKind.labelText));
            return;
          }
        }
      }
    }
    if (_looksLikeLabel(raw) && !_containsKnown(k)) {
      out.add(Issue(s, e, raw, null, IssueKind.labelText));
      return;
    }
    final f = _fix(raw, k) ?? _headTail(raw);
    if (f != null) {
      if (f.$1 != raw) out.add(_Fix(s, e, raw, f.$1, f.$2));
      return;
    }
    // The decoder flags any short item with a fragrance word in it ("Masking Fragrance").
    if (_fragranceWord.hasMatch(k) && k.split(' ').length <= 4) return;
    out.add(Issue(s, e, raw, null, IssueKind.unknown));
  }

  static int _letters(String k) {
    var n = 0;
    for (final c in k.codeUnits) {
      if (c >= 97 && c <= 122) n++;
    }
    return n;
  }

  /// A known name, a color index number, "Glycerin 2%", or a plural or singular of a known name.
  bool _recognized(String k) {
    if (_known.contains(k) || _ciNumber.hasMatch(k)) return true;
    final bare = k.replaceFirst(_trailingNumbers, '');
    if (bare != k && _known.contains(bare)) return true;
    // Plural or singular of a known name ("Enzymes", "Fragrances").
    if (k.endsWith('s') && _known.contains(k.substring(0, k.length - 1))) return true;
    if (_known.contains('${k}s')) return true;
    return false;
  }

  /// Every word of [k] is a word of some known name (numbers count as known).
  bool _knownWords(String k) {
    for (final w in k.split(' ')) {
      if (!_words.contains(w) && !_numbersOnly.hasMatch(w)) return false;
    }
    return true;
  }

  /// A known name of 4 or more letters anywhere in [k] (whole words).
  bool _containsKnown(String k) {
    final w = k.split(' ');
    for (var i = 0; i < w.length; i++) {
      var phrase = '';
      for (var j = i; j < w.length && j < i + 6; j++) {
        phrase = j == i ? w[i] : '$phrase ${w[j]}';
        if (_letters(phrase) >= 4 && _known.contains(phrase)) return true;
      }
    }
    return false;
  }

  /// The best fix for one item or part: a close known name, or two known names missing a comma.
  (String, double)? _fix(String raw, String k) {
    final best = _best(k);
    final two = best != null && best.$2 <= .5 ? null : _splitTwo(k);
    if (two != null) return ('${_styled(two.$1, raw)}, ${_styled(two.$2, raw)}', 1);
    if (best != null) return (_styled(best.$1, raw), best.$2);
    return null;
  }

  static final _gap = RegExp(r'\s+');

  /// A missing comma after a known name, before a misread one: split at a space into a head that is a known name
  /// as written and a tail that is known or has a confident fix. A slash stays inside the tail
  /// ("Acrylates/C10-30 Alkyl Acrylate Crosspolymer" is one name).
  (String, double)? _headTail(String raw) {
    for (final m in _gap.allMatches(raw)) {
      final head = raw.substring(0, m.start), tail = raw.substring(m.end);
      if (head.contains(_hasParts)) break; // only a plain name before the gap
      final hk = Decoder.norm(head), tk = Decoder.norm(tail);
      if (_letters(hk) < 4 || _letters(tk) < 4 || !_known.contains(hk)) continue;
      final tw = tk.split(' ');
      if (_continues.contains(tw.first)) continue; // "... Seed Oil" carries the name on
      if (_known.contains(tk)) return ('$head, $tail', 1);
      // A misread tail: only a name of two or more words, so one short word is never guessed ("Sodium Octrate").
      if (tw.length < 2) continue;
      final f = _fix(tail, tk);
      if (f != null && !f.$1.contains(', ')) return ('$head, ${f.$1}', 1 + f.$2);
    }
    return null;
  }

  // ---------- label text ----------

  static const _states = 'AL|AK|AZ|AR|CA|CO|CT|DE|DC|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|'
      'NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY';
  static final _labelSigns = [
    RegExp(r'[0-9]{7,}'), // lot number or barcode
    RegExp(r'''\b[0-9]{1,6}(?:[ "'’.][0-9]{2,6}){2,}\b'''), // a barcode read with gaps or quotes: 3 02993"93816
    RegExp(r'\b(?:' + _states + r')\.?,?\s+[0-9]{5}(?:-[0-9]{4})?\b'), // state and zip
    RegExp(r'\(?\b[0-9]{3}\)?[\s.-][0-9]{3}[\s.-][0-9]{4}\b'), // phone
    RegExp(r'www\.|https?:|\b[a-z0-9-]+\.(?:com|net|org)\b|\S@\S+\.[a-z]{2,}', caseSensitive: false),
    RegExp(r'\b(?:inc|llc|ltd|corp|gmbh|laboratories|laboratoires)\b|\bCo\.'),
    RegExp(r'\b(?:Inc|LLC|Ltd|Corp|GmbH|Laboratories|Laboratoires)\b', caseSensitive: false),
    RegExp(
        r'\b(?:distributed|dist\.?\s*by|manufactured|mfd|made\s+in|product\s+of|trademarks?|directions|warnings?|'
        r'caution|questions|net\s+wt|apply|rinse|keep\s+out|avoid\s+contact)\b',
        caseSensitive: false),
  ];
  static final _code6 = RegExp(r'^[A-Za-z]{1,2}[0-9]{3,}(?:-[0-9]+)?$'); // "P500", "P202418-0"
  static final _eNumber = RegExp(r'^[Ee][0-9]{3,4}[a-z]?$'); // a food additive number, not label text
  static const _stop = {
    'the', 'a', 'an', 'to', 'your', 'you', 'after', 'before', 'into', 'onto', 'is', 'are', 'be', 'if', 'for', 'or',
    'on', 'use', 'with', 'by', 'of', 'all', 'their', 'and', 'any', 'not', 'do', 'this', 'from', 'in', 'at',
  };

  /// Where label text starts in an item, if it has a clear sign of it.
  static int? _labelStart(String raw) {
    int? first;
    for (final r in _labelSigns) {
      final m = r.firstMatch(raw);
      if (m != null && (first == null || m.start < first)) first = m.start;
    }
    return first;
  }

  /// An address, a phone number, a web address, a company, directions, a lot number, a code, or a sentence.
  static bool _looksLikeLabel(String raw) {
    final t = raw.trim();
    if (_labelStart(t) != null) return true;
    if (_code6.hasMatch(t) && !_eNumber.hasMatch(t)) return true;
    final words = RegExp(r"[A-Za-z][A-Za-z'’]*").allMatches(t).map((m) => m[0]!).toList();
    final stop = words.where((w) => _stop.contains(w.toLowerCase())).length;
    final lower = words.where((w) => w[0] == w[0].toLowerCase()).length;
    if (words.length >= 4 && stop >= 2) return true;
    return words.length >= 6 && stop >= 1 && lower * 2 >= words.length;
  }

  // ---------- suggestions ----------

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
    // Up to 3 edits; long names a little more ("Dig0dim m Aureth Sulfosuccinate").
    if (bestD > (longest * .12 > 3 ? longest * .12 : 3) || bestD > longest * .25) return null;
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
    var shown = pretty(k);
    // Same number of words: keep the label's own punctuation between them ("Acrylates/C10-30 Alkyl ...").
    final words = _word.allMatches(raw).toList();
    final kw = k.split(' ');
    if (words.length > 1 && words.length == kw.length && Decoder.norm(raw).split(' ').length == kw.length) {
      final pw = shown.split(RegExp('[ -]'));
      if (pw.length == kw.length) {
        final b = StringBuffer(pw[0]);
        for (var i = 1; i < pw.length; i++) {
          final gap = raw.substring(words[i - 1].end, words[i].start);
          b
            ..write(gap.trim().isEmpty ? ' ' : gap.trim())
            ..write(pw[i]);
        }
        shown = b.toString();
      }
    }
    final letters = raw.replaceAll(RegExp('[^A-Za-z]'), '');
    // Mostly caps counts as caps: text recognition often reads a capital I as a lowercase l ("GLYCERlN").
    final caps = letters.replaceAll(RegExp('[^A-Z]'), '').length;
    if (letters.length > 1 && caps >= letters.length * .75) return shown.toUpperCase();
    if (letters.isNotEmpty && letters == letters.toLowerCase()) return shown.toLowerCase();
    return shown;
  }

  static final _word = RegExp(r"[\p{L}\p{N}'’`]+", unicode: true);

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

  /// Remove the [issues] (from the same text) and one separator next to each, so the list still reads cleanly.
  /// Skips any issue whose text no longer matches.
  static String removeAll(String text, List<Issue> issues) {
    final sorted = [...issues]..sort((a, b) => b.start - a.start);
    var limit = text.length; // skip an issue that overlaps one already removed
    for (final i in sorted) {
      if (i.start < 0 || i.end > limit || i.start >= i.end || text.substring(i.start, i.end) != i.from) continue;
      limit = i.start;
      text = _removeSpan(text, i.start, i.end);
    }
    return text;
  }

  static bool _isSep(int c) => '\n,;•·●|'.codeUnits.contains(c);

  static String _removeSpan(String text, int s, int e) {
    final s0 = s;
    // Take the spaces around it, and brackets left empty ("Panthenol [Vitanmin 85]").
    while (true) {
      while (s > 0 && _isSpace(text.codeUnitAt(s - 1)) && text.codeUnitAt(s - 1) != 10) {
        s--;
      }
      while (e < text.length && _isSpace(text.codeUnitAt(e)) && text.codeUnitAt(e) != 10) {
        e++;
      }
      if (s > 0 && e < text.length) {
        final o = text[s - 1], c = text[e];
        if ((o == '(' && c == ')') || (o == '[' && c == ']')) {
          s--;
          e++;
          continue;
        }
      }
      break;
    }
    // A whole item: from the start of the text or a separator to a separator, a final period, or the end.
    var after = e;
    while (after < text.length &&
        (text[after] == '.' ||
            text[after] == '*' ||
            (_isSpace(text.codeUnitAt(after)) && text.codeUnitAt(after) != 10))) {
      after++;
    }
    final startsItem = s == 0 || _isSep(text.codeUnitAt(s - 1));
    final endsItem = after == text.length || _isSep(text.codeUnitAt(after));
    if (startsItem && endsItem) {
      if (after < text.length) {
        // "A, X, B": take X and the separator after it.
        var n = after;
        while (n < text.length && (_isSep(text.codeUnitAt(n)) || _isSpace(text.codeUnitAt(n)))) {
          n++;
        }
        var f = s; // keep the space after the previous separator
        while (f < s0 && _isSpace(text.codeUnitAt(f))) {
          f++;
        }
        return text.replaceRange(f, n, '');
      }
      // The last item: take the separator before it, keep a final period ("A, X." -> "A.").
      var b = s;
      while (b > 0 && (_isSep(text.codeUnitAt(b - 1)) || _isSpace(text.codeUnitAt(b - 1)))) {
        b--;
      }
      return text.replaceRange(b, e, '');
    }
    // Part of an item: keep one space between what is left on each side.
    final left = s > 0 ? text[s - 1] : '', right = e < text.length ? text[e] : '';
    final space = left.isNotEmpty &&
        right.isNotEmpty &&
        !'([/'.contains(left) &&
        !')]/.,;'.contains(right) &&
        !_isSep(left.codeUnitAt(0)) &&
        !_isSep(right.codeUnitAt(0));
    return text.replaceRange(s, e, space ? ' ' : '');
  }
}
