// The Slot, SlotScope page.
part of 'framework.dart';

/// The status bar's box.
const _sw = 44;

/// A status bar item: its name muted, then its value.
Widget _item(BuildContext context, String name, String value) =>
    Text.rich([Span('$name ', Theme.of(context).muted), Span(value)]);

/// What the plugins put in the slots named 'status', in order, the lint's
/// at [lint].
List<SlotEntry> _plugins(int lint) => [
  SlotEntry(
    slot: 'status',
    id: 'git',
    builder: (context) => _item(context, 'git', 'main'),
  ),
  SlotEntry(
    slot: 'status',
    id: 'lint',
    order: lint,
    builder: (context) => _item(context, 'lint', '0 problems'),
  ),
  SlotEntry(
    slot: 'status',
    id: 'words',
    order: 2,
    builder: (context) => _item(context, 'words', '120'),
  ),
];

final _slots = GalleryPage(
  group: 'Framework',
  title: 'Slot, SlotScope',
  options: const [
    ChoiceOption(
      'lint',
      'lint order',
      values: [-1, 1, 3],
      initial: 1,
      labels: ['-1, first', '1, between', '3, last'],
    ),
    SwitchOption('placeholder', 'placeholder', initial: true),
  ],
  build: (context, o) =>
      _Plugins(lint: o.choice('lint'), placeholder: o.flag('placeholder')),
  code: (o) => [
    '/// A status bar item: its name muted, then its value.',
    codeLine([
      'static Widget _item(BuildContext context, String name, ',
      'String value) =>',
    ]),
    r"    Text.rich([Span('$name ', Theme.of(context).muted), Span(value)]);",
    '',
    "/// What the plugins put in the slots named 'status', in order.",
    'static final _plugins = [',
    '  SlotEntry(',
    "    slot: 'status',",
    "    id: 'git',",
    "    builder: (context) => _item(context, 'git', 'main'),",
    '  ),',
    '  SlotEntry(',
    "    slot: 'status',",
    "    id: 'lint',",
    '    order: ${o.choice<int>('lint')},',
    "    builder: (context) => _item(context, 'lint', '0 problems'),",
    '  ),',
    '  SlotEntry(',
    "    slot: 'status',",
    "    id: 'words',",
    '    order: 2,',
    "    builder: (context) => _item(context, 'words', '120'),",
    '  ),',
    '];',
    '',
    'final _registry = SlotRegistry()',
    '  ..register(_plugins[0])',
    '  ..register(_plugins[2]);',
    '',
    'void _turn(SlotEntry plugin, {required bool on}) => setState(() {',
    '  if (on) {',
    '    _registry.register(plugin);',
    '  } else {',
    '    _registry.unregister(plugin.slot, plugin.id);',
    '  }',
    '});',
    '',
    '@override',
    'void dispose() {',
    '  _registry.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  // an InheritedWidget: the Slots below find the registry through it',
    '  return SlotScope(',
    '    registry: _registry,',
    '    child: Column(',
    '      mainAxisSize: .min,',
    '      crossAxisAlignment: .start,',
    '      gap: 1,',
    '      children: [',
    '        Row(',
    '          mainAxisSize: .min,',
    '          gap: 2,',
    '          children: [',
    '            for (final plugin in _plugins)',
    '              Checkbox(',
    "                value: _registry.entriesOf('status').contains(plugin),",
    '                onChanged: (on) => _turn(plugin, on: on),',
    '                label: plugin.id,',
    '              ),',
    '          ],',
    '        ),',
    '        SizedBox(',
    '          width: $_sw,',
    '          child: Box(',
    '            border: .all(type: .rounded, style: theme.border),',
    "            titles: const [BorderTitle(' status ')],",
    '            padding: const .x(1),',
    codeLine([
      "            // built again when the entries of 'status' change, ",
      'and then only',
    ]),
    '            child: Slot(',
    "              'status',",
    codeLine([
      '              layout: (context, children) => ',
      'Row(gap: 2, children: children),',
    ]),
    if (o.flag('placeholder'))
      codeLine([
        '              placeholder: ',
        "Text('no plugins', style: theme.muted),",
      ]),
    '            ),',
    '          ),',
    '        ),',
    '      ],',
    '    ),',
    '  );',
    '}',
  ].join('\n'),
);

/// The Code's registry and its Slot: a Checkbox for each plugin, which
/// registers its entry or unregisters it, the lint's at order [lint].
final class _Plugins extends StatefulWidget {
  const _Plugins({required this.lint, required this.placeholder});

  final int lint;
  final bool placeholder;

  @override
  State<_Plugins> createState() => _PluginsState();
}

final class _PluginsState extends State<_Plugins> with KeptState {
  /// The ids registered, in the order they were.
  late final _on =
      (kept['registered'] ??= <String>['git', 'words']) as List<String>;
  late List<SlotEntry> _entries = _plugins(widget.lint);
  final _registry = SlotRegistry();

  var _registered = false;

  @override
  void didUpdateWidget(_Plugins oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lint != widget.lint) {
      _entries = _plugins(widget.lint);
      if (_on.contains('lint')) {
        // a new order: registered again, as the Code's would be built
        _registry
          ..unregister('status', 'lint')
          ..register(_entries[1]);
      }
    }
  }

  @override
  void dispose() {
    _registry.dispose();
    super.dispose();
  }

  void _turn(SlotEntry plugin, {required bool on}) => setState(() {
    if (on) {
      _registry.register(plugin);
      _on.add(plugin.id);
    } else {
      _registry.unregister(plugin.slot, plugin.id);
      _on.remove(plugin.id);
    }
  });

  @override
  Widget build(BuildContext context) {
    if (!_registered) {
      // the page's kept plugins, once its state can be read
      _registered = true;
      for (final id in _on) {
        _registry.register(_entries.firstWhere((e) => e.id == id));
      }
    }
    final theme = Theme.of(context);
    return SlotScope(
      registry: _registry,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            gap: 2,
            children: [
              for (final plugin in _entries)
                Checkbox(
                  value: _on.contains(plugin.id),
                  onChanged: (on) => _turn(plugin, on: on),
                  label: plugin.id,
                ),
            ],
          ),
          SizedBox(
            width: _sw,
            child: Box(
              border: Border.all(type: BorderType.rounded, style: theme.border),
              titles: const [BorderTitle(' status ')],
              padding: const EdgeInsets.x(1),
              child: Slot(
                'status',
                layout: (context, children) => Row(gap: 2, children: children),
                placeholder: widget.placeholder
                    ? Text('no plugins', style: theme.muted)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
