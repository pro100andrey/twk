// The Overlay page.
part of 'overlays.dart';

final _overlayPage = GalleryPage(
  group: 'Overlays',
  title: 'Overlay',
  options: [
    ChoiceOption('position', 'positioned', values: _entryAt.keys.toList()),
    const SwitchOption('shadow', 'shadow', initial: true),
    _lookOption,
  ],
  build: (context, o) => _Entries(
    position: o.choice('position'),
    shadow: o.flag('shadow'),
    look: _lookOf(o),
  ),
  code: (o) => [
    'final _entries = <OverlayEntry>[];',
    '',
    '@override',
    'void dispose() {',
    '  for (final entry in _entries) {',
    '    entry.remove();',
    '  }',
    '  super.dispose();',
    '}',
    '',
    'void _insert() {',
    '  final n = _entries.length + 1;',
    '  final entry = OverlayEntry(',
    '    builder: (context) => Positioned(',
    for (final a in _entryAt[o.choice<String>('position')]!) '      $a,',
    '      child: Panel(',
    ..._lookLine(o, '        '),
    '        padding: const .x(1),',
    if (!o.flag('shadow')) '        shadow: false,',
    '        child: Text.rich([',
    r"          'Entry $n'.bold,",
    "          Span(' of the overlay', Theme.of(context).muted),",
    '        ]),',
    '      ),',
    '    ),',
    '  );',
    '  Overlay.of(context).insert(entry);',
    '  setState(() => _entries.add(entry));',
    '}',
    '',
    'void _remove() => setState(() => _entries.removeLast().remove());',
    '',
    '@override',
    'Widget build(BuildContext context) => Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  gap: 1,',
    '  children: [',
    '    Row(',
    '      mainAxisSize: .min,',
    '      gap: 2,',
    '      children: [',
    '        Button(',
    "          'Insert an entry',",
    '          onPressed: _entries.length < 3 ? _insert : null,',
    '        ),',
    _removeLine,
    '      ],',
    '    ),',
    '    Text.rich([',
    "      Span('entries: ', Theme.of(context).muted),",
    r"      Span('${_entries.length}'),",
    "      Span(' of the overlay', Theme.of(context).muted),",
    '    ]),',
    '  ],',
    ');',
  ].join('\n'),
);

/// The Code's line of the Remove button.
const _removeLine =
    "        Button('Remove one', onPressed: _entries.isEmpty ? null : "
    '_remove),';

/// Where the n-th entry of the Overlay page goes, as its Code writes it.
const _entryAt = {
  'topRight': ['right: 4 * n - 3', 'top: 2 * n - 1'],
  'topLeft': ['left: 4 * n - 3', 'top: 2 * n - 1'],
  'bottomLeft': ['left: 4 * n - 3', 'bottom: 7 - 2 * n'],
};

/// Two buttons that insert entries into the app's overlay and remove them,
/// and how many there are. The gallery keeps how many while it runs, and
/// shows them again when the page comes back (on the Code tab too, as the
/// design's overlay does).
final class _Entries extends StatefulWidget {
  const _Entries({
    required this.position,
    required this.shadow,
    required this.look,
  });

  final String position;
  final bool shadow;
  final PanelLook look;

  @override
  State<_Entries> createState() => _EntriesState();
}

final class _EntriesState extends State<_Entries> with KeptState {
  final _entries = <OverlayEntry>[];
  var _restored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) {
      return;
    }
    _restored = true;
    final n = kept['entries'] as int? ?? 0;
    if (n > 0) {
      // an entry goes in outside a build
      unawaited(
        Future.microtask(() {
          for (var i = 0; mounted && i < n; i++) {
            _insert(keep: false);
          }
        }),
      );
    }
  }

  @override
  void didUpdateWidget(_Entries oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position ||
        oldWidget.shadow != widget.shadow ||
        oldWidget.look != widget.look) {
      for (final entry in _entries) {
        entry.markNeedsBuild();
      }
    }
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.remove();
    }
    super.dispose();
  }

  Widget _entry(BuildContext context, int n) {
    final theme = Theme.of(context);
    final box = Panel(
      look: widget.look,
      padding: const EdgeInsets.x(1),
      shadow: widget.shadow,
      child: Text.rich([
        'Entry $n'.bold,
        Span(' of the overlay', theme.muted),
      ]),
    );
    return switch (widget.position) {
      'topLeft' => Positioned(left: 4 * n - 3, top: 2 * n - 1, child: box),
      'bottomLeft' => Positioned(
        left: 4 * n - 3,
        bottom: 7 - 2 * n,
        child: box,
      ),
      _ => Positioned(right: 4 * n - 3, top: 2 * n - 1, child: box),
    };
  }

  void _insert({bool keep = true}) {
    final n = _entries.length + 1;
    final entry = OverlayEntry(builder: (context) => _entry(context, n));
    Overlay.of(context).insert(entry);
    setState(() => _entries.add(entry));
    if (keep) {
      kept['entries'] = _entries.length;
    }
  }

  void _remove() {
    setState(() => _entries.removeLast().remove());
    kept['entries'] = _entries.length;
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        gap: 2,
        children: [
          Button(
            'Insert an entry',
            onPressed: _entries.length < 3 ? _insert : null,
          ),
          Button('Remove one', onPressed: _entries.isEmpty ? null : _remove),
        ],
      ),
      Text.rich([
        Span('entries: ', Theme.of(context).muted),
        Span('${_entries.length}'),
        Span(' of the overlay', Theme.of(context).muted),
      ]),
    ],
  );
}
