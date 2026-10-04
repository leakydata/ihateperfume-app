/// "Ask us to find it": the link in the scanner's not-found notice, the one-time sheet, the Learn setting, and the
/// home panel for products that were found. Nothing is sent before the user picks an option.
library;

import 'package:flutter/material.dart';

import '../services.dart';
import '../theme.dart';
import '../wanted.dart';
import 'no_list.dart';
import 'result.dart';

/// Sends one barcode; true when the server took it. [Wanted.send] in the app, a fake in tests.
typedef WantedSender = Future<bool> Function(String barcode, String? name);

Future<bool> _send(String barcode, String? name) => Wanted.send(barcode, name: name);

/// The one-time sheet. Returns the saved choice, or null if the user closed it without choosing.
Future<WantedMode?> showWantedSheet(BuildContext context) async {
  final m = await showModalBottomSheet<WantedMode>(
    context: context,
    backgroundColor: C.paper,
    shape: const RoundedRectangleBorder(),
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Big('Help fill the gaps.', size: 30),
          const SizedBox(height: 10),
          const Text(
              'When a barcode isn’t found, the app can send just the number to ihateperfume.com, so we can look for '
              'the product. No account, no location, no device ID. Nothing else.',
              style: T.lede),
          const SizedBox(height: 16),
          Btn('Send missing barcodes automatically',
              size: 17, padding: const EdgeInsets.all(12), onTap: () => Navigator.pop(c, WantedMode.auto)),
          const SizedBox(height: 10),
          Btn('Ask me each time',
              ghost: true, size: 17, padding: const EdgeInsets.all(12), onTap: () => Navigator.pop(c, WantedMode.ask)),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
                onPressed: () => Navigator.pop(c, WantedMode.off), child: const Mono('No thanks', color: C.muted)),
          ),
        ]),
      ),
    ),
  );
  if (m != null) await Wanted.setMode(m);
  return m;
}

/// The third choice in the scanner's not-found notice. Shows "Ask us to find it" (until the user says no), or sends
/// on its own when they chose "automatically", then a one-line confirmation. Give it a key per barcode.
class AskToFind extends StatefulWidget {
  final String barcode;
  final String? name;
  final WantedSender send;
  const AskToFind({super.key, required this.barcode, this.name, this.send = _send});
  @override
  State<AskToFind> createState() => _AskToFindState();
}

class _AskToFindState extends State<AskToFind> {
  WantedMode? _mode;
  bool _loaded = false;
  bool _sending = false;
  String? _said; // "Sent. We’ll look for it." or why it wasn't sent

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final m = await Wanted.mode();
    final asked = await Wanted.isAsked(widget.barcode);
    if (!mounted) return;
    setState(() {
      _mode = m;
      _loaded = true;
      if (asked) _said = 'Already sent. We’ll look for it.';
    });
    if (m == WantedMode.auto && !asked) await _go();
  }

  Future<void> _go() async {
    if (_sending || !isWantedBarcode(widget.barcode)) return;
    setState(() => _sending = true);
    final ok = await widget.send(widget.barcode, widget.name);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _said = ok ? 'Sent. We’ll look for it.' : 'Couldn’t send it. Try again later.';
    });
  }

  Future<void> _tap() async {
    if (_sending) return;
    var m = _mode;
    if (m == null) {
      m = await showWantedSheet(context);
      if (!mounted || m == null) return; // closed without choosing: nothing sent
      setState(() => _mode = m);
      if (m == WantedMode.off) return;
    }
    await _go();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !isWantedBarcode(widget.barcode)) return const SizedBox.shrink();
    final sent = _said != null && _said!.endsWith('look for it.');
    if (_mode == WantedMode.off && _said == null) return const SizedBox.shrink();
    if (sent || (_sending && _mode == WantedMode.auto)) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_sending ? 'Sending…' : _said!, style: T.src(size: 11.5)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: _tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: MonoLink(_sending ? 'Sending…' : 'Ask us to find it', icon: Icons.arrow_forward, size: 10,
                color: C.signalDark),
          ),
        ),
        Text(_said ?? 'We’ll try to find it. Photos get it added faster.', style: T.src(size: 11)),
      ]),
    );
  }
}

/// Learn: "Missing barcodes", with the three choices. Changing it saves the mode.
class WantedSetting extends StatefulWidget {
  const WantedSetting({super.key});
  @override
  State<WantedSetting> createState() => _WantedSettingState();
}

class _WantedSettingState extends State<WantedSetting> {
  WantedMode? _mode;

  @override
  void initState() {
    super.initState();
    Wanted.mode().then((m) {
      if (mounted) setState(() => _mode = m);
    });
  }

  Future<void> _set(WantedMode m) async {
    setState(() => _mode = m);
    await Wanted.setMode(m);
  }

  @override
  Widget build(BuildContext context) {
    Widget option(WantedMode m, String label) => Semantics(
          selected: _mode == m,
          button: true,
          child: InkWell(
            onTap: () => _set(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Icon(_mode == m ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 18, color: _mode == m ? C.signal : C.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: T.lede)),
              ]),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.rule, width: 2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Missing barcodes', style: T.lede.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('When a barcode isn’t found, send just the number to ihateperfume.com so we can look for the product.',
            style: T.src(size: 12)),
        const SizedBox(height: 4),
        option(WantedMode.auto, 'Send missing barcodes automatically'),
        option(WantedMode.ask, 'Ask me each time'),
        option(WantedMode.off, 'Don’t send'),
      ]),
    );
  }
}

/// Home: "We found N products you asked about." Tap a name to open it; dismiss to forget them.
class FoundPanel extends StatelessWidget {
  const FoundPanel({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: Wanted.found,
        builder: (context, found, _) {
          if (found.isEmpty) return const SizedBox.shrink();
          final n = found.length;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text('We found $n ${n == 1 ? 'product' : 'products'} you asked about.',
                        style: T.lede.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Semantics(
                    button: true,
                    label: 'Dismiss',
                    child: InkWell(
                      onTap: Wanted.dismissFound,
                      child: const Padding(
                          padding: EdgeInsets.only(left: 8, bottom: 4), child: Icon(Icons.close, size: 18, color: C.ink)),
                    ),
                  ),
                ]),
                for (final p in found)
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => p.ingredients != null
                            ? ResultScreen(
                                text: p.ingredients!, name: p.name, barcode: p.barcode, source: 'ihp', ihp: p.ihp, save: true)
                            : NoListScreen(
                                name: p.name, barcode: p.barcode, info: p.ihp ?? const IhpInfo(noList: true), save: true))),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: MonoLink(p.name.isNotEmpty ? p.name : 'Barcode ${p.barcode}',
                          icon: Icons.arrow_forward, size: 11),
                    ),
                  ),
              ]),
            ),
          );
        },
      );
}
