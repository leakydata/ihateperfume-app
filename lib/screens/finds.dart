/// The "Finds" tab: reviewed products with no ingredient list, by category. Fetched from ihateperfume.com only
/// when the tab is opened (or pulled to refresh), and kept on the phone for offline use.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../finds.dart';
import '../services.dart';
import '../theme.dart';
import 'contribute.dart';

class FindsScreen extends StatefulWidget {
  /// True while the tab is showing; the list is fetched the first time it is.
  final ValueListenable<bool> visible;
  const FindsScreen({super.key, required this.visible});
  @override
  State<FindsScreen> createState() => _FindsScreenState();
}

class _FindsScreenState extends State<FindsScreen> {
  CachedFinds? _finds;
  bool _loading = false;
  bool _started = false;
  String? _error;
  String? _category; // null = all

  @override
  void initState() {
    super.initState();
    widget.visible.addListener(_onVisible);
    _onVisible();
  }

  @override
  void dispose() {
    widget.visible.removeListener(_onVisible);
    super.dispose();
  }

  void _onVisible() {
    if (!widget.visible.value || _started) return;
    _started = true;
    FindsStore.cached().then((c) {
      if (mounted && c != null && _finds == null) setState(() => _finds = c);
    });
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = await FindsStore.refresh();
      if (mounted) setState(() => _finds = f);
    } on FindsError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _finds?.data;
    final cats = data?.categories ?? const <String>[];
    final items = (data?.items ?? const <Find>[]).where((f) => _category == null || f.category == _category).toList();
    return Column(children: [
      TopBar(left: Text('FRAGRANCE-FREE FINDS', style: T.big(26).copyWith(height: 1))),
      Expanded(
        child: RefreshIndicator(
          color: C.signal,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            children: [
              const Text('For things with no ingredient list. Every entry checked against the package.', style: T.lede),
              if (cats.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _chip('All', null),
                  for (final c in cats) _chip(c, c),
                ]),
              ],
              const SizedBox(height: 8),
              if (_finds == null && _loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                      child: SizedBox(
                          width: 30, height: 30, child: CircularProgressIndicator(color: C.signal, strokeWidth: 4))),
                )
              else if (_finds == null && _error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('$_error Pull down to try again.', style: T.lede.copyWith(fontSize: 14)),
                )
              else if (_finds != null && data!.items.isEmpty)
                InkWell(
                  onTap: _add,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text.rich(TextSpan(style: T.lede, children: [
                      const TextSpan(text: 'No finds yet. Be the first: '),
                      TextSpan(
                          text: 'add one.',
                          style: const TextStyle(color: C.signal, fontWeight: FontWeight.w700)),
                    ])),
                  ),
                )
              else
                for (final f in items) _row(f),
              if (_finds != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Last updated ${_date(_finds!.updated)}${_error != null ? ' · offline copy' : ''}',
                  style: T.src(size: 11),
                ),
              ],
              const SizedBox(height: 14),
              InkWell(
                onTap: _add,
                child: Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(style: T.lede, children: const [
                      TextSpan(text: 'Know a good one? ', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(
                          text: 'Add it. Took us 20 minutes to find trash bags without fragrance. It shouldn’t.'),
                    ])),
                    const SizedBox(height: 8),
                    const MonoLink('Add it', icon: Icons.arrow_forward, size: 11),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  void _add() => openContribute(context, noList: true, back: 'Finds');

  Widget _chip(String label, String? value) {
    final on = _category == value;
    return InkWell(
      onTap: () => setState(() => _category = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(color: on ? C.ink : C.paper, border: Border.all(color: C.ink, width: 2)),
        child: Mono(label, size: 12, color: on ? C.paper : C.ink),
      ),
    );
  }

  Widget _row(Find f) {
    final says = saysTag(f.says);
    return Rule(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(f.name, style: T.name.copyWith(fontSize: 16.5)),
        if (f.brand.isNotEmpty) Text(f.brand, style: T.lede.copyWith(fontSize: 14, color: C.muted)),
        const SizedBox(height: 5),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (says != null) Tag(says.$1, level: says.$2),
          if (f.checkedLine.isNotEmpty) Text(f.checkedLine, style: T.src(size: 11)),
        ]),
        if (f.note != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(f.note!, style: T.src(size: 11.5))),
      ]),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime d) {
  final l = d.toLocal();
  return '${_months[l.month - 1]} ${l.day}, ${l.year}';
}
