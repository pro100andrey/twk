// The ListTile page.
part of 'controls.dart';

final _listtilePage = GalleryPage(
  group: 'Controls',
  title: 'ListTile',
  options: const [
    SwitchOption('leading', 'leading', initial: true),
    SwitchOption('subtitle', 'subtitle', initial: true),
    SwitchOption('trailing', 'trailing', initial: true),
  ],
  build: (context, o) => _Tiles(
    leading: o.flag('leading'),
    subtitle: o.flag('subtitle'),
    trailing: o.flag('trailing'),
  ),
  code: (o) {
    final leading = o.flag('leading');
    final subtitle = o.flag('subtitle');
    final trailing = o.flag('trailing');
    return [
      'var _open = 0;',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  const files = [',
      for (final (name, about) in _tileFiles) "    ('$name', '$about'),",
      '  ];',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    children: [',
      '      for (final (i, (name, about)) in files.indexed)',
      '        ListTile(',
      if (leading) "          leading: const Text('▤'),",
      '          title: Text(name),',
      if (subtitle) '          subtitle: Text(about),',
      if (trailing) "          trailing: const Text('›'),",
      '          selected: i == _open,',
      '          enabled: i != 3,',
      '          onTap: () => setState(() => _open = i),',
      '        ),',
      '    ],',
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
  Widget build(BuildContext context) => Column(
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
  );
}
