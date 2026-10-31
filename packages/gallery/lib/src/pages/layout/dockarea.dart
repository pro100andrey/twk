// The DockArea page.
part of 'layout.dart';

// ------------------------------------------------------------ DockArea

const _daw = 50;

const _dah = 10;

DockLayout _docked() => DockLayout(
  root: DockSplit(
    Axis.horizontal,
    [
      DockTabs(['files', 'find']),
      DockTabs(['editor']),
    ],
    fractions: [1, 2],
  ),
  windows: const [DockWindow('log', left: 23, top: 4, width: 26, height: 6)],
);

final _dockArea = GalleryPage(
  group: 'Layout',
  title: 'DockArea',
  options: const [
    SwitchOption('strip', 'tab strip', initial: true),
    ChoiceOption(
      'frame',
      'window frame',
      values: [null, 'raised', 'bordered'],
      labels: ['by the theme', 'raised', 'bordered'],
    ),
  ],
  build: (context, o) => _Dock(
    tabStrip: o.flag('strip'),
    windowFrame: switch (o.choice<String?>('frame')) {
      final frame? => WindowFrame.values.byName(frame),
      null => null,
    },
  ),
  code: (o) => [
    _dockHead,
    if (!o.flag('strip')) '        tabStrip: false,',
    if (o.choice<String?>('frame') case final frame?)
      '        windowFrame: .$frame,',
    _dockTail,
  ].join('\n'),
);

/// The DockArea page's widget: its controller kept in the page's state,
/// so that the panels stay where they were put over a visit to another
/// page.
final class _Dock extends StatelessWidget {
  const _Dock({required this.tabStrip, required this.windowFrame});

  final bool tabStrip;
  final WindowFrame? windowFrame;

  @override
  Widget build(BuildContext context) {
    final dock = keptAt(context, 'dock', () => DockController(_docked()));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SizedBox(
          width: _daw,
          height: _dah,
          child: DockArea(
            controller: dock,
            tabStrip: tabStrip,
            windowFrame: windowFrame,
            panels: const [
              DockPanel(
                id: 'files',
                title: 'Files',
                child: Padding(
                  padding: EdgeInsets.x(1),
                  child: Text('Drag a tab onto a target to dock it there.'),
                ),
              ),
              DockPanel(
                id: 'find',
                title: 'Find',
                child: Padding(
                  padding: EdgeInsets.x(1),
                  child: Text('Find in files.'),
                ),
              ),
              DockPanel(
                id: 'editor',
                title: 'Editor',
                child: Padding(padding: EdgeInsets.x(1), child: _Clicks()),
              ),
              DockPanel(
                id: 'log',
                title: 'Log',
                child: Padding(
                  padding: EdgeInsets.x(1),
                  child: Text('Drop a tab off the targets to float it.'),
                ),
              ),
            ],
          ),
        ),
        Button(
          'Dock them as they were',
          onPressed: () => dock.layout = _docked(),
        ),
      ],
    );
  }
}

/// A count and a button that adds to it: kept as its panel moves, and in
/// the page's state over a visit to another page.
final class _Clicks extends StatefulWidget {
  const _Clicks();

  @override
  State<_Clicks> createState() => _ClicksState();
}

final class _ClicksState extends State<_Clicks> with KeptState {
  int get _count => kept['count'] as int? ?? 0;
  set _count(int n) => kept['count'] = n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich([Span('count: ', theme.muted), Span('$_count')]),
        Button('Add one', onPressed: () => setState(() => _count++)),
      ],
    );
  }
}

const _dockHead = '''
final _dock = DockController(_docked());

static DockLayout _docked() => DockLayout(
  root: DockSplit(
    .horizontal,
    [
      DockTabs(['files', 'find']),
      DockTabs(['editor']),
    ],
    fractions: [1, 2],
  ),
  windows: const [DockWindow('log', left: 23, top: 4, width: 26, height: 6)],
);

@override
void dispose() {
  _dock.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  gap: 1,
  children: [
    SizedBox(
      width: 50,
      height: 10,
      child: DockArea(
        controller: _dock,''';

const _dockTail = r'''
        panels: const [
          DockPanel(
            id: 'files',
            title: 'Files',
            child: Padding(
              padding: .x(1),
              child: Text('Drag a tab onto a target to dock it there.'),
            ),
          ),
          DockPanel(
            id: 'find',
            title: 'Find',
            child: Padding(padding: .x(1), child: Text('Find in files.')),
          ),
          DockPanel(
            id: 'editor',
            title: 'Editor',
            child: Padding(padding: .x(1), child: _Clicks()),
          ),
          DockPanel(
            id: 'log',
            title: 'Log',
            child: Padding(
              padding: .x(1),
              child: Text('Drop a tab off the targets to float it.'),
            ),
          ),
        ],
      ),
    ),
    Button(
      'Dock them as they were',
      onPressed: () => _dock.layout = _docked(),
    ),
  ],
);

/// A count and a button that adds to it: kept as its panel moves.
final class _Clicks extends StatefulWidget {
  const _Clicks();

  @override
  State<_Clicks> createState() => _ClicksState();
}

final class _ClicksState extends State<_Clicks> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text.rich([Span('count: ', theme.muted), Span('$_count')]),
        Button('Add one', onPressed: () => setState(() => _count++)),
      ],
    );
  }
}''';
