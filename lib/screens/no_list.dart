/// A product we reviewed that has no ingredient list on the package: what the package says about scent, where we
/// checked it, and why "unscented" isn't "fragrance-free". Never says a product is safe.
library;

import 'package:flutter/material.dart';

import '../report.dart';
import '../services.dart';
import '../theme.dart';
import '../list_report.dart';
import 'contribute.dart';
import 'ingredient.dart';
import 'report_list.dart';
import 'scanner.dart';

class NoListScreen extends StatefulWidget {
  final String name;
  final String? barcode;
  final IhpInfo info;
  final bool save; // add to recent scans
  const NoListScreen({super.key, required this.name, this.barcode, required this.info, this.save = false});

  /// The tag recent scans show for it.
  static (String, int) tagFor(IhpInfo i) => saysTag(i.says) ?? ('No list', 1);

  @override
  State<NoListScreen> createState() => _NoListScreenState();
}

class _NoListScreenState extends State<NoListScreen> {
  String get _name => widget.name.isNotEmpty ? widget.name : 'No ingredient list';

  @override
  void initState() {
    super.initState();
    if (widget.save) {
      final (tag, level) = NoListScreen.tagFor(widget.info);
      History.add(Scan(_name, widget.barcode, '', 'ihp', DateTime.now(), tag, level, ihp: widget.info));
    }
  }

  void _home() => Navigator.of(context).popUntil((r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    final says = saysTag(widget.info.says);
    final scented = widget.info.says == 'scented';
    final canReport = isReportBarcode(widget.barcode);
    final meta = ['Checked by I Hate Perfume', if (widget.barcode != null) 'Barcode ${widget.barcode}'].join(' · ');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _home();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            TopBar(left: TopBar.back(context, 'Scan', onTap: _home)),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 24), children: [
                Mono(meta, color: const Color(0xFF666666), size: 11),
                const SizedBox(height: 6),
                Big(_name, size: 36),
                const SizedBox(height: 14),
                VerdictBox(
                  level: scented ? 3 : 1,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Big('No ingredient list', size: 26),
                    const SizedBox(height: 8),
                    Text(
                        'The package doesn’t list its ingredients, so there’s nothing to decode. Here’s what it says '
                        'about scent.',
                        style: T.lede.copyWith(fontSize: 14)),
                    const SizedBox(height: 10),
                    if (says != null) Align(alignment: Alignment.centerLeft, child: Tag(says.$1, level: says.$2, size: 12)),
                    if (says == null) Text('We didn’t record a scent claim for it.', style: T.src()),
                  ]),
                ),
                const SizedBox(height: 10),
                Text('${ihpNote(widget.info)} What the package says, not a guarantee: packages change, so read yours.',
                    style: T.src()),
                if (canReport)
                  ReportListLink(
                      key: ValueKey('${widget.barcode}|ihp'),
                      barcode: widget.barcode!,
                      source: 'ihp',
                      name: widget.name,
                      noList: true),
                const SizedBox(height: 14),
                // Approved copy from the design (mockup screen 4). The evidence stays on the website as graded claims
                // with their sources; the app links there instead of paraphrasing them.
                Panel(
                  child: Text.rich(TextSpan(style: T.lede.copyWith(fontSize: 14), children: const [
                    TextSpan(text: 'Don’t want it on you or in your air? ', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: 'Look for “fragrance-free,” not “unscented.”'),
                  ])),
                ),
                InkWell(
                  onTap: () => openLink(context, '$site/facts/?grade=all&q=unscented#facts'),
                  child: const Padding(
                      padding: EdgeInsets.only(top: 12), child: MonoLink('Why: our graded facts on “unscented”', size: 11)),
                ),
                if (widget.barcode != null && !canReport)
                  InkWell(
                    onTap: () => openContribute(context, barcode: widget.barcode, name: widget.name, noList: true),
                    child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: MonoLink('Something wrong? Send it to us', icon: Icons.arrow_forward, size: 11)),
                  ),
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
}
