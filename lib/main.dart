// I Hate Perfume. Based on the I Hate Perfume app by ihateperfume.com (https://ihateperfume.com).
// GPL-3.0 with the additional terms in ADDITIONAL-TERMS.md.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/about.dart';
import 'screens/home.dart';
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
  late final Future<void> _ready = Future.wait([
    loadDecoder(),
    Future.delayed(const Duration(milliseconds: 600)), // let the splash be read, not flash
  ]);

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
            return const Shell();
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

/// Bottom tabs: Scan, Search, Learn.
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
                child: IndexedStack(index: i, children: const [HomeScreen(), SearchScreen(), AboutScreen()]),
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
                    if (i == 1) Shell.searchFocus.requestFocus();
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
