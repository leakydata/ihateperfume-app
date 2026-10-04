/// "Not found? Add it": two photos and a few checkboxes, then a confirmation step that shows exactly what will be
/// sent. Photos are cleaned on the phone (re-encoded with no metadata) as soon as they're taken, and held only in
/// memory; the camera's or picker's file is deleted right away. Nothing leaves the phone until Send.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../contribute.dart';
import '../theme.dart';

Future<void> openContribute(BuildContext context,
        {String? barcode, String? name, bool noList = false, String back = 'Scan'}) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ContributeScreen(barcode: barcode, name: name, noList: noList, back: back)));

class ContributeScreen extends StatefulWidget {
  final String? barcode;
  final String? name;
  final bool noList;
  final String back;
  const ContributeScreen({super.key, this.barcode, this.name, this.noList = false, this.back = 'Scan'});
  @override
  State<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends State<ContributeScreen> {
  int _step = 1; // 1 the form, 2 check and send, 3 sent
  Uint8List? _front;
  Uint8List? _ingredients;
  bool _fragranceFree = false;
  bool _unscented = false;
  late bool _noList = widget.noList;
  String? _category;
  late final _name = TextEditingController(text: widget.name ?? '');
  String? _busy;
  String? _error;
  String? _ref;

  bool get _ready => _front != null && (_ingredients != null || _noList);

  Submission get _submission => Submission(
        barcode: widget.barcode,
        name: _name.text,
        fragranceFree: _fragranceFree,
        unscented: _unscented,
        noList: _noList,
        category: _category,
        front: _front!,
        ingredients: _noList ? null : _ingredients,
      );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _forget() {
    _front = null;
    _ingredients = null;
  }

  Future<void> _pick({required bool front}) async {
    if (_busy != null) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(),
      backgroundColor: C.paper,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (s, label) in [(ImageSource.camera, 'Take a photo'), (ImageSource.gallery, 'Pick from your photos')])
            Rule(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              onTap: () => Navigator.pop(c, s),
              child: Mono(label, size: 13),
            ),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    XFile? x;
    try {
      x = await ImagePicker().pickImage(source: source, requestFullMetadata: false);
    } catch (_) {
      _snack(source == ImageSource.camera
          ? 'The camera couldn’t open. You can turn it on for this app in Settings.'
          : 'Your photos couldn’t open.');
      return;
    }
    if (x == null || !mounted) return;
    setState(() => _busy = 'Preparing the photo');
    try {
      final clean = await preparePhotoInBackground(await x.readAsBytes());
      if (!mounted) return;
      setState(() => front ? _front = clean : _ingredients = clean);
    } catch (_) {
      _snack('That photo couldn’t be read. Try another.');
    } finally {
      // The picker's own copy (with its metadata) lives in the app's cache: delete it now. Never the original.
      if (x.path.contains('/com.ihateperfume.ihateperfume/cache/')) {
        try {
          await File(x.path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _send() async {
    setState(() {
      _busy = 'Sending';
      _error = null;
    });
    final r = await sendSubmission(_submission);
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (r.ok) {
        _ref = r.ref;
        _step = 3;
        _forget();
      } else {
        _error = r.error;
      }
    });
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != 2 && _busy == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == 2 && _busy == null) setState(() => _step = 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(children: [
            Column(children: [
              TopBar(
                left: _step == 2
                    ? TopBar.back(context, 'Back', onTap: () {
                        if (_busy == null) setState(() => _step = 1);
                      })
                    : TopBar.back(context, widget.back),
                right: _step < 3 ? Mono('Step $_step of 2') : null,
              ),
              Expanded(child: switch (_step) { 1 => _form(), 2 => _confirm(), _ => _sent() }),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: switch (_step) {
                  1 => Btn('Send it to us', onTap: _ready && _busy == null ? () => setState(() => _step = 2) : null),
                  2 => Btn('Send', onTap: _busy == null ? _send : null),
                  _ => Btn('Done', onTap: () => Navigator.of(context).maybePop()),
                },
              ),
            ]),
            if (_busy != null)
              Positioned.fill(
                child: Container(
                  color: const Color(0xCCFFFFFF),
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(color: C.signal, strokeWidth: 4)),
                    const SizedBox(height: 18),
                    Mono(_busy!, size: 13),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  // ---------- step 1 ----------

  Widget _form() => ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 18), children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: 'WE DON’T KNOW\n', style: T.big(40)),
          TextSpan(text: 'THIS ONE YET.', style: T.big(40, color: C.signal)),
        ])),
        const SizedBox(height: 10),
        const Text('Help the next person. Two photos, no account.', style: T.lede),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _photoBox('Front of\nthe package', _front, C.ink, () => _pick(front: true))),
          const SizedBox(width: 12),
          Expanded(
            child: Opacity(
              opacity: _noList ? .35 : 1,
              child: _photoBox('Ingredient\nlist', _ingredients, C.signal, _noList ? null : () => _pick(front: false)),
            ),
          ),
        ]),
        if (widget.barcode != null) ...[
          const SizedBox(height: 10),
          Mono('Barcode ${widget.barcode}', size: 11, color: C.muted),
        ],
        const SizedBox(height: 18),
        const Mono('The package says'),
        const SizedBox(height: 4),
        _check('Fragrance-free', _fragranceFree, (v) => setState(() => _fragranceFree = v)),
        _check('Unscented', _unscented, (v) => setState(() => _unscented = v)),
        _check('No ingredient list on it', _noList, (v) => setState(() => _noList = v)),
        if (_noList) ...[
          const SizedBox(height: 14),
          const Mono('What is it?', size: 11, color: C.muted),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border.all(color: C.ink, width: 3)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _category,
                isExpanded: true,
                hint: Text('Pick a category', style: T.src(size: 15, color: C.faint)),
                style: T.lede,
                borderRadius: BorderRadius.zero,
                dropdownColor: C.paper,
                items: [for (final c in submitCategories) DropdownMenuItem(value: c, child: Text(c, style: T.lede))],
                onChanged: (v) => setState(() => _category = v),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        const Mono('Product name (optional)', size: 11, color: C.muted),
        const SizedBox(height: 6),
        TextField(
          controller: _name,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          style: T.lede,
          decoration: const InputDecoration(
            hintText: 'Brand and product',
            counterText: '',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: C.ink, width: 3)),
            focusedBorder:
                OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: C.signal, width: 3)),
          ),
        ),
        const SizedBox(height: 14),
        Text('We check every photo before it goes live. Photos are stripped of location data.', style: T.src()),
        if (!_ready && _front != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Add the ingredient list photo, or tick “No ingredient list on it.”',
                style: T.src(color: C.signalDark)),
          ),
      ]);

  Widget _photoBox(String label, Uint8List? photo, Color color, VoidCallback? onTap) => Semantics(
        button: onTap != null,
        label: photo == null ? 'Add a photo: ${label.replaceAll('\n', ' ')}' : 'Retake: ${label.replaceAll('\n', ' ')}',
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 150,
            child: photo == null
                ? CustomPaint(
                    painter: _Dashed(color),
                    child: Center(child: Mono('+ $label', color: color, align: TextAlign.center)),
                  )
                : Stack(fit: StackFit.expand, children: [
                    Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: C.ink,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: const Mono('Retake', size: 11, color: C.paper, align: TextAlign.center),
                      ),
                    ),
                  ]),
          ),
        ),
      );

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) => Rule(
        padding: const EdgeInsets.symmetric(vertical: 4),
        onTap: () => onChanged(!value),
        child: Row(children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            shape: const RoundedRectangleBorder(),
            side: const BorderSide(color: C.ink, width: 2),
            activeColor: C.signal,
          ),
          Text(label, style: T.lede),
        ]),
      );

  // ---------- step 2 ----------

  Widget _confirm() {
    final s = _submission;
    final says = [if (s.fragranceFree) 'Fragrance-free', if (s.unscented) 'Unscented', if (s.noList) 'No ingredient list'];
    Widget row(String k, String v) => Rule(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Mono(k, size: 11, color: C.muted)),
            Expanded(child: Text(v, style: T.lede)),
          ]),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 18), children: [
      const Big('Check what\nyou’ll send', size: 40),
      const SizedBox(height: 10),
      const Text('Only these photos and details are sent, to ihateperfume.com. No account, no location.',
          style: T.lede),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _sentPhoto('Front', s.front)),
        const SizedBox(width: 12),
        Expanded(child: s.ingredients == null ? const SizedBox() : _sentPhoto('Ingredient list', s.ingredients!)),
      ]),
      const SizedBox(height: 8),
      row('Barcode', s.validBarcode ?? 'None'),
      row('Name', s.trimmedName.isEmpty ? 'None' : s.trimmedName),
      row('Package says', says.isEmpty ? 'Nothing ticked' : says.join(', ')),
      if (s.sentCategory != null) row('Category', s.sentCategory!),
      const SizedBox(height: 12),
      Text('The app’s version number goes with it. We check every photo before it goes live.', style: T.src()),
      if (_error != null) ...[
        const SizedBox(height: 14),
        Panel(child: Text(_error!, style: T.lede.copyWith(fontSize: 14))),
      ],
    ]);
  }

  Widget _sentPhoto(String label, Uint8List bytes) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(height: 150, width: double.infinity, child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)),
        const SizedBox(height: 4),
        Mono('$label · ${(bytes.length / 1000).round()} KB', size: 10, color: C.muted),
      ]);

  // ---------- step 3 ----------

  Widget _sent() => ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 18), children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: 'SENT.\n', style: T.big(48)),
          TextSpan(text: 'THANK YOU.', style: T.big(48, color: C.signal)),
        ])),
        const SizedBox(height: 14),
        Text(_ref == null ? 'Thanks.' : 'Thanks. Reference $_ref.', style: T.lede.copyWith(fontSize: 18)),
        const SizedBox(height: 10),
        const Text(
            'We check every photo before anything goes live. The app hasn’t kept a copy on this phone.',
            style: T.lede),
      ]);
}

/// A dashed square outline, 3px, for the empty photo boxes.
class _Dashed extends CustomPainter {
  final Color color;
  _Dashed(this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    const dash = 9.0, gap = 6.0;
    final path = Path()..addRect(Rect.fromLTWH(1.5, 1.5, s.width - 3, s.height - 3));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash + gap) {
        canvas.drawPath(m.extractPath(d, d + dash), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}
