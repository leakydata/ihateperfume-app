/// "My list": the user's own ingredients to watch, matched against a scanned label. Stored only on this phone
/// (shared preferences, left out of backups like recent scans). The matching here has no widgets in it.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/decoder.dart';
import 'report.dart';

enum Reaction {
  allergic('Allergic', 3),
  irritates('Irritates me', 2),
  avoid('Avoid', 2),
  tellMe('Just tell me', 1);

  final String label;
  final int level; // 3 red, 2 amber, 1 neutral (as Tag and VerdictBox)
  const Reaction(this.label, this.level);

  static Reaction parse(String? s) => Reaction.values.firstWhere((r) => r.name == s, orElse: () => Reaction.tellMe);
}

enum EntryKind {
  ingredient('Ingredient'),
  group('Group'),
  word('Name contains');

  final String label;
  const EntryKind(this.label);
}

/// One thing on the list: an ingredient name, a built-in group id, or a word a name can contain.
class ListEntry {
  final EntryKind kind;
  final String value; // ingredient name as written, group id ('fragrance', 'allergen', 'plant-oil', 'cat:<key>'), or word
  final Reaction reaction;
  const ListEntry(this.kind, this.value, this.reaction);

  /// Two entries are the same thing on the list if kind and normalized value match.
  String get id => '${kind.name}:${kind == EntryKind.group ? value : Decoder.norm(value)}';

  ListEntry withReaction(Reaction r) => ListEntry(kind, value, r);

  String label(Decoder d) => kind == EntryKind.group ? groupLabel(d, value) : value;

  Map<String, dynamic> toJson() => {'k': kind.name, 'v': value, 'r': reaction.name};
  static ListEntry? fromJson(Map<String, dynamic> j) {
    final k = EntryKind.values.where((x) => x.name == j['k']).firstOrNull;
    final v = j['v'];
    if (k == null || v is! String || v.isEmpty) return null;
    return ListEntry(k, v, Reaction.parse(j['r'] as String?));
  }

  @override
  bool operator ==(Object other) => other is ListEntry && other.id == id && other.reaction == reaction;
  @override
  int get hashCode => Object.hash(id, reaction);
}

// ---------- groups ----------

const _fixedGroups = {
  'fragrance': 'Any fragrance or parfum',
  'allergen': 'Any EU-labeled fragrance allergen',
  'plant-oil': 'Any scented plant oil',
};

/// Every group the user can pick: the three fragrance groups, then one per decoder category, worst first.
List<(String, String)> listGroups(Decoder d) {
  final cats = d.cats.entries.toList()
    ..sort((a, b) => a.value.level != b.value.level
        ? b.value.level - a.value.level
        : a.value.short.toLowerCase().compareTo(b.value.short.toLowerCase()));
  return [
    for (final e in _fixedGroups.entries) (e.key, e.value),
    for (final c in cats) ('cat:${c.key}', c.value.short),
  ];
}

String groupLabel(Decoder d, String id) =>
    _fixedGroups[id] ?? (id.startsWith('cat:') ? d.cat(id.substring(4)).short : id);

/// The minimum length of a "name contains" word (normalized).
const minWordLength = 3;

// ---------- matching ----------

class ListMatch {
  final String item; // as written on the label
  final String how; // e.g. "Same ingredient", "Listed as “Parfum (Fragrance)”", "Contains “coco”"
  const ListMatch(this.item, this.how);
}

class ListHit {
  final ListEntry entry;
  final List<ListMatch> matches;
  const ListHit(this.entry, this.matches);
  List<String> get items => [for (final m in matches) m.item];
  String get how => matches.first.how;
}

class ListCheck {
  final List<ListHit> hits; // worst reaction first, then list order
  final List<ListEntry> maybeHidden; // fragrance ingredients on the list that the label's "Fragrance" could hide
  const ListCheck(this.hits, this.maybeHidden);
  static const none = ListCheck([], []);

  /// 3 if anything allergic matched, 2 for irritates/avoid, 1 for "just tell me", 0 if nothing matched.
  int get level => hits.fold(0, (m, h) => h.entry.reaction.level > m ? h.entry.reaction.level : m);

  /// The worst reaction for one label item, for its chip.
  Reaction? reactionFor(String item) {
    Reaction? worst;
    for (final h in hits) {
      if (h.items.contains(item) && (worst == null || h.entry.reaction.level > worst.level)) worst = h.entry.reaction;
    }
    return worst;
  }
}

const maybeHiddenNote = 'Could be inside “Fragrance”: labels don’t have to name every fragrance ingredient.';
const noneNamedNote = 'None of your list is named on this label.';

final _fragranceWord = RegExp(r'\b(fragrance|parfum|perfume)\b', caseSensitive: false);
const _fragranceNames = {'fragrance', 'parfum', 'perfume'};

final _allergenNorms = Expando<Set<String>>();
Set<String> _allergenSet(Decoder d) => _allergenNorms[d] ??= {for (final n in d.allergenNames) Decoder.norm(n)};

/// Is this ingredient name a known fragrance ingredient: an EU fragrance allergen, or flagged as a scent ingredient?
bool isFragranceIngredient(Decoder d, String name) {
  final n = Decoder.norm(name);
  if (_fragranceNames.contains(n)) return false; // "Fragrance" itself is the declared mixture
  if (_allergenSet(d).contains(n)) return true;
  final i = d.itemIndex(n);
  return i != null && d.itemCats(i).contains('scent-ingredient');
}

/// How a label item matches an ingredient entry, or null. [guess] is the name a misspelled item was read as.
String? ingredientMatch(Decoder d, String entryName, String item, {String? guess}) {
  final e = Decoder.norm(entryName);
  if (e.isEmpty) return null;
  final ei = d.itemIndex(e);
  bool same(String s) {
    final n = Decoder.norm(s);
    return n.isNotEmpty && (n == e || (ei != null && d.itemIndex(n) == ei));
  }

  final whole = Decoder.norm(item);
  if (whole == e) return 'Same ingredient';
  if (same(item)) return 'Listed as “$item”';
  // Like the decoder: without the parentheses, then each part in parentheses ("Parfum (Fragrance)").
  if (item.contains('(')) {
    final parts = [
      item.replaceAll(RegExp(r'\([^)]*\)'), ' '),
      for (final m in RegExp(r'\(([^)]+)\)').allMatches(item)) m.group(1)!,
    ];
    if (parts.any(same)) return 'Listed as “$item”';
  }
  // Fragrance, parfum, and perfume are the same declared mixture.
  if (_fragranceNames.contains(e) && _fragranceWord.hasMatch(item)) return 'Listed as “$item”';
  if (guess != null && same(guess)) return 'Read as “$guess” from “$item”';
  return null;
}

/// Match a report against the list.
ListCheck checkList(Decoder d, Report r, List<ListEntry> entries) {
  if (entries.isEmpty || r.empty) return ListCheck.none;
  final res = r.result;
  final guesses = {for (final row in res.rows) row.item: row.guess};
  final hits = <ListHit>[];
  final hidden = <ListEntry>[];
  for (final entry in entries) {
    final found = <String, String>{}; // item -> how (first way found)
    void add(String item, String how) => found.putIfAbsent(item, () => how);
    switch (entry.kind) {
      case EntryKind.ingredient:
        for (final item in res.items) {
          final how = ingredientMatch(d, entry.value, item, guess: guesses[item]);
          if (how != null) add(item, how);
        }
        // An EU allergen named inside a longer item, as the decoder finds it.
        final e = Decoder.norm(entry.value);
        for (final a in res.allergens) {
          if (Decoder.norm(a.name) == e) add(a.item, 'Named in “${a.item}”');
        }
      case EntryKind.group:
        final how = 'In group “${groupLabel(d, entry.value)}”';
        switch (entry.value) {
          case 'fragrance':
            for (final f in res.fragrance) {
              add(f.item, how);
            }
          case 'allergen':
            for (final a in res.allergens) {
              add(a.item, how);
            }
          case 'plant-oil':
            for (final p in res.plantOils) {
              add(p, how);
            }
          default:
            if (entry.value.startsWith('cat:')) {
              final c = entry.value.substring(4);
              for (final row in res.rows) {
                if (row.flags.any((f) => f.cat == c)) add(row.item, how);
              }
            }
        }
      case EntryKind.word:
        final w = Decoder.norm(entry.value);
        if (w.length >= minWordLength) {
          for (final item in res.items) {
            if (Decoder.norm(item).contains(w)) add(item, 'Contains “${entry.value.trim()}”');
          }
        }
    }
    if (found.isNotEmpty) {
      // Label order.
      final items = res.items.where(found.containsKey).toSet();
      hits.add(ListHit(entry, [for (final i in items) ListMatch(i, found[i]!)]));
    } else if (entry.kind == EntryKind.ingredient &&
        res.fragrance.isNotEmpty &&
        isFragranceIngredient(d, entry.value)) {
      hidden.add(entry);
    }
  }
  final order = {for (var i = 0; i < entries.length; i++) entries[i].id: i};
  hits.sort((a, b) => a.entry.reaction.level != b.entry.reaction.level
      ? b.entry.reaction.level - a.entry.reaction.level
      : order[a.entry.id]! - order[b.entry.id]!);
  return ListCheck(hits, hidden);
}

/// The matched entries only (see [checkList] for the "could be inside Fragrance" ones too).
List<ListHit> matchList(Report r, List<ListEntry> entries, Decoder d) => checkList(d, r, entries).hits;

/// The list entry for one ingredient name, if the user has it on the list as an ingredient.
ListEntry? ingredientEntryFor(Decoder d, List<ListEntry> entries, String name, {String? guess}) {
  for (final e in entries) {
    if (e.kind == EntryKind.ingredient && ingredientMatch(d, e.value, name, guess: guess) != null) return e;
  }
  return null;
}

/// The list grouped by reaction, allergic first.
Map<Reaction, List<ListEntry>> byReaction(List<ListEntry> entries) => {
      for (final r in Reaction.values)
        if (entries.any((e) => e.reaction == r)) r: entries.where((e) => e.reaction == r).toList(),
    };

String shareText(Decoder d, List<ListEntry> entries) {
  final lines = ['My ingredient list (I Hate Perfume app)'];
  for (final group in byReaction(entries).values) {
    for (final e in group) {
      final name = switch (e.kind) {
        EntryKind.ingredient => e.value,
        EntryKind.group => '${e.label(d)} (group)',
        EntryKind.word => 'Any name containing “${e.value}”',
      };
      lines.add('- $name: ${e.reaction.label}');
    }
  }
  return lines.join('\n');
}

// ---------- persistence ----------

class MyList {
  static const key = 'my-list';
  static final changes = _Changes();
  static List<ListEntry> _cache = const [];

  /// The list as last loaded or saved (empty until [all] has run once).
  static List<ListEntry> get current => _cache;

  static Future<List<ListEntry>> all() async {
    final p = await SharedPreferences.getInstance();
    try {
      _cache = [
        for (final j in (jsonDecode(p.getString(key) ?? '[]') as List).cast<Map<String, dynamic>>())
          ?ListEntry.fromJson(j),
      ];
    } catch (_) {
      _cache = const [];
    }
    return _cache;
  }

  static Future<void> _save(List<ListEntry> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode([for (final e in list) e.toJson()]));
    _cache = List.unmodifiable(list);
    changes.bump();
  }

  /// Adds the entry, or changes its reaction if it's already on the list.
  static Future<void> add(ListEntry e) async {
    final list = [...await all()];
    final i = list.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      list[i] = e;
    } else {
      list.add(e);
    }
    await _save(list);
  }

  static Future<void> update(ListEntry e, Reaction r) => add(e.withReaction(r));

  static Future<void> remove(ListEntry e) async {
    final list = [...await all()]..removeWhere((x) => x.id == e.id);
    await _save(list);
  }

  static Future<void> clear() => _save(const []);
}

class _Changes extends ChangeNotifier {
  void bump() => notifyListeners();
}

/// Reports for recent scans, kept in memory so the home screen can check them against the list without decoding
/// every label on every rebuild. The result screen adds the report it built.
class ReportCache {
  static const _max = 60;
  static final _m = <String, Report>{};

  static Report? peek(String text) => _m[text];

  static void put(String text, Report r) {
    _m.remove(text);
    _m[text] = r;
    if (_m.length > _max) _m.remove(_m.keys.first);
  }

  static Report get(Decoder d, String text) {
    final r = _m[text] ?? Report.build(d, text);
    put(text, r);
    return r;
  }
}
