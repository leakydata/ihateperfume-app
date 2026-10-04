import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/decoder.dart';
import '../my_list.dart';
import '../services.dart';
import '../theme.dart';
import 'search.dart';

const emptyListText = 'Add ingredients you’re allergic to, that irritate you, or that you just want to know about. '
    'When you scan, they’re flagged first. Your list stays on this phone.';

Color reactionColor(Reaction r) => switch (r.level) { 3 => C.signal, 2 => C.amber, _ => C.muted };

/// The "My list" tab: the user's own ingredients, groups, and words to watch for.
class MyListScreen extends StatefulWidget {
  const MyListScreen({super.key});
  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  final _q = TextEditingController();
  List<ListEntry> _list = MyList.current;
  List<NameHit> _results = [];

  @override
  void initState() {
    super.initState();
    _load();
    MyList.changes.addListener(_load);
  }

  @override
  void dispose() {
    MyList.changes.removeListener(_load);
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final l = await MyList.all();
    if (mounted) setState(() => _list = l);
  }

  void _search(String raw) => setState(() => _results = searchNames(raw, max: 30));

  ListEntry? _onList(String id) => _list.where((e) => e.id == id).firstOrNull;

  Future<void> _pick(ListEntry draft) async {
    final added = await editOnList(context, _onList(draft.id) ?? draft, onList: _onList(draft.id) != null);
    if (added && mounted) {
      _q.clear();
      _search('');
      FocusScope.of(context).unfocus();
    }
  }

  void _share() => SharePlus.instance
      .share(ShareParams(text: shareText(decoder, _list), subject: 'My ingredient list'));

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim();
    final searching = Decoder.norm(q).length >= 2;
    return Column(children: [
      TopBar(
        left: Text('MY LIST', style: T.big(30).copyWith(height: 1)),
        right: _list.isEmpty
            ? null
            : InkWell(
                onTap: _share,
                child: const Padding(padding: EdgeInsets.all(8), child: Mono('Share', color: C.signal))),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: TextField(
          controller: _q,
          onChanged: _search,
          textInputAction: TextInputAction.search,
          style: T.src(size: 15, color: C.ink),
          decoration: InputDecoration(
            hintText: 'Add an ingredient…',
            hintStyle: T.src(size: 15, color: C.faint),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, color: C.ink),
                    onPressed: () {
                      _q.clear();
                      _search('');
                    }),
            enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero, borderSide: BorderSide(color: C.ink, width: 3)),
            focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero, borderSide: BorderSide(color: C.signal, width: 3)),
          ),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: searching ? _searchResults(q) : _listView(),
        ),
      ),
    ]);
  }

  List<Widget> _searchResults(String q) => [
        if (Decoder.norm(q).length >= minWordLength)
          _addRow('Any name containing “$q”', EntryKind.word.label, () => _pick(ListEntry(EntryKind.word, q, Reaction.avoid))),
        for (final e in _results)
          _addRow(e.name, e.chip, () => _pick(ListEntry(EntryKind.ingredient, e.name, Reaction.avoid)),
              level: e.level, on: _onList(ListEntry(EntryKind.ingredient, e.name, Reaction.avoid).id)),
        if (_results.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('No ingredient by that name. Check the spelling, or add it as a word above.', style: T.src()),
          ),
      ];

  Widget _addRow(String name, String? chip, VoidCallback onTap, {int level = 1, ListEntry? on}) => Rule(
        padding: const EdgeInsets.symmetric(vertical: 11),
        onTap: onTap,
        child: Row(children: [
          Expanded(child: Text(name, style: T.lede.copyWith(fontSize: 16))),
          const SizedBox(width: 8),
          if (on != null)
            Tag(on.reaction.label, level: on.reaction.level)
          else ...[
            if (chip != null) ...[Tag(chip, level: level), const SizedBox(width: 8)],
            const Icon(Icons.add, size: 20, color: C.signal),
          ],
        ]),
      );

  List<Widget> _listView() {
    final sections = byReaction(_list);
    return [
      Wrap(spacing: 18, children: [
        InkWell(
          onTap: _addGroup,
          child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8), child: MonoLink('Add a group', icon: Icons.add)),
        ),
        InkWell(
          onTap: _addWord,
          child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8), child: MonoLink('Add a word', icon: Icons.add)),
        ),
      ]),
      const SizedBox(height: 10),
      if (_list.isEmpty)
        const Text(emptyListText, style: T.lede)
      else ...[
        for (final MapEntry(key: r, value: entries) in sections.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 2),
            child: Mono(r.label, color: r.level == 1 ? C.ink : reactionColor(r)),
          ),
          for (final e in entries)
            Rule(
              onTap: () => editOnList(context, e, onList: true),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.label(decoder), style: T.name.copyWith(fontSize: 17)),
                    const SizedBox(height: 2),
                    Mono(e.kind.label, size: 10, color: C.muted),
                  ]),
                ),
                const SizedBox(width: 8),
                Tag(e.reaction.label, level: e.reaction.level),
              ]),
            ),
        ],
        const SizedBox(height: 16),
        Text('Your list stays on this phone and is left out of phone backups. Share it to keep a copy.',
            style: T.src()),
      ],
    ];
  }

  Future<void> _addGroup() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(),
      backgroundColor: C.paper,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .92,
        builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 20, 20, 24), children: [
          const Big('Add a group', size: 28),
          const SizedBox(height: 6),
          Text('Flag any ingredient in the group, wherever it’s on a label.', style: T.src()),
          const SizedBox(height: 6),
          for (final (id, label) in listGroups(decoder))
            Rule(
              onTap: () => Navigator.pop(c, id),
              child: Row(children: [
                Expanded(child: Text(label, style: T.lede.copyWith(fontSize: 16))),
                if (_onList(ListEntry(EntryKind.group, id, Reaction.avoid).id) case final on?)
                  Tag(on.reaction.label, level: on.reaction.level)
                else
                  const Icon(Icons.add, size: 20, color: C.signal),
              ]),
            ),
        ]),
      ),
    );
    if (id != null && mounted) await _pick(ListEntry(EntryKind.group, id, Reaction.avoid));
  }

  Future<void> _addWord() async {
    final word = await showDialog<String>(context: context, builder: (c) => const _WordDialog());
    if (word != null && mounted) await _pick(ListEntry(EntryKind.word, word, Reaction.avoid));
  }
}

class _WordDialog extends StatefulWidget {
  const _WordDialog();
  @override
  State<_WordDialog> createState() => _WordDialogState();
}

class _WordDialogState extends State<_WordDialog> {
  final _t = TextEditingController();
  bool get _ok => Decoder.norm(_t.text).length >= minWordLength;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Big('Add a word', size: 26),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Flag any ingredient whose name contains it, like “lavandula” or “coco”.', style: T.src(size: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _t,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _ok ? Navigator.pop(context, _t.text.trim()) : null,
            style: T.src(size: 15, color: C.ink),
            decoration: InputDecoration(
              hintText: 'At least 3 letters',
              hintStyle: T.src(size: 15, color: C.faint),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero, borderSide: BorderSide(color: C.ink, width: 3)),
              focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero, borderSide: BorderSide(color: C.signal, width: 3)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Mono('Cancel')),
          TextButton(
              onPressed: _ok ? () => Navigator.pop(context, _t.text.trim()) : null,
              child: Mono('Next', color: _ok ? C.signal : C.faint)),
        ],
      );
}

/// The reaction sheet: pick how an entry affects you, or take it off the list. Saves the choice.
/// Returns true if the entry is on the list afterwards.
Future<bool> editOnList(BuildContext context, ListEntry entry, {required bool onList}) async {
  const remove = 'remove';
  final choice = await showModalBottomSheet<Object>(
    context: context,
    shape: const RoundedRectangleBorder(),
    backgroundColor: C.paper,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Mono(onList ? 'On my list' : 'Add to my list', color: C.signal),
          const SizedBox(height: 6),
          Big(entry.kind == EntryKind.word ? 'Contains “${entry.value}”' : entry.label(decoder), size: 28),
          const SizedBox(height: 8),
          for (final r in Reaction.values)
            Rule(
              onTap: () => Navigator.pop(c, r),
              child: Row(children: [
                SizedBox(width: 14, height: 14, child: ColoredBox(color: reactionColor(r))),
                const SizedBox(width: 12),
                Expanded(child: Text(r.label, style: T.name.copyWith(fontSize: 17))),
                if (onList && entry.reaction == r) const Icon(Icons.check, size: 20, color: C.ink),
              ]),
            ),
          if (onList)
            InkWell(
              onTap: () => Navigator.pop(c, remove),
              child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14), child: Mono('Remove from my list', color: C.signal)),
            ),
        ]),
      ),
    ),
  );
  if (choice is Reaction) {
    await MyList.add(entry.withReaction(choice));
    return true;
  }
  if (choice == remove) {
    await MyList.remove(entry);
    return false;
  }
  return onList;
}

/// The box at the top of a result: what on the label is on the user's list. Nothing if the list is empty.
class ListBox extends StatelessWidget {
  final ListCheck check;
  final bool hasList;
  final void Function(String item)? onItem;
  const ListBox({super.key, required this.check, required this.hasList, this.onItem});

  @override
  Widget build(BuildContext context) {
    if (!hasList) return const SizedBox.shrink();
    final hidden = check.maybeHidden.isEmpty
        ? const <Widget>[]
        : [
            const SizedBox(height: 10),
            for (final e in check.maybeHidden) _line(e.label(decoder), e.reaction),
            const SizedBox(height: 4),
            Text(maybeHiddenNote, style: T.src(color: C.ink)),
          ];
    if (check.hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(noneNamedNote, style: T.src()),
          if (hidden.isNotEmpty) ...[
            const SizedBox(height: 8),
            Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: hidden.skip(1).toList())),
          ],
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: VerdictBox(
        level: check.level,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Big('On your list: ${check.hits.length}', size: 26),
          const SizedBox(height: 6),
          for (final h in check.hits) _hit(h),
          ...hidden,
        ]),
      ),
    );
  }

  Widget _line(String name, Reaction r) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Expanded(child: Text(name, style: T.name.copyWith(fontSize: 17))),
          const SizedBox(width: 8),
          Tag(r.label, level: r.level),
        ]),
      );

  Widget _hit(ListHit h) {
    final detail = h.entry.kind == EntryKind.ingredient
        ? h.matches.map((m) => m.how).where((x) => x != 'Same ingredient').toSet().join(' · ')
        : 'On the label: ${h.items.join(', ')}';
    return InkWell(
      onTap: onItem == null ? null : () => onItem!(h.items.first),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _line(h.entry.label(decoder), h.entry.reaction),
          if (detail.isNotEmpty) Text(detail, style: T.src(color: C.ink)),
        ]),
      ),
    );
  }
}
