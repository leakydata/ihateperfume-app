import 'package:flutter/material.dart';

import '../engine/decoder.dart';
import '../main.dart';
import '../services.dart';
import '../theme.dart';
import 'ingredient.dart';
import 'result.dart';

/// Search every ingredient name we know: flagged ones first, then the ~33,000 real names with no flags.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _Entry {
  final String name;
  final String key;
  final int level; // worst flag level, 0 = no flags
  final String? chip;
  const _Entry(this.name, this.key, this.level, this.chip);
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  List<_Entry> _results = [];

  static List<(String, String)>? _flagged; // (name, normalized)
  static List<String>? _vocab;

  void _index() {
    if (_flagged != null) return;
    final seen = <String>{};
    _flagged = [
      for (final n in [...decoder.allergenNames, ...decoder.flaggedNames])
        if (seen.add(Decoder.norm(n))) (n, Decoder.norm(n))
    ];
    _vocab = decoder.vocab.where((v) => !seen.contains(v)).toList()..sort();
  }

  void _search(String raw) {
    _index();
    final q = Decoder.norm(raw);
    if (q.length < 2) {
      setState(() => _results = []);
      return;
    }
    final starts = <(String, String)>[], contains = <(String, String)>[];
    for (final e in _flagged!) {
      if (e.$2.startsWith(q)) {
        starts.add(e);
      } else if (e.$2.contains(q)) {
        contains.add(e);
      }
    }
    int byLen((String, String) a, (String, String) b) => a.$2.length - b.$2.length;
    starts.sort(byLen);
    contains.sort(byLen);
    final out = <_Entry>[];
    for (final e in [...starts, ...contains].take(40)) {
      final row = rowFor(e.$1, '');
      out.add(_Entry(e.$1, e.$2, row?.worst ?? 0, row?.chips.first.$1));
    }
    if (out.length < 40) {
      final more = _vocab!.where((v) => v.contains(q)).toList()
        ..sort((a, b) => (b.startsWith(q) ? 1 : 0) - (a.startsWith(q) ? 1 : 0) != 0
            ? (b.startsWith(q) ? 1 : 0) - (a.startsWith(q) ? 1 : 0)
            : a.length - b.length);
      for (final v in more.take(40 - out.length)) {
        out.add(_Entry(_title(v), v, 0, null));
      }
    }
    setState(() => _results = out);
  }

  static String _title(String s) => s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TopBar(left: Text('SEARCH', style: T.big(30).copyWith(height: 1))),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: TextField(
          controller: _q,
          focusNode: Shell.searchFocus,
          onChanged: _search,
          textInputAction: TextInputAction.search,
          style: T.src(size: 15, color: C.ink),
          decoration: InputDecoration(
            hintText: 'Search an ingredient…',
            hintStyle: T.src(size: 15, color: C.faint),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, color: C.ink),
                    onPressed: () {
                      _q.clear();
                      _search('');
                    }),
            enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero, borderSide: BorderSide(color: C.ink, width: 3)),
            focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero, borderSide: BorderSide(color: C.signal, width: 3)),
          ),
        ),
      ),
      Expanded(
        child: _results.isEmpty
            ? ListView(padding: const EdgeInsets.all(20), children: [
                Text(
                  _q.text.length < 2
                      ? 'Type a name from a label, like linalool, parfum, or methylisothiazolinone.'
                      : 'Nothing by that name. Check the spelling against the package.',
                  style: T.lede,
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final e = _results[i];
                  return Rule(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => IngredientScreen(name: e.name, back: 'Search'))),
                    child: Row(children: [
                      Expanded(child: Text(e.name, style: T.lede.copyWith(fontSize: 16))),
                      const SizedBox(width: 8),
                      e.chip == null ? Text('no flags', style: T.src(size: 11)) : Tag(e.chip!, level: e.level),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}
