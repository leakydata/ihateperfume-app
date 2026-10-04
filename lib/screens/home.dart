import 'package:flutter/material.dart';

import '../main.dart';
import '../my_list.dart';
import '../services.dart';
import '../theme.dart';
import 'no_list.dart';
import 'result.dart';
import 'scanner.dart';
import 'wanted.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Scan> _recent = [];
  List<ListEntry> _list = MyList.current;
  final _onList = <String, int>{}; // scan text -> worst reaction level of list hits (0 = none)
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _load();
    History.changes.addListener(_load);
    MyList.changes.addListener(_load);
  }

  @override
  void dispose() {
    History.changes.removeListener(_load);
    MyList.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final r = await History.all();
    final l = await MyList.all();
    if (!mounted) return;
    setState(() {
      _recent = r;
      _list = l;
      _onList.clear();
    });
    _checkList();
  }

  /// Check recent scans against the list, one label per frame so scrolling stays smooth. Reports are cached, so
  /// this decodes each label once.
  Future<void> _checkList() async {
    final run = ++_run;
    if (_list.isEmpty) return;
    for (final s in _recent.take(20)) {
      if (s.text.isEmpty) continue; // a product with no ingredient list
      await Future<void>.delayed(Duration.zero);
      if (!mounted || run != _run) return;
      final level = checkList(decoder, ReportCache.get(decoder, s.text), _list).level;
      setState(() => _onList[s.text] = level);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TopBar(
        left: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('I HATE PERFUME', style: T.big(30).copyWith(height: 1, letterSpacing: -.3)),
          const SizedBox(height: 2),
          Text('IHATEPERFUME.COM', style: T.mono(size: 10, color: C.signal).copyWith(letterSpacing: .8)),
        ]),
        right: const Mono('Offline OK', color: C.signal),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 18), children: [
          Container(
            color: C.ink,
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Mono('What’s really in it?', color: C.signalLight),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'SCAN IT.\n', style: T.big(52, color: C.paper)),
                  TextSpan(text: 'UNMASK IT.', style: T.big(52, color: C.signal)),
                ]),
              ),
              const SizedBox(height: 16),
              Btn('Scan a barcode', onTap: () => openScanner(context, ScanMode.barcode)),
              const SizedBox(height: 10),
              Btn('Photograph the ingredients',
                  ghost: true,
                  ghostColor: C.paper,
                  size: 19,
                  padding: const EdgeInsets.all(12),
                  onTap: () => openScanner(context, ScanMode.list)),
            ]),
          ),
          const SizedBox(height: 16),
          const FoundPanel(),
          InkWell(
            onTap: () {
              Shell.tab.value = 1;
              WidgetsBinding.instance.addPostFrameCallback((_) => Shell.searchFocus.requestFocus());
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: C.ink, width: 3)),
              child: Text('Search an ingredient…',
                  style: T.src(size: 15, color: C.faint).copyWith(height: 1.2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Mono('Recent scans'),
            if (_recent.isNotEmpty)
              InkWell(
                onTap: _confirmClear,
                child: const Padding(padding: EdgeInsets.all(6), child: Mono('Clear', size: 10, color: C.muted)),
              ),
          ]),
          const SizedBox(height: 4),
          if (_recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('Nothing yet. What you scan stays on this phone.', style: T.src(size: 12.5)),
            ),
          for (final s in _recent.take(20)) _RecentRow(s, _onList[s.text] ?? 0),
          const SizedBox(height: 24),
          ValueListenableBuilder(valueListenable: dataStatus, builder: (context, _, _) => Text(
            'Ingredient data from ihateperfume.com, ${_date(dataVersion)} · '
            '${_thousands(decoder.flaggedNames.length)} flagged ingredients',
            style: T.src(size: 11),
          )),
        ]),
      ),
    ]);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Big('Clear recent scans?', size: 26),
        content: const Text('They’re only stored on this phone. This removes them.', style: T.lede),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Mono('Keep')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Mono('Clear', color: C.signal)),
        ],
      ),
    );
    if (ok == true) await History.clear();
  }
}

class _RecentRow extends StatelessWidget {
  final Scan s;
  final int onList; // worst reaction level of list hits, 0 = none
  const _RecentRow(this.s, this.onList);
  @override
  Widget build(BuildContext context) {
    return Rule(
      padding: const EdgeInsets.symmetric(vertical: 9),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => s.text.isEmpty && s.ihp != null
              ? NoListScreen(name: s.name, barcode: s.barcode, info: s.ihp!)
              : ResultScreen(text: s.text, name: s.name, barcode: s.barcode, source: s.source, ihp: s.ihp))),
      child: Row(children: [
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: s.name, style: T.lede.copyWith(fontSize: 15.5)),
            TextSpan(text: '  ${_short(s.at)}', style: T.src(size: 11)),
          ])),
        ),
        const SizedBox(width: 8),
        onList > 0 ? Tag('On your list', level: onList) : Tag(s.tag, level: s.level),
      ]),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _short(DateTime d) => '${_months[d.month - 1]} ${d.day}';
String _date(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
