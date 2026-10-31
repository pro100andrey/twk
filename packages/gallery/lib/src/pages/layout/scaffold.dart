// The Scaffold page.
part of 'layout.dart';

/// What the Scaffold page keeps while the gallery runs: the controller,
/// whose sidebar width and choice outlive a visit elsewhere, and the
/// checkboxes and the count.
final class _NotesState {
  final controller = ScaffoldController(sidebarWidth: 14);
  var inbox = true;
  var archive = false;
  var notes = 3;
}

final class _Notes extends StatefulWidget {
  const _Notes(this.o);

  final Options o;

  @override
  State<_Notes> createState() => _NotesPageState();
}

final class _NotesPageState extends State<_Notes> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = widget.o;
    final k = keptAt(context, 'notes', _NotesState.new);
    return SizedBox(
      width: o.number('width').toInt(),
      height: 12,
      child: Scaffold(
        controller: k.controller,
        collapsedBelow: o.choice('collapsed'),
        sidebarSide: o['side'] == 'right'
            ? SidebarSide.right
            : SidebarSide.left,
        resizableSidebar: o.flag('resizable'),
        keyHints: o.flag('hints'),
        header: o.flag('header') ? const Text('notes') : null,
        sidebar: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: k.inbox,
                label: 'inbox',
                onChanged: (v) => setState(() => k.inbox = v),
              ),
              Checkbox(
                value: k.archive,
                label: 'archive',
                onChanged: (v) => setState(() => k.archive = v),
              ),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            gap: 1,
            children: [
              Button('New note', onPressed: () => setState(() => k.notes++)),
              Text.rich([Span('notes: ', theme.muted), Span('${k.notes}')]),
            ],
          ),
        ),
        statusBar: o.flag('status')
            ? StatusBar(
                left: Text('${k.notes} notes'),
                right: const Text('saved'),
              )
            : null,
      ),
    );
  }
}

final _scaffold = GalleryPage(
  group: 'Layout',
  title: 'Scaffold',
  options: [
    SliderOption(
      'width',
      'width',
      min: 30,
      max: 48,
      initial: 48,
      format: (v) => '$v cells',
    ),
    const ChoiceOption('side', 'sidebar side', values: ['left', 'right']),
    const SwitchOption('resizable', 'resizable', initial: true),
    const SwitchOption('hints', 'key hints', initial: true),
    const SwitchOption('header', 'header', initial: true),
    const SwitchOption('status', 'status bar', initial: true),
    const ChoiceOption(
      'collapsed',
      'collapsed below',
      values: [null, 36, 40, 44],
      initial: 40,
    ),
  ],
  build: (context, o) => _Notes(o),
  code: (o) => [
    'final _controller = ScaffoldController(sidebarWidth: 14);',
    'var _inbox = true;',
    'var _archive = false;',
    'var _notes = 3;',
    '',
    '@override',
    'void dispose() {',
    '  _controller.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return SizedBox(',
    '    width: ${o.label('width')},',
    '    height: 12,',
    '    child: Scaffold(',
    '      controller: _controller,',
    if (o.choice<int?>('collapsed') case final w?) '      collapsedBelow: $w,',
    if (o['side'] == 'right') '      sidebarSide: .right,',
    if (o.flag('resizable')) '      resizableSidebar: true,',
    if (!o.flag('hints')) '      keyHints: false,',
    if (o.flag('header')) "      header: const Text('notes'),",
    '      sidebar: Padding(',
    '        padding: const .all(1),',
    '        child: Column(',
    '          crossAxisAlignment: .start,',
    '          children: [',
    '            Checkbox(',
    '              value: _inbox,',
    "              label: 'inbox',",
    '              onChanged: (v) => setState(() => _inbox = v),',
    '            ),',
    '            Checkbox(',
    '              value: _archive,',
    "              label: 'archive',",
    '              onChanged: (v) => setState(() => _archive = v),',
    '            ),',
    '          ],',
    '        ),',
    '      ),',
    '      body: Padding(',
    '        padding: const .all(1),',
    '        child: Column(',
    '          crossAxisAlignment: .start,',
    '          gap: 1,',
    '          children: [',
    codeLine([
      "            Button('New note', ",
      'onPressed: () => setState(() => _notes++)),',
    ]),
    r"            Text.rich([Span('notes: ', theme.muted), Span('$_notes')]),",
    '          ],',
    '        ),',
    '      ),',
    if (o.flag('status')) ...[
      '      statusBar: StatusBar(',
      r"        left: Text('$_notes notes'),",
      "        right: const Text('saved'),",
      '      ),',
    ],
    '    ),',
    '  );',
    '}',
  ].join('\n'),
);
