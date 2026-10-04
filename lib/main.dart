// I Hate Perfume. Based on the I Hate Perfume app by ihateperfume.com (https://ihateperfume.com).
// GPL-3.0 with the additional terms in ADDITIONAL-TERMS.md.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/about.dart';
import 'screens/home.dart';
import 'screens/legal.dart';
import 'screens/my_list.dart';
import 'screens/search.dart';
import 'services.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final (pkg, file) in [('Archivo', 'LICENSE-Archivo.txt'), ('IBM Plex Mono', 'LICENSE-IBM-Plex-Mono.txt')]) {
      yield LicenseEntryWithLineBreaks([pkg], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final Future<bool> _ready = Future.wait([
    loadDecoder(),
    Future.delayed(const Duration(milliseconds: 600)), // let the splash be read, not flash
    FirstRunNotice.seen(),
  ]).then((r) => r[2] as bool);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'I Hate Perfume',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        builder: (context, child) => AnnotatedRegion(value: SystemUiOverlayStyle.dark, child: child!),
        home: FutureBuilder(
          future: _ready,
          builder: (context, snap) {
            if (snap.hasError) return Splash(error: '${snap.error}');
            if (snap.connectionState != ConnectionState.done) return const Splash();
            return NoticeGate(seen: snap.data!, child: const Shell());
          },
        ),
      );
}

class Splash extends StatelessWidget {
  final String? error;
  const Splash({super.key, this.error});
  @override
  Widget build(BuildContext context) => AnnotatedRegion(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: C.ink,
          body: SafeArea(
            child: Stack(children: [
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Big('I Hate\nPerfume', size: 64, color: C.paper, align: TextAlign.center),
                  const SizedBox(height: 14),
                  const Mono('Scan it. Unmask it.', color: C.signalLight),
                  if (error != null)
                    Padding(padding: const EdgeInsets.all(24), child: Text(error!, style: T.src(color: C.signalLight))),
                ]),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 34,
                child: Mono('No account. No ads. No tracking.', size: 11, color: Color(0xFF888888), align: TextAlign.center),
              ),
            ]),
          ),
        ),
      );
}

/// Shows [FirstRunNotice] until it's dismissed once, then [child].
class NoticeGate extends StatefulWidget {
  final bool seen;
  final Widget child;
  const NoticeGate({super.key, required this.seen, required this.child});
  @override
  State<NoticeGate> createState() => _NoticeGateState();
}

class _NoticeGateState extends State<NoticeGate> {
  late bool _seen = widget.seen;
  @override
  Widget build(BuildContext context) => _seen
      ? widget.child
      : FirstRunNotice(onDone: () {
          setState(() => _seen = true);
          FirstRunNotice.markSeen();
        });
}

/// Shown once, after the splash on first launch: what the app is and isn't, and what leaves the phone.
class FirstRunNotice extends StatelessWidget {
  static const prefsKey = 'notice-v1';
  final VoidCallback onDone;
  const FirstRunNotice({super.key, required this.onDone});

  static Future<bool> seen() async => (await SharedPreferences.getInstance()).getBool(prefsKey) ?? false;
  static Future<void> markSeen() async => (await SharedPreferences.getInstance()).setBool(prefsKey, true);

  static const points = [
    'Information, not medical advice.',
    'Never a guarantee: always read the package. Labels and formulas change, and text recognition can misread.',
    'Your scans stay on this phone. Only a barcode number is sent, to look the product up.',
  ];

  @override
  Widget build(BuildContext context) {
    Widget link(String t, LegalDoc doc) => InkWell(
          onTap: () => Navigator.of(context).push(LegalScreen.route(doc, back: 'Back')),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: MonoLink(t, icon: Icons.arrow_forward, color: C.signalLight)),
        );
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: C.ink,
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Big('Before you start', size: 56, color: C.paper),
                  const SizedBox(height: 28),
                  for (final t in points)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Padding(
                            padding: EdgeInsets.only(top: 8, right: 12),
                            child: SizedBox(width: 10, height: 10, child: ColoredBox(color: C.signal))),
                        Expanded(child: Text(t, style: T.lede.copyWith(color: C.paper, fontSize: 18))),
                      ]),
                    ),
                  const SizedBox(height: 8),
                  link('Terms and disclaimer', termsDoc),
                  link('Privacy policy', privacyDoc),
                ]),
              ),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), child: Btn('Got it', onTap: onDone)),
          ]),
        ),
      ),
    );
  }
}

/// Bottom tabs: Scan, Search, My list, Learn.
class Shell extends StatefulWidget {
  const Shell({super.key});
  static final tab = ValueNotifier(0);
  static final searchFocus = FocusNode();
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: Shell.tab,
        builder: (context, i, _) => PopScope(
          canPop: i == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) Shell.tab.value = 0;
          },
          child: AnnotatedRegion(
            value: SystemUiOverlayStyle.dark,
            child: Scaffold(
              body: SafeArea(
                bottom: false,
                child: IndexedStack(index: i, children: const [HomeScreen(), SearchScreen(), MyListScreen(), AboutScreen()]),
              ),
              bottomNavigationBar: _Tabs(i),
            ),
          ),
        ),
      );
}

class _Tabs extends StatelessWidget {
  final int on;
  const _Tabs(this.on);
  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.crop_free, 'Scan'),
      (Icons.search, 'Search'),
      (Icons.bookmark_border, 'My list'),
      (Icons.menu_book_outlined, 'Learn'),
    ];
    return Container(
      decoration: const BoxDecoration(color: C.paper, border: Border(top: BorderSide(color: C.ink, width: 3))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () {
                    Shell.tab.value = i;
                    if (i == 1) WidgetsBinding.instance.addPostFrameCallback((_) => Shell.searchFocus.requestFocus());
                  },
                  child: Semantics(
                    selected: on == i,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(items[i].$1, size: 26, color: on == i ? C.signal : C.ink),
                      const SizedBox(height: 4),
                      Mono(items[i].$2, size: 10, color: on == i ? C.signal : C.ink),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
