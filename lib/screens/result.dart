import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/decoder.dart';
import '../report.dart';
import '../services.dart';
import '../theme.dart';
import 'ingredient.dart';
import 'review.dart';
import 'scanner.dart';

const sourceNames = {
  'obf': 'From Open Beauty Facts',
  'opf': 'From Open Products Facts',
  'photo': 'From your photo',
  'typed': 'Typed in',
};

class ResultScreen extends StatefulWidget {
  final String text;
  final String? name;
  final String? barcode;
  final String source;
  final bool save; // add to recent scans
  const ResultScreen(
      {super.key, required this.text, this.name, this.barcode, required this.source, this.save = false});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  String _ptype = '';
  late Report _r = Report.build(decoder, widget.text);
  bool _showUnflagged = false;
  bool _showLimits = false;

  String get _name => widget.name?.isNotEmpty == true ? widget.name! : 'Ingredient list';

  @override
  void initState() {
    super.initState();
    Prefs.productType().then((t) {
      if (!mounted) return;
      setState(() {
        _ptype = t;
        _r = Report.build(decoder, widget.text, ptype: t);
      });
      if (widget.save) {
        final (tag, level) = _r.tag;
        History.add(Scan(_name, widget.barcode, widget.text, widget.source, DateTime.now(), tag, level));
      }
    });
  }

  void _setType(String t) {
    Prefs.setProductType(t);
    setState(() {
      _ptype = t;
      _r = Report.build(decoder, widget.text, ptype: t);
    });
  }

  void _home() => Navigator.of(context).popUntil((r) => r.isFirst);

  void _share() {
    final url =
        'https://ihateperfume.com/label-decoder/#i=${Uri.encodeComponent(_r.result.items.join(', '))}${_ptype.isEmpty ? '' : '&t=$_ptype'}';
    final lines = [
      'I Hate Perfume app results: $_name',
      _r.verdictLine,
      '',
      for (final row in _r.rows) '- ${row.item}: ${row.chips.map((c) => c.$1).join(', ')}',
      '',
      'Check your own label: $url',
    ];
    SharePlus.instance.share(ShareParams(text: lines.join('\n'), subject: 'Label check: $_name'));
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final meta = [
      sourceNames[widget.source] ?? '',
      if (widget.barcode != null) 'Barcode ${widget.barcode}',
    ].where((x) => x.isNotEmpty).join(' · ');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _home();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            TopBar(
              left: TopBar.back(context, 'Scan', onTap: _home),
              right: r.empty
                  ? null
                  : InkWell(
                      onTap: _share,
                      child: const Padding(padding: EdgeInsets.all(8), child: Mono('Share', color: C.signal))),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 24), children: [
                Mono(meta, color: const Color(0xFF666666), size: 11),
                const SizedBox(height: 6),
                Big(_name, size: 36),
                const SizedBox(height: 12),
                if (r.empty)
                  const Text('No ingredients found in that text.', style: T.lede)
                else ...[
                  VerdictBox(
                    level: r.boxLevel,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Big(r.headline, size: 26),
                      const SizedBox(height: 6),
                      if (r.declared != null) ...[
                        Text.rich(TextSpan(style: T.lede, children: [
                          const TextSpan(text: 'Including '),
                          TextSpan(text: r.declared, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const TextSpan(text: ': not one ingredient, a hidden mixture the label doesn’t have to name.'),
                        ])),
                        const SizedBox(height: 6),
                      ],
                      Text(r.verdictLine, style: T.lede.copyWith(fontSize: 14)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  _productType(),
                  if (_ptype == 'home')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          'EU cosmetics rules don’t cover cleaners and detergents, so “banned” or “restricted in EU '
                          'cosmetics” shows how an ingredient is treated in cosmetics. The hazard classifications '
                          '(allergen, carcinogen, hormone disruptor) apply to the chemical in any product.',
                          style: T.src()),
                    ),
                  const SizedBox(height: 4),
                  for (final row in r.rows) _row(row),
                  const SizedBox(height: 10),
                  if (r.unflagged.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() => _showUnflagged = !_showUnflagged),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '+ ${r.unflagged.length} ingredient${r.unflagged.length == 1 ? '' : 's'} with no flags. '
                          'Not on a list doesn’t mean safe; it may never have been assessed. '
                          '${_showUnflagged ? 'Hide them.' : 'Show them.'}',
                          style: T.src(),
                        ),
                      ),
                    ),
                  if (_showUnflagged)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final u in r.unflagged)
                          InkWell(onTap: () => _openIngredient(u, null), child: Tag(u, level: 1, size: 10)),
                      ]),
                    ),
                  if (r.scentCount == 0) ...[
                    const SizedBox(height: 14),
                    Panel(
                      child: Text(
                          'No fragrance on our lists is a good sign, but not a guarantee. ${decoder.caution}',
                          style: T.lede.copyWith(fontSize: 14)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (widget.source == 'obf' || widget.source == 'opf')
                    Text(
                      'Ingredient list from ${widget.source == 'obf' ? 'Open Beauty Facts' : 'Open Products Facts'} '
                      '(ODbL), written by volunteers. Check it matches your package: formulas change.',
                      style: T.src(),
                    ),
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ReviewScreen(
                            text: widget.text,
                            kind: ReviewKind.edit,
                            barcode: widget.barcode,
                            name: widget.name,
                            source: widget.source))),
                    child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: MonoLink('Edit the list', icon: Icons.arrow_forward)),
                  ),
                  _limits(),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Btn('Scan another', onTap: () {
                _home();
                openScanner(context, ScanMode.barcode);
              }),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _productType() {
    const types = [('', 'Not sure'), ('leave', 'Leave-on'), ('rinse', 'Rinse-off'), ('home', 'Cleaner')];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Mono('Product type', size: 10.5, color: C.muted),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (k, label) in types)
          InkWell(
            onTap: () => _setType(k),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                  color: _ptype == k ? C.ink : C.paper, border: Border.all(color: C.ink, width: 2)),
              child: Mono(label, size: 11, color: _ptype == k ? C.paper : C.ink),
            ),
          ),
      ]),
    ]);
  }

  Widget _row(IngRow row) => Rule(
        onTap: () => _openIngredient(row.item, row),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(row.item, style: T.name)),
            const Icon(Icons.chevron_right, size: 20, color: C.faint),
          ]),
          if (row.guess != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Read as “${row.guess}”, check the spelling', style: T.src(color: C.signalDark)),
            ),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [for (final (t, l) in row.chips) Tag(t, level: l)]),
        ]),
      );

  void _openIngredient(String item, IngRow? row) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => IngredientScreen(name: item, row: row, back: 'Result', ptype: _ptype)));

  Widget _limits() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _showLimits = !_showLimits),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Mono('${_showLimits ? '−' : '+'} What this can’t check'),
          ),
        ),
        if (_showLimits)
          for (final t in decoder.limits)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: T.lede.copyWith(fontSize: 14))),
      ]);
}

/// Decode a single ingredient the same way, for the ingredient screen.
/// List separators inside an official name ("Hymexazol (ISO); 3-hydroxy-…") are not separate ingredients.
IngRow? rowFor(String name, ProductType ptype) {
  final rep = Report.build(decoder, name.replaceAll(RegExp(r'[,;\n•·●|]+'), ' '), ptype: ptype);
  return rep.rows.isEmpty ? null : rep.rows.first;
}
