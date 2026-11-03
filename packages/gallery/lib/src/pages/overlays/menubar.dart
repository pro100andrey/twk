// The MenuBar page.
part of 'overlays.dart';

/// The MenuBar page's `keys` option.
const _menubarKeys = SwitchOption(
  'keys',
  'keys bound',
  initial: true,
);

final _menubarPage = GalleryPage(
  group: _group,
  title: 'MenuBar',
  // an open menu takes Tab itself
  modalTab: false,
  options: [
    _menubarKeys,
    _lookOption,
  ],
  build: (context, o) => _Bar(keys: o(_menubarKeys), look: _lookOf(o)),
  code: _menuBarCode,
);

/// The MenuBar page's Code.
String _menuBarCode(Options o) {
  final keys = o(_menubarKeys);
  String on(String fn, String closure) => keys ? fn : closure;
  return [
    'final _menus = MenuController();',
    'String? _chosen;',
    'var _wrap = true;',
    'var _numbers = false;',
    '',
    '@override',
    'void dispose() {',
    '  _menus.dispose();',
    '  super.dispose();',
    '}',
    '',
    'void _choose(String what) => setState(() => _chosen = what);',
    if (keys) ...[
      "void _open() => _choose('Open');",
      "void _save() => _choose('Save');",
      "void _undo() => _choose('Undo');",
    ],
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final child = Padding(',
    '    padding: const .all(1),',
    '    child: Column(',
    '      crossAxisAlignment: .start,',
    '      gap: 1,',
    '      children: [',
    '        Text.rich([',
    "          Span('chosen: ', Theme.of(context).muted),",
    '          switch (_chosen) {',
    "            null => Span('nothing', Theme.of(context).muted),",
    '            final chosen => Span(chosen),',
    '          },',
    '        ]),',
    '        Row(',
    '          gap: 2,',
    '          children: [',
    '            Checkbox(',
    '              value: _wrap,',
    "              label: 'wrap lines',",
    '              onChanged: (value) => setState(() => _wrap = value),',
    '            ),',
    '            // File › Open recent, opened from outside the bar',
    '            Button(',
    "              'Recent files',",
    '              onPressed: () => _menus.open([0, 2]),',
    '            ),',
    '          ],',
    '        ),',
    '      ],',
    '    ),',
    '  );',
    '  return SizedBox(',
    '    width: 48,',
    '    height: 8,',
    '    child: MenuBar(',
    '      controller: _menus,',
    ..._lookLine(o, '      '),
    '      menus: [',
    '        Menu(',
    "          '&File',",
    '          items: [',
    "            MenuItem('&New', onSelected: () => _choose('New')),",
    _item('&Open…', on('_open', "() => _choose('Open')")),
    '            Menu(',
    "              'Open &recent',",
    '              items: [',
    '                for (final file in const [',
    "                  'main.dart',",
    "                  'page.dart',",
    "                  'overlay.dart',",
    '                ])',
    '                  MenuItem(file, onSelected: () => _choose(file)),',
    '              ],',
    '            ),',
    '            const MenuDivider(),',
    _item('&Save', on('_save', "() => _choose('Save')")),
    "            const MenuItem('&Print'),",
    '          ],',
    '        ),',
    '        Menu(',
    "          '&Edit',",
    '          items: [',
    _item('&Undo', on('_undo', "() => _choose('Undo')")),
    "            const MenuItem('&Redo'),",
    '            const MenuDivider(),',
    "            for (final what in const ['Cu&t', '&Copy', '&Paste'])",
    '              MenuItem(',
    '                what,',
    "                onSelected: () => _choose(what.replaceAll('&', '')),",
    '              ),',
    '          ],',
    '        ),',
    '        Menu(',
    "          '&View',",
    '          items: [',
    '            MenuItem(',
    "              '&Wrap lines',",
    '              checked: _wrap,',
    '              onSelected: () => setState(() {',
    '                _wrap = !_wrap;',
    "                _chosen = 'Wrap lines';",
    '              }),',
    '            ),',
    '            MenuItem(',
    "              'Line &numbers',",
    '              checked: _numbers,',
    '              onSelected: () => setState(() {',
    '                _numbers = !_numbers;',
    "                _chosen = 'Line numbers';",
    '              }),',
    '            ),',
    '          ],',
    '        ),',
    '      ],',
    if (keys) ...[
      '      // the items show the keys bound to what they call',
      '      child: KeyBindings(',
      "        {'ctrl+o': _open, 'ctrl+s': _save, 'ctrl+z': _undo},",
      '        child: child,',
      '      ),',
    ] else
      '      child: child,',
    '    ),',
    '  );',
    '}',
  ].join('\n');
}

/// The Code's line of a menu item [label] that calls [call].
String _item(String label, String call) =>
    "            MenuItem('$label', onSelected: $call),";

/// A menu bar over what was chosen and a checkbox the View menu flips too.
final class _Bar extends StatefulWidget {
  const _Bar({required this.keys, required this.look});

  final bool keys;
  final PanelLook look;

  @override
  State<_Bar> createState() => _BarState();
}

final class _BarState extends State<_Bar> with KeptState {
  String? get _chosen => kept['chosen'] as String?;
  bool get _wrap => kept['wrap'] as bool? ?? true;
  bool get _numbers => kept['numbers'] as bool? ?? false;
  int get _serial => kept['serial'] as int? ?? 0;

  void _set(void Function() change) => setState(change);

  void _choose(String what) => _set(() {
    kept['chosen'] = what;
    kept['serial'] = _serial + 1;
  });
  void _open() => _choose('Open');
  void _save() => _choose('Save');
  void _undo() => _choose('Undo');

  final _menus = MenuController();

  @override
  void dispose() {
    _menus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.keys;
    final child = Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: [
          LitLine([
            ('chosen: ', true),
            (_chosen ?? 'nothing', _chosen == null),
          ], serial: _serial),
          Row(
            gap: 2,
            children: [
              Checkbox(
                value: _wrap,
                label: 'wrap lines',
                onChanged: (value) => _set(() => kept['wrap'] = value),
              ),
              Button('Recent files', onPressed: () => _menus.open([0, 2])),
            ],
          ),
        ],
      ),
    );
    return SizedBox(
      width: 48,
      height: 8,
      child: MenuBar(
        controller: _menus,
        look: widget.look,
        menus: [
          Menu(
            '&File',
            items: [
              MenuItem('&New', onSelected: () => _choose('New')),
              MenuItem('&Open…', onSelected: _open),
              Menu(
                'Open &recent',
                items: [
                  for (final file in const [
                    'main.dart',
                    'page.dart',
                    'overlay.dart',
                  ])
                    MenuItem(file, onSelected: () => _choose(file)),
                ],
              ),
              const MenuDivider(),
              MenuItem('&Save', onSelected: _save),
              const MenuItem('&Print'),
            ],
          ),
          Menu(
            '&Edit',
            items: [
              MenuItem('&Undo', onSelected: _undo),
              const MenuItem('&Redo'),
              const MenuDivider(),
              for (final what in const ['Cu&t', '&Copy', '&Paste'])
                MenuItem(
                  what,
                  onSelected: () => _choose(what.replaceAll('&', '')),
                ),
            ],
          ),
          Menu(
            '&View',
            items: [
              MenuItem(
                '&Wrap lines',
                checked: _wrap,
                onSelected: () {
                  kept['wrap'] = !_wrap;
                  _choose('Wrap lines');
                },
              ),
              MenuItem(
                'Line &numbers',
                checked: _numbers,
                onSelected: () {
                  kept['numbers'] = !_numbers;
                  _choose('Line numbers');
                },
              ),
            ],
          ),
        ],
        child: keys
            ? KeyBindings({
                'ctrl+o': _open,
                'ctrl+s': _save,
                'ctrl+z': _undo,
              }, child: child)
            : child,
      ),
    );
  }
}
