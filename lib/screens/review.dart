/// Shows the text read from a photo so mistakes can be fixed, or takes a typed or pasted list.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/ocr_fix.dart';
import '../services.dart';
import '../theme.dart';
import 'result.dart';

enum ReviewKind { photo, typed, edit }

class ReviewScreen extends StatefulWidget {
  final String text;
  final ReviewKind kind;
  final String? barcode;
  final String? name;
  final String? source; // kept when editing a list that came from a database
  const ReviewScreen({super.key, required this.text, required this.kind, this.barcode, this.name, this.source});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final _text = TextEditingController(text: widget.text);
  late final _name = TextEditingController(text: widget.name ?? '');
  OcrFix? _fix;
  List<Suggestion> _sugs = const [];
  String? _seen; // the text the suggestions are for
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    spelling.then((f) {
      _fix = f;
      _refresh();
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    _text.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (t.isEmpty) return;
    final sel = _text.selection;
    final cur = _text.text;
    final start = sel.isValid ? sel.start : cur.length;
    final end = sel.isValid ? sel.end : cur.length;
    _text.value = TextEditingValue(
        text: cur.replaceRange(start, end, t), selection: TextSelection.collapsed(offset: start + t.length));
  }

  void _changed() {
    if (_text.text == _seen) return; // a cursor move, not an edit
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 300), _refresh);
  }

  void _refresh() {
    final f = _fix;
    if (f == null || !mounted) return;
    _seen = _text.text;
    setState(() => _sugs = f.suggest(_seen!));
  }

  /// Replace the misread items with the suggested names (only ever on a tap).
  void _use(List<Suggestion> picked) {
    final t = OcrFix.applyAll(_text.text, picked);
    if (t == _text.text) return;
    final end = picked.length == 1 ? picked.first.start + picked.first.to.length : t.length;
    _text.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: end));
    _wait?.cancel();
    _refresh();
  }

  Widget _spellings() => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Flexible(child: Mono('Check these spellings')),
            if (_sugs.length > 1)
              InkWell(
                  key: const Key('use-all'),
                  onTap: () => _use(_sugs),
                  child: const Padding(padding: EdgeInsets.all(6), child: Mono('Use all', color: C.signal))),
          ]),
          const SizedBox(height: 4),
          Text('Closest known ingredient names. Nothing changes until you tap.', style: T.src()),
          for (final s in _sugs)
            Row(children: [
              Expanded(
                child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                  Text(s.from, style: T.src(size: 14, color: C.muted)),
                  const Icon(Icons.arrow_forward, size: 15, color: C.ink, semanticLabel: 'to'),
                  Text(s.to, style: T.src(size: 14, color: C.ink).copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
              InkWell(
                key: Key('use-${s.start}'),
                onTap: () => _use([s]),
                child: const Padding(
                    padding: EdgeInsets.fromLTRB(12, 14, 0, 14), child: Mono('Use it', color: C.signal)),
              ),
            ]),
        ]),
      );

  void _check() {
    final t = _text.text.trim();
    if (t.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('TYPE OR PASTE AN INGREDIENT LIST FIRST.')));
      return;
    }
    final name = _name.text.trim();
    final source = widget.source ?? (widget.kind == ReviewKind.photo ? 'photo' : 'typed');
    final route = MaterialPageRoute(
        builder: (_) => ResultScreen(
            text: t, name: name.isEmpty ? null : name, barcode: widget.barcode, source: source, save: true));
    if (widget.kind == ReviewKind.edit) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.kind == ReviewKind.photo;
    final (back, title, lede) = switch (widget.kind) {
      ReviewKind.photo => ('Retake', 'Check what\nit read', 'Fix anything it misread, then check it. Commas separate ingredients.'),
      ReviewKind.typed => ('Scan', 'Type or paste\nthe list', 'Copy it from the package or a store page. Commas separate ingredients.'),
      ReviewKind.edit => ('Result', 'Edit the list', 'Fix anything that doesn’t match your package.'),
    };
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          TopBar(
            left: TopBar.back(context, back),
            right: widget.barcode == null ? null : Mono('Barcode ${widget.barcode}', color: C.muted, size: 11),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 18), children: [
              Big(title, size: 40),
              const SizedBox(height: 10),
              Text(lede, style: T.lede),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Mono(photo ? 'What it read' : 'Ingredients'),
                InkWell(
                    onTap: _paste,
                    child: const Padding(padding: EdgeInsets.all(6), child: Mono('Paste', color: C.signal))),
              ]),
              const SizedBox(height: 6),
              TextField(
                key: const Key('ingredients'),
                controller: _text,
                autofocus: widget.kind == ReviewKind.typed,
                minLines: 8,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.words,
                style: T.src(size: 14.5, color: C.ink).copyWith(height: 1.45),
                decoration: _box('Water, Glycerin, Fragrance…'),
              ),
              if (_sugs.isNotEmpty) ...[const SizedBox(height: 12), _spellings()],
              const SizedBox(height: 16),
              const Mono('Product name (optional)'),
              const SizedBox(height: 6),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                style: T.lede.copyWith(fontSize: 16),
                decoration: _box('So you can find it in recent scans'),
              ),
              const SizedBox(height: 12),
              Text('Checked on your phone. Nothing is sent.', style: T.src()),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Btn('Check these ingredients', onTap: _check),
          ),
        ]),
      ),
    );
  }

  InputDecoration _box(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: T.src(size: 14.5, color: C.faint),
        contentPadding: const EdgeInsets.all(12),
        enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: C.ink, width: 3)),
        focusedBorder:
            const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: C.signal, width: 3)),
      );
}
