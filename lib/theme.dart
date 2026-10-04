/// The look from design/mockups.png: the website's palette, Archivo condensed caps for headlines, and IBM Plex
/// Mono for labels. Square corners everywhere.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class C {
  static const ink = Color(0xFF111111);
  static const signal = Color(0xFFC4361B);
  static const signalDark = Color(0xFF9E2A14);
  static const signalLight = Color(0xFFFF8A6E);
  static const label = Color(0xFFF3F1EC);
  static const paper = Color(0xFFFFFFFF);
  static const redBg = Color(0xFFFBE3DC);
  static const amber = Color(0xFFC99A1C);
  static const amberText = Color(0xFF7A5A00);
  static const amberBg = Color(0xFFFBF0D2);
  static const green = Color(0xFF2D6A2D);
  static const rule = Color(0xFFDDDDDD);
  static const muted = Color(0xFF555555);
  static const faint = Color(0xFF777777);
}

class T {
  /// Headline caps (Archivo, width 72, weight 900). Uppercase the text with [Big].
  static TextStyle big(double size, {Color color = C.ink}) =>
      TextStyle(fontFamily: 'ArchivoCondensed', fontSize: size, height: .92, color: color);

  /// Mono labels: IBM Plex Mono 600, caps, spaced.
  static TextStyle mono({double size = 12, Color color = C.ink, FontWeight weight = FontWeight.w600}) =>
      TextStyle(fontFamily: 'Plex', fontWeight: weight, fontSize: size, letterSpacing: size * .06, color: color);

  /// Source lines: Plex 400, grey.
  static TextStyle src({double size = 11.5, Color color = C.muted}) =>
      TextStyle(fontFamily: 'Plex', fontWeight: FontWeight.w400, fontSize: size, height: 1.4, color: color);

  static const lede = TextStyle(fontFamily: 'Archivo', fontSize: 15, height: 1.4, color: C.ink);
  static const name = TextStyle(fontFamily: 'Archivo', fontWeight: FontWeight.w800, fontSize: 18, color: C.ink);
}

ThemeData appTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Archivo',
    scaffoldBackgroundColor: C.paper,
    colorScheme: const ColorScheme.light(
        primary: C.signal, onPrimary: C.paper, secondary: C.ink, surface: C.paper, onSurface: C.ink, error: C.signal),
    splashFactory: NoSplash.splashFactory,
    textSelectionTheme: const TextSelectionThemeData(
        cursorColor: C.signal, selectionColor: C.redBg, selectionHandleColor: C.signal),
    appBarTheme: const AppBarTheme(systemOverlayStyle: SystemUiOverlayStyle.dark),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.ink,
      contentTextStyle: T.mono(color: C.paper),
      shape: const RoundedRectangleBorder(),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(shape: RoundedRectangleBorder(), backgroundColor: C.paper),
  );
  return base;
}

/// Headline in condensed caps.
class Big extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  final TextAlign? align;
  const Big(this.text, {super.key, this.size = 36, this.color = C.ink, this.align});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: T.big(size, color: color), textAlign: align);
}

/// Mono caps label.
class Mono extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  final TextAlign? align;
  const Mono(this.text, {super.key, this.size = 12, this.color = C.ink, this.align});
  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: T.mono(size: size, color: color), textAlign: align);
}

/// The square signal-red button (or the outlined "ghost" one).
class Btn extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool ghost;
  final Color ghostColor;
  final double size;
  final EdgeInsets padding;
  const Btn(this.text,
      {super.key,
      this.onTap,
      this.ghost = false,
      this.ghostColor = C.ink,
      this.size = 22,
      this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) {
    final fg = ghost ? ghostColor : C.paper;
    return Semantics(
      button: true,
      child: Material(
        color: ghost ? Colors.transparent : (onTap == null ? C.faint : C.signal),
        shape: ghost ? Border.all(color: ghostColor, width: 3) : const RoundedRectangleBorder(),
        child: InkWell(
          onTap: onTap,
          highlightColor: ghost ? fg.withValues(alpha: .12) : C.signalDark,
          child: Padding(
            padding: ghost ? padding - const EdgeInsets.all(3) : padding,
            child: SizedBox(
              width: double.infinity,
              child: Text(text.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'ArchivoButton', fontSize: size, color: fg, height: 1.1)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flag chip colors by level: 3 red, 2 amber, 1 neutral, 0 green (only for "none found").
class Tag extends StatelessWidget {
  final String text;
  final int level;
  final double size;
  const Tag(this.text, {super.key, this.level = 2, this.size = 10.5});
  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (level) {
      3 => (C.signalDark, C.redBg),
      2 => (C.amberText, C.amberBg),
      0 => (C.green, C.paper),
      _ => (C.muted, C.label),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: bg, border: Border.all(color: fg, width: 2)),
      child: Text(text.toUpperCase(), style: T.mono(size: size, color: fg).copyWith(letterSpacing: size * .04)),
    );
  }
}

/// The top bar under the status bar: left action, right action, 3px ink rule.
class TopBar extends StatelessWidget {
  final Widget left;
  final Widget? right;
  const TopBar({super.key, required this.left, this.right});

  /// "← Scan" style back link.
  static Widget back(BuildContext context, String label, {VoidCallback? onTap}) => InkWell(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_back, size: 16, color: C.ink),
            const SizedBox(width: 6),
            Mono(label),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.ink, width: 3))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [Flexible(child: left), ?right],
        ),
      );
}

/// Mono label followed by an arrow icon (the bundled fonts have no arrow glyphs).
class MonoLink extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final double size;
  const MonoLink(this.text, {super.key, this.icon = Icons.north_east, this.color = C.signal, this.size = 12});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Mono(text, color: color, size: size),
        const SizedBox(width: 4),
        Icon(icon, size: size + 3, color: color),
      ]);
}

/// Cream panel with the red left rule.
class Panel extends StatelessWidget {
  final Widget child;
  const Panel({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(color: C.label, border: Border(left: BorderSide(color: C.signal, width: 6))),
        child: child,
      );
}

/// Verdict box: red, amber, or neutral.
class VerdictBox extends StatelessWidget {
  final int level; // 3 red, 2 amber, otherwise neutral
  final Widget child;
  const VerdictBox({super.key, required this.level, required this.child});
  @override
  Widget build(BuildContext context) {
    final (border, bg) = switch (level) {
      3 => (C.signal, C.redBg),
      2 => (C.amber, C.amberBg),
      _ => (C.ink, C.label),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border, width: 3)),
      child: child,
    );
  }
}

/// A row with the light grey bottom rule.
class Rule extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const Rule({super.key, required this.child, this.padding = const EdgeInsets.symmetric(vertical: 12), this.onTap});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: padding,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.rule, width: 2))),
      child: child,
    );
    return onTap == null ? box : InkWell(onTap: onTap, child: box);
  }
}
