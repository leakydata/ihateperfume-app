/// "Wrong or missing ingredients? Report it": the link under a result's source note and its sheet. Nothing is sent
/// unless the user taps "Just report" or sends a suggested correction; "Add photos (fastest fix)" opens the normal
/// "Add it" flow instead.
library;

import 'package:flutter/material.dart';

import '../corrections.dart';
import '../list_report.dart';
import '../theme.dart';
import 'contribute.dart';

/// Sends one report; true when the server took it. [ListReports.send] in the app, a fake in tests.
typedef ReportSender = Future<bool> Function(String barcode, String source, ReportReason reason);

Future<bool> _send(String barcode, String source, ReportReason reason) => ListReports.send(barcode, source, reason);

/// Sends one correction; the server's reference when it took it, else null. [sendCorrection] in the app, a fake in
/// tests.
typedef CorrectionSender = Future<String?> Function(String barcode, String source, Correction c);

Future<String?> _sendCorrection(String barcode, String source, Correction c) => sendCorrection(barcode, source, c);

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

class SuggestCorrectionChoice extends ReportChoice {
  const SuggestCorrectionChoice();
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
            Btn('Suggest a correction',
                ghost: true,
                size: 17,
                padding: const EdgeInsets.all(12),
                onTap: () => Navigator.pop(context, const SuggestCorrectionChoice())),
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

/// The correction form. Returns what the user typed when they tap Send; null when they close it. Sends nothing itself.
Future<Correction?> showCorrectionSheet(BuildContext context, {String? name}) => showModalBottomSheet<Correction>(
      context: context,
      backgroundColor: C.paper,
      shape: const RoundedRectangleBorder(),
      isScrollControlled: true,
      builder: (c) => _CorrectionSheet(name: name),
    );

class _CorrectionSheet extends StatefulWidget {
  final String? name;
  const _CorrectionSheet({this.name});
  @override
  State<_CorrectionSheet> createState() => _CorrectionSheetState();
}

class _CorrectionSheetState extends State<_CorrectionSheet> {
  final _message = TextEditingController();
  final _name = TextEditingController();
  final _ingredients = TextEditingController();

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    _name.dispose();
    _ingredients.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController c, String label, {int lines = 1, int? max}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines == 1 ? 1 : 8,
          maxLength: max,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Big('Suggest a correction', size: 30),
              const SizedBox(height: 10),
              const Text('We check every suggestion before anything changes.', style: T.lede),
              _field(_message, 'What’s wrong?', lines: 3, max: maxCorrectionMessage),
              _field(_name, 'Correct product name (optional)', max: maxCorrectionName),
              _field(_ingredients, 'Correct ingredient list, as printed (optional)', lines: 3),
              const SizedBox(height: 12),
              Btn('Send',
                  size: 17,
                  padding: const EdgeInsets.all(12),
                  onTap: _message.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(context,
                          Correction(message: _message.text, name: _name.text, ingredients: _ingredients.text))),
              const SizedBox(height: 10),
              Text(
                  'Please don’t include personal details. We receive only the barcode, which list you saw, and what '
                  'you type here.',
                  style: T.src()),
            ]),
          ),
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
  final CorrectionSender suggest;
  final AddPhotos addPhotos;
  const ReportListLink(
      {super.key,
      required this.barcode,
      required this.source,
      this.name,
      this.noList = false,
      this.send = _send,
      this.suggest = _sendCorrection,
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
      case SuggestCorrectionChoice():
        final c = await showCorrectionSheet(context, name: widget.name);
        if (!mounted || c == null) return; // closed: nothing sent
        setState(() {
          _sending = true;
          _said = null;
        });
        final ref = await widget.suggest(widget.barcode, widget.source, c);
        if (!mounted) return;
        setState(() {
          _sending = false;
          _reported = ref != null;
          _said = ref == null
              ? 'Couldn’t send it. Try again later.'
              : 'Thanks. We’ll check it.${ref.isEmpty ? '' : ' Reference $ref.'}';
        });
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
