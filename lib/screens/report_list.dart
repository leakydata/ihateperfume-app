/// "Wrong or missing ingredients? Report it": the link under a result's source note and its sheet. Nothing is sent
/// unless the user taps "Just report"; "Add photos (fastest fix)" opens the normal "Add it" flow instead.
library;

import 'package:flutter/material.dart';

import '../list_report.dart';
import '../theme.dart';
import 'contribute.dart';

/// Sends one report; true when the server took it. [ListReports.send] in the app, a fake in tests.
typedef ReportSender = Future<bool> Function(String barcode, String source, ReportReason reason);

Future<bool> _send(String barcode, String source, ReportReason reason) => ListReports.send(barcode, source, reason);

/// Opens the "Add it" flow. [openContribute] in the app, a fake in tests.
typedef AddPhotos = Future<void> Function(BuildContext context, String barcode, String? name, bool noList);

Future<void> _addPhotos(BuildContext context, String barcode, String? name, bool noList) =>
    openContribute(context, barcode: barcode, name: name, noList: noList);

/// What the user chose in the sheet: add photos, or just report with a reason. Null when they closed it.
sealed class ReportChoice {
  const ReportChoice();
}

class AddPhotosChoice extends ReportChoice {
  const AddPhotosChoice();
}

class JustReportChoice extends ReportChoice {
  final ReportReason reason;
  const JustReportChoice(this.reason);
}

/// The sheet. Sends nothing itself.
Future<ReportChoice?> showReportSheet(BuildContext context) => showModalBottomSheet<ReportChoice>(
      context: context,
      backgroundColor: C.paper,
      shape: const RoundedRectangleBorder(),
      isScrollControlled: true,
      builder: (c) => const _ReportSheet(),
    );

class _ReportSheet extends StatefulWidget {
  const _ReportSheet();
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Big('Report this list', size: 30),
            const SizedBox(height: 10),
            const Text('Tell us what’s wrong. Photos fix it fastest.', style: T.lede),
            const SizedBox(height: 8),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (r) => setState(() => _reason = r),
              child: Column(children: [
                for (final r in ReportReason.values)
                  RadioListTile<ReportReason>(
                    value: r,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: C.signal,
                    title: Text(r.label, style: T.lede),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            Btn('Add photos (fastest fix)',
                size: 17,
                padding: const EdgeInsets.all(12),
                onTap: () => Navigator.pop(context, const AddPhotosChoice())),
            const SizedBox(height: 10),
            Btn('Just report',
                ghost: true,
                size: 17,
                padding: const EdgeInsets.all(12),
                onTap: _reason == null ? null : () => Navigator.pop(context, JustReportChoice(_reason!))),
            const SizedBox(height: 10),
            Text('“Just report” sends only the barcode, where the list came from, and the reason.', style: T.src()),
          ]),
        ),
      );
}

/// The link. Shows "Reported. Thanks." once this (barcode, source) was reported from this phone. Give it a key per
/// barcode and source.
class ReportListLink extends StatefulWidget {
  final String barcode;
  final String source; // obf, opf, fda, or ihp
  final String? name;
  final bool noList; // for "Add photos": the product has no ingredient list
  final ReportSender send;
  final AddPhotos addPhotos;
  const ReportListLink(
      {super.key,
      required this.barcode,
      required this.source,
      this.name,
      this.noList = false,
      this.send = _send,
      this.addPhotos = _addPhotos});
  @override
  State<ReportListLink> createState() => _ReportListLinkState();
}

class _ReportListLinkState extends State<ReportListLink> {
  bool _reported = false;
  bool _sending = false;
  String? _said; // "Thanks. We’ll check it." or why it wasn't sent

  @override
  void initState() {
    super.initState();
    ListReports.isReported(widget.barcode, widget.source).then((r) {
      if (mounted && r) setState(() => _reported = true);
    });
  }

  Future<void> _tap() async {
    if (_sending) return;
    final choice = await showReportSheet(context);
    if (!mounted || choice == null) return; // closed: nothing sent
    switch (choice) {
      case AddPhotosChoice():
        await widget.addPhotos(context, widget.barcode, widget.name, widget.noList);
      case JustReportChoice(:final reason):
        setState(() {
          _sending = true;
          _said = null;
        });
        final ok = await widget.send(widget.barcode, widget.source, reason);
        if (!mounted) return;
        setState(() {
          _sending = false;
          _reported = ok;
          _said = ok ? 'Thanks. We’ll check it.' : 'Couldn’t send it. Try again later.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isReportBarcode(widget.barcode) || !reportSources.contains(widget.source)) return const SizedBox.shrink();
    if (_sending) return Padding(padding: const EdgeInsets.only(top: 10), child: Text('Sending…', style: T.src()));
    if (_reported) {
      return Padding(
          padding: const EdgeInsets.only(top: 10), child: Text(_said ?? 'Reported. Thanks.', style: T.src()));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: _tap,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text.rich(TextSpan(style: T.src(), children: const [
            TextSpan(text: 'Wrong or missing ingredients? '),
            TextSpan(text: 'Report it', style: TextStyle(color: C.signal, fontWeight: FontWeight.w600)),
          ])),
        ),
      ),
      if (_said != null) Text(_said!, style: T.src(color: C.faint)),
    ]);
  }
}
