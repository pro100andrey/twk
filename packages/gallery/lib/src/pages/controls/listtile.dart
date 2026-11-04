// The ListTile page.
part of 'controls.dart';

/// The ListTile page's `leading` option.
const _listtileLeading = SwitchOption(
  'leading',
  'leading',
  initial: true,
);

/// The ListTile page's `subtitle` option.
const _listtileSubtitle = SwitchOption(
  'subtitle',
  'subtitle',
  initial: true,
);

/// The ListTile page's `trailing` option.
const _listtileTrailing = SwitchOption(
  'trailing',
  'trailing',
  initial: true,
);

final _listtilePage = GalleryPage(
  group: _group,
  title: 'ListTile',
  options: const [
    _listtileLeading,
    _listtileSubtitle,
    _listtileTrailing,
  ],
  build: (context, o) => _Tiles(
    leading: o(_listtileLeading),
    subtitle: o(_listtileSubtitle),
    trailing: o(_listtileTrailing),
  ),
  code: (o) {
    final leading = o(_listtileLeading);
    final subtitle = o(_listtileSubtitle);
    final trailing = o(_listtileTrailing);
    return [
      'var _open = 0;',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  const files = [',
      for (final (name, about) in _tileFiles) "    ('$name', '$about'),",
      '  ];',
      '  return SizedBox(',
      '    width: 32,',
      '    child: Column(',
      '      mainAxisSize: .min,',
      '      children: [',
      '        for (final (i, (name, about)) in files.indexed)',
      '          ListTile(',
      if (leading) "            leading: const Text('▤'),",
      '            title: Text(name),',
      if (subtitle) '            subtitle: Text(about),',
      if (trailing) "            trailing: const Text('›'),",
      '            selected: i == _open,',
      '            enabled: i != 3,',
      '            onTap: () => setState(() => _open = i),',
      '          ),',
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The files of the ListTile page, each with what it is; the last is the
/// disabled one.
const _tileFiles = [
  ('notes.md', '2 KB, an hour ago'),
  ('todo.md', '640 B, today'),
  ('photo.png', '1.2 MB, last week'),
  ('locked.txt', 'no access'),
];

/// The ListTile page: the files, the one tapped open (selected), its parts
/// as the options say.
final class _Tiles extends StatefulWidget {
  const _Tiles({
    required this.leading,
    required this.subtitle,
    required this.trailing,
  });

  final bool leading;
  final bool subtitle;
  final bool trailing;

  @override
  State<_Tiles> createState() => _TilesState();
}

final class _TilesState extends State<_Tiles> with KeptState {
  // kept in the page's state while the gallery runs
  int get _open => kept['open'] as int? ?? 0;
  set _open(int i) => kept['open'] = i;

  @override
  // a ListTile is as wide as it is let be: the list is given a width of
  // its own, as a list in an app is, not the stage's
  Widget build(BuildContext context) => SizedBox(
    width: 32,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (name, about)) in _tileFiles.indexed)
          ListTile(
            leading: widget.leading ? const Text('▤') : null,
            title: Text(name),
            subtitle: widget.subtitle ? Text(about) : null,
            trailing: widget.trailing ? const Text('›') : null,
            selected: i == _open,
            enabled: i != 3,
            onTap: () => setState(() => _open = i),
          ),
      ],
    ),
  );
}
