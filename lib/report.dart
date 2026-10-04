/// Turns a decoder [Result] into what the screens show: one row per flagged ingredient, each flag with its
/// source. Wording follows the website's label decoder (decoder.js and decoder-flags.js).
library;

import 'engine/decoder.dart';

const site = 'https://ihateperfume.com';

/// One reason an ingredient is flagged, always with where it comes from.
class Reason {
  final String title; // short name, e.g. "Skin allergen"
  final String label; // the full category label
  final String help; // what the category means
  final String detail; // e.g. "Skin Sens. 1B (H317)"
  final String source; // e.g. "EU CLP Regulation, Annex VI harmonized classification"
  final String? url;
  final int level;
  const Reason(this.title, this.label, this.help, this.detail, this.source, this.url, this.level);
}

class IngRow {
  final String item;
  final String? guess; // the ingredient a misspelling was read as
  final List<Reason> reasons; // worst first
  final int index; // position on the label
  const IngRow(this.item, this.guess, this.reasons, this.index);
  int get worst => reasons.fold(0, (m, r) => r.level > m ? r.level : m);

  /// Chips: one per distinct title, worst first.
  List<(String, int)> get chips {
    final seen = <String>{};
    return [
      for (final r in reasons)
        if (seen.add(r.title)) (r.title, r.level)
    ];
  }
}

class Report {
  final Result result;
  final List<IngRow> rows; // worst first, then label order
  final List<String> unflagged;
  final String? declared; // first "Fragrance"/"Parfum"-type item, for the verdict line
  const Report(this.result, this.rows, this.unflagged, this.declared);

  int get scentCount => result.fragranceCount;
  bool get empty => result.items.isEmpty;

  /// 3 red, 2 amber, 1 nothing found. Fragrance on the label counts as red here, as in the mockups.
  int get boxLevel => result.verdict == Verdict.red || scentCount > 0 ? 3 : (result.verdict == Verdict.amber ? 2 : 1);

  String get headline {
    if (scentCount > 0) return '$scentCount scent ingredient${scentCount == 1 ? '' : 's'}';
    if (result.redShort.isNotEmpty) {
      return '${result.redShort.length} red flag${result.redShort.length == 1 ? '' : 's'}';
    }
    if (result.amberShort.isNotEmpty) return 'Worth a closer look';
    return 'No fragrance found on our lists';
  }

  /// The website's verdict line.
  String get verdictLine {
    if (result.redShort.isNotEmpty) {
      return '${result.redShort.length} red flag${result.redShort.length == 1 ? '' : 's'}: ${result.redShort.join(' · ')}';
    }
    if (result.amberShort.isNotEmpty) return 'No red flags, but worth a closer look: ${result.amberShort.join(' · ')}';
    if (scentCount > 0) return 'Contains fragrance. No other flags found on our lists.';
    return 'No fragrance and no red flags found on our lists. That’s a good sign, not a guarantee: see what this '
        'can’t check below.';
  }

  /// Short summary for the recent-scans chip.
  (String, int) get tag {
    if (empty) return ('Empty', 1);
    if (result.redShort.isNotEmpty) return ('${result.redShort.length} red', 3);
    if (scentCount > 0) return ('$scentCount scent', 3);
    if (result.amberShort.isNotEmpty) return ('Look closer', 2);
    return ('None found', 0);
  }

  static Report build(Decoder d, String text, {ProductType ptype = ''}) {
    final r = d.decode(text, ptype: ptype);
    final byItem = <String, List<Reason>>{};
    final guesses = <String, String?>{};
    void add(String item, Reason reason) => (byItem[item] ??= []).add(reason);

    for (final f in r.fragrance) {
      add(
          f.item,
          Reason('Hidden mixture', 'Fragrance declared', '',
              '${f.label}. The individual chemicals in the mixture don’t have to be listed.', 'the ingredient list itself',
              null, 3));
    }
    for (final a in r.allergens) {
      add(a.item, _allergen(d, a));
    }
    for (final p in r.plantOils) {
      add(
          p,
          Reason('Scented plant oil', 'Scented plant oils and extracts', '',
              'Probably a scented plant ingredient. Essential oils are fragrance too, and they can contain the same allergens.',
              'ihateperfume.com label decoder (plant oil names)', '$site/label-decoder/', 2));
    }
    for (final row in d.shown(r)) {
      guesses[row.item] = row.guess;
      final flags = [...row.flags]..sort((a, b) => d.cat(b.cat).level - d.cat(a.cat).level);
      for (final f in flags) {
        final c = d.cat(f.cat);
        final s = d.sources[f.src];
        var url = f.url ?? s?['url'] as String?;
        if (url != null && url.startsWith('/')) url = '$site$url';
        add(row.item, Reason(c.short, c.label, c.help, f.detail, (s?['label'] as String?) ?? f.src, url, c.level));
      }
    }

    final rows = <IngRow>[];
    final unflagged = <String>[];
    for (var i = 0; i < r.items.length; i++) {
      final item = r.items[i];
      final reasons = byItem.remove(item);
      if (reasons == null) {
        // The same name twice on one label is listed once.
        if (!rows.any((x) => x.item == item)) unflagged.add(item);
        continue;
      }
      reasons.sort((a, b) => b.level - a.level);
      rows.add(IngRow(item, guesses[item], reasons, i));
    }
    rows.sort((a, b) => a.worst != b.worst ? b.worst - a.worst : a.index - b.index);
    return Report(r, rows, unflagged, r.fragrance.isEmpty ? null : r.fragrance.first.item);
  }

  static Reason _allergen(Decoder d, AllergenHit a) => switch (a.kind) {
        'eu-original' => Reason(
            'Labeled fragrance allergen (EU)',
            'EU-listed fragrance allergen',
            'Fragrance allergens the EU requires on the label above a set amount.',
            'EU-listed fragrance allergen (one of the original 26)',
            'EU Cosmetics Regulation, Annex III (restricted)',
            'https://eur-lex.europa.eu/eli/reg/2009/1223/oj/eng',
            2),
        'eu-2023' => Reason(
            'Fragrance allergen (EU 2023)',
            'Added to the EU allergen list in 2023',
            'Fragrance allergens the EU requires on the label above a set amount.',
            'Added to the EU allergen list in 2023 (labeling phases in 2026 to 2028)',
            'EU Regulation 2023/1545',
            'https://eur-lex.europa.eu/eli/reg/2023/1545/oj/eng',
            2),
        'eu-banned' => Reason('Banned in EU cosmetics', 'Prohibited in cosmetics in the EU', '', a.note,
            'EU Cosmetics Regulation, Annex II (prohibited)', 'https://eur-lex.europa.eu/eli/reg/2009/1223/oj/eng', 3),
        _ => Reason('Fragrance allergen', 'Fragrance allergen', '', 'Fragrance allergen', 'ihateperfume.com label decoder',
            '$site/label-decoder/', 2),
      };
}
