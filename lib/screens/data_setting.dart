/// Learn: which ingredient data is in use, and a button to check ihateperfume.com for newer data now.
library;

import 'package:flutter/material.dart';

import '../services.dart';
import '../theme.dart';

class DataSetting extends StatefulWidget {
  const DataSetting({super.key});
  @override
  State<DataSetting> createState() => _DataSettingState();
}

class _DataSettingState extends State<DataSetting> {
  bool _busy = false;
  String? _result;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final r = await checkForDataUpdate(force: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = switch (r) {
        DataCheck.updated => 'Updated.',
        DataCheck.unchanged => 'You have the newest data.',
        DataCheck.skipped => 'Already checking.',
        DataCheck.failed => 'Couldn’t check right now. Try again later.',
      };
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: dataStatus,
        builder: (context, s, _) => Semantics(
          button: true,
          label: 'Check for new ingredient data',
          // The whole row is the button: easier to hit than the small "Check now" label.
          child: Rule(
            onTap: _busy ? null : _check,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ingredient data', style: T.lede.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Data ${s.label}'
                    '${s.products > 0 ? ' · ${s.products} reviewed product${s.products == 1 ? '' : 's'}' : ''}. '
                    'Checking sends nothing about you.',
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
                    : const Mono('Check now', color: C.signal),
              ),
            ]),
          ),
        ),
      );
}
