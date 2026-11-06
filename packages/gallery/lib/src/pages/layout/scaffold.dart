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
      width: o(_scaffoldWidth).toInt(),
      height: 12,
      child: Scaffold(
        controller: k.controller,
        collapsedBelow: o(_scaffoldCollapsed),
        sidebarSide: o(_scaffoldSide) == 'right'
            ? SidebarSide.right
            : SidebarSide.left,
        resizableSidebar: o(_scaffoldResizable),
        keyHints: o(_scaffoldHints),
        header: o(_scaffoldHeader) ? const Text('notes') : null,
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
            spacing: 1,
            children: [
              Button('New note', onPressed: () => setState(() => k.notes++)),
              Text.rich([Span('notes: ', theme.muted), Span('${k.notes}')]),
            ],
          ),
        ),
        statusBar: o(_scaffoldStatus)
            ? StatusBar(
                left: Text('${k.notes} notes'),
                right: const Text('saved'),
              )
            : null,
      ),
    );
  }
}

/// The Scaffold page's `width` option.
final _scaffoldWidth = SliderOption(
  'width',
  'width',
  min: 30,
  max: 48,
  initial: 48,
  format: (v) => '$v cells',
);

/// The Scaffold page's `side` option.
const _scaffoldSide = ChoiceOption<String>(
  'side',
  'sidebar side',
  values: ['left', 'right'],
);

/// The Scaffold page's `resizable` option.
const _scaffoldResizable = SwitchOption(
  'resizable',
  'resizable',
  initial: true,
);

/// The Scaffold page's `hints` option.
const _scaffoldHints = SwitchOption(
  'hints',
  'key hints',
  initial: true,
);

/// The Scaffold page's `header` option.
const _scaffoldHeader = SwitchOption(
  'header',
  'header',
  initial: true,
);

/// The Scaffold page's `status` option.
const _scaffoldStatus = SwitchOption(
  'status',
  'status bar',
  initial: true,
);

/// The Scaffold page's `collapsed` option.
const _scaffoldCollapsed = ChoiceOption<int?>(
  'collapsed',
  'collapsed below',
  values: [null, 36, 40, 44],
  initial: 40,
);

final _scaffold = GalleryPage(
  group: _group,
  title: 'Scaffold',
  options: [
    _scaffoldWidth,
    _scaffoldSide,
    _scaffoldResizable,
    _scaffoldHints,
    _scaffoldHeader,
    _scaffoldStatus,
    _scaffoldCollapsed,
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
    '    width: ${o.nameOf(_scaffoldWidth)},',
    '    height: 12,',
    '    child: Scaffold(',
    '      controller: _controller,',
    if (o(_scaffoldCollapsed) case final w?) '      collapsedBelow: $w,',
    if (o(_scaffoldSide) == 'right') '      sidebarSide: .right,',
    if (o(_scaffoldResizable)) '      resizableSidebar: true,',
    if (!o(_scaffoldHints)) '      keyHints: false,',
    if (o(_scaffoldHeader)) "      header: const Text('notes'),",
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
    '          spacing: 1,',
    '          children: [',
    codeLine([
      "            Button('New note', ",
      'onPressed: () => setState(() => _notes++)),',
    ]),
    r"            Text.rich([Span('notes: ', theme.muted), Span('$_notes')]),",
    '          ],',
    '        ),',
    '      ),',
    if (o(_scaffoldStatus)) ...[
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
