import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/decoder.dart';
import '../report.dart';
import '../services.dart';
import '../theme.dart';
import 'result.dart';

/// Opens a link in the browser. Only ever on a tap.
Future<void> openLink(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('NO BROWSER FOUND TO OPEN THE LINK.')));
  }
}

const _scentTitles = {'Hidden mixture', 'Scent ingredient', 'Scented plant oil', 'Oxidizes into stronger allergens'};

class IngredientScreen extends StatefulWidget {
  final String name;
  final IngRow? row; // from a result; looked up again when null
  final String back;
  final ProductType ptype;
  const IngredientScreen({super.key, required this.name, this.row, required this.back, this.ptype = ''});
  @override
  State<IngredientScreen> createState() => _IngredientScreenState();
}

class _IngredientScreenState extends State<IngredientScreen> {
  late final IngRow? row = widget.row ?? rowFor(widget.name, widget.ptype);
  final _open = <int>{};

  @override
  Widget build(BuildContext context) {
    final r = row;
    final lookupName = r?.guess ?? widget.name;
    final page = decoder.pageFor(lookupName);
    final fact = decoder.facts[Decoder.norm(widget.name)];
    final level = r?.worst ?? 0;
    final scent = r != null &&
        r.reasons.any((x) => _scentTitles.contains(x.title) || x.title.toLowerCase().contains('fragrance allergen'));
    final known = decoder.vocab.contains(Decoder.norm(lookupName));
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          TopBar(
            left: TopBar.back(context, widget.back),
            right: page == null
                ? null
                : InkWell(
                    onTap: () => openLink(context, page),
                    child: const Padding(padding: EdgeInsets.all(8), child: MonoLink('ihateperfume.com')),
                  ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 24), children: [
              Big(widget.name, size: widget.name.length > 16 ? 34 : 48),
              if (r?.guess != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Read as “${r!.guess}”, check the spelling', style: T.src(color: C.signalDark)),
                ),
              const SizedBox(height: 12),
              VerdictBox(
                level: level,
                child: Big(
                    switch (level) {
                      3 => 'Red flag',
                      2 => 'Worth a closer look',
                      1 => 'Worth knowing',
                      _ => 'Not on our lists',
                    },
                    size: 22),
              ),
              if (r == null) ...[
                const SizedBox(height: 12),
                Text(
                  known
                      ? 'It’s a real ingredient name, but it isn’t on any list we check. Not on a list doesn’t mean '
                          'safe; it may never have been assessed.'
                      : 'We don’t recognize this name. Check the spelling against the package.',
                  style: T.lede,
                ),
              ] else ...[
                const SizedBox(height: 16),
                const Mono('Why it’s flagged', color: C.signal),
                const SizedBox(height: 4),
                for (var i = 0; i < r.reasons.length; i++) _reason(i, r.reasons[i]),
                if (r.reasons.any((x) => x.title.contains('allergen (EU')))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                        'A few fragrance allergens, such as benzyl alcohol, can also be in a product for another '
                        'reason, like preserving it.',
                        style: T.src()),
                  ),
              ],
              if (scent) ...[
                const SizedBox(height: 14),
                Panel(
                  child: Text.rich(TextSpan(style: T.lede, children: [
                    const TextSpan(text: 'Don’t want it on you or in your air? ', style: TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: 'Look for “fragrance-free,” not “unscented.”'),
                  ])),
                ),
              ],
              const SizedBox(height: 18),
              if (page != null) _link('What it is and why it’s flagged', page),
              if (fact != null)
                _link('Our graded facts', '$site/facts/?grade=all&q=${Uri.encodeComponent(fact)}#facts'),
              _link('Look it up on EWG Skin Deep',
                  'https://www.ewg.org/skindeep/search/?search=${Uri.encodeComponent(widget.name)}'),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _reason(int i, Reason x) {
    final open = _open.contains(i);
    final detail = x.detail.isEmpty ? '' : '${x.detail[0].toUpperCase()}${x.detail.substring(1)} · ';
    return Rule(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => open ? _open.remove(i) : _open.add(i)),
          child: Text(x.title, style: T.name.copyWith(fontSize: 16)),
        ),
        if (open && (x.help.isNotEmpty || x.label != x.title))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text([if (x.label != x.title) '${x.label}.', x.help].join(' ').trim(),
                style: T.lede.copyWith(fontSize: 14)),
          ),
        const SizedBox(height: 3),
        InkWell(
          onTap: x.url == null ? null : () => openLink(context, x.url!),
          child: Text.rich(TextSpan(style: T.src(), children: [
            TextSpan(text: detail),
            TextSpan(text: 'Source: ${x.source}'),
            if (x.url != null)
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                    padding: EdgeInsets.only(left: 4), child: Icon(Icons.north_east, size: 13, color: C.signal)),
              ),
          ])),
        ),
        if (!open && (x.help.isNotEmpty || x.label != x.title))
          InkWell(
            onTap: () => setState(() => _open.add(i)),
            child: Padding(
                padding: const EdgeInsets.only(top: 4), child: Mono('What does this mean?', size: 10, color: C.muted)),
          ),
      ]),
    );
  }

  Widget _link(String text, String url) => Rule(
        padding: const EdgeInsets.symmetric(vertical: 12),
        onTap: () => openLink(context, url),
        child: Row(children: [
          Expanded(child: Text(text, style: T.lede.copyWith(fontWeight: FontWeight.w600))),
          const Icon(Icons.north_east, size: 18, color: C.signal),
        ]),
      );
}
