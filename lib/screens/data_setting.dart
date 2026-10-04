/// The phone's copy of our product and ingredient database: what's in use, when it was last checked, and a button to
/// update it now (it also updates on its own about once a day).
library;

import 'package:flutter/material.dart';

import '../services.dart';
import '../theme.dart';

/// Checks ihateperfume.com for newer data now and says what happened, in a few words.
Future<String> updateDatabaseNow() async => switch (await checkForDataUpdate(force: true)) {
      DataCheck.updated => 'Updated.',
      DataCheck.unchanged => 'You’re up to date.',
      DataCheck.skipped => 'Already updating.',
      DataCheck.failed => 'Couldn’t update right now. Try again later.',
    };

/// "Checked just now", "Checked 3 hours ago", "Checked Oct 4", or "Not checked yet".
String checkedText(DateTime? t, {DateTime? now}) {
  if (t == null) return 'Not checked yet';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'Checked just now';
  if (d.inHours < 1) return 'Checked ${d.inMinutes} min ago';
  if (d.inDays < 1) return 'Checked ${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'Checked ${m[t.month - 1]} ${t.day}';
}

String _products(int n) => n == 0 ? '' : ' · $n reviewed product${n == 1 ? '' : 's'}';

class DataSetting extends StatefulWidget {
  const DataSetting({super.key});
  @override
  State<DataSetting> createState() => _DataSettingState();
}

class _DataSettingState extends State<DataSetting> {
  bool _busy = false;
  String? _result;

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final r = await updateDatabaseNow();
    if (mounted) {
      setState(() {
        _busy = false;
        _result = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: dataStatus,
        builder: (context, s, _) => Semantics(
          button: true,
          label: 'Update the product and ingredient database',
          // The whole row is the button.
          child: Rule(
            onTap: _busy ? null : _update,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Product and ingredient database', style: T.lede.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Data ${s.label}${_products(s.products)}. ${checkedText(s.lastCheck)}. Updates on its own about '
                    'once a day. Updating sends nothing about you.',
                    style: T.src(),
                  ),
                  if (_result != null)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text(_result!, style: T.src(color: C.ink))),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.signal))
                    : const Mono('Update database', color: C.signal),
              ),
            ]),
          ),
        ),
      );
}

/// The home screen's data line with an Update link.
class DataFooter extends StatefulWidget {
  final String text;
  const DataFooter(this.text, {super.key});
  @override
  State<DataFooter> createState() => _DataFooterState();
}

class _DataFooterState extends State<DataFooter> {
  bool _busy = false;

  Future<void> _update() async {
    setState(() => _busy = true);
    final r = await updateDatabaseNow();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: dataStatus,
        builder: (context, s, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${widget.text}${_products(s.products)}. ${checkedText(s.lastCheck)}.', style: T.src(size: 11)),
          InkWell(
            onTap: _busy ? null : _update,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: C.signal))
                  : const MonoLink('Update database', icon: Icons.refresh, size: 11),
            ),
          ),
        ]),
      );
}
