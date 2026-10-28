part of '../sample_app.dart';

extension on _SampleAppState {
  List<Widget> _layout() => [
    const Divider(type: BorderType.heavy),
    SizedBox(
      height: 4,
      child: Flex(
        direction: Axis.horizontal,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Flexible(fit: FlexFit.tight, child: Text('flexible')),
          const Expanded(
            child: Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                SizedBox.expand(),
                Positioned(left: 0, top: 0, child: Text('pinned')),
                Positioned.fill(left: 10, child: SizedBox.shrink()),
              ],
            ),
          ),
          SizedBox(
            width: 30,
            child: Grid(
              columns: const [
                GridTrack.fixed(5),
                GridTrack.fr(1),
                GridTrack.content(),
              ],
              rows: [
                for (final kind in GridTrackKind.values)
                  if (kind == GridTrackKind.fixed)
                    const GridTrack.fixed(1)
                  else
                    const GridTrack.content(),
              ],
              columnGap: 1,
              children: const [
                GridPlacement(columnSpan: 2, child: Text('grid')),
                GridPlacement(row: 1, column: 2, child: Text('cell')),
              ],
            ),
          ),
          const SizedBox(width: 12, child: _Split()),
          const SizedBox(width: 16, child: _Dock()),
          const SizedBox(
            width: 6,
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              gap: 1,
              runGap: 1,
              children: [Text('wrap'), Text('runs')],
            ),
          ),
          const Shadow(
            shadow: BoxShadow(dx: 1, color: Color.black, alpha: 0x60),
            child: Text('shadow'),
          ),
          const VerticalDivider(),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.all(1),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Text('aligned'),
              ),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(
      height: 3,
      child: Row(
        children: [
          Container(
            width: 14,
            constraints: BoxConstraints(0, 16, 0, 3),
            margin: EdgeInsets.only(right: 1),
            padding: EdgeInsets.x(1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(type: BorderType.rounded),
              titles: [BorderTitle('box')],
              gradient: Gradient([Color.blue, Color.cyan]),
            ),
            foregroundDecoration: BoxDecoration(
              titles: [BorderTitle('in', alignment: Alignment.bottomRight)],
            ),
            child: Text('container'),
          ),
          Container(height: 1, color: Color.blue, child: Text('color')),
          ColoredBox(color: Color.green, child: Text('colored')),
          DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              style: Style(fg: Color.yellow),
              border: Border.all(),
            ),
            child: Text('decorated over'),
          ),
          LimitedBox(maxWidth: 8, child: Text('limited box')),
          SizedBox(
            width: 5,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: 9,
              child: Text('overflows'),
            ),
          ),
          SizedOverflowBox(size: (4, 1), child: Text('sized over')),
          Transform.translate(offset: (1, 1), child: Text('moved')),
        ],
      ),
    ),
    RepaintBoundary(
      child: CustomPaint(
        painter: _Dots(_count),
        child: const Row(
          children: [
            Offstage(child: Text('offstage')),
            Visibility(
              visible: false,
              maintainState: true,
              maintainSize: true,
              child: Text('kept'),
            ),
            Visibility(child: Text('shown')),
          ],
        ),
      ),
    ),
    const Accordion(
      initiallyExpanded: 0,
      children: [
        ExpansionTile(
          title: Text('Security'),
          subtitle: Text('TLS'),
          trailing: Text('2'),
          child: Text('TLS Version: 1.3'),
        ),
        ExpansionTile(title: Text('Network'), child: Text('Proxy: none')),
      ],
    ),
  ];
}

/// A dot in each cell of the row, repainted as the count changes.
final class _Dots extends CellPainter {
  _Dots(this.count) : super(repaint: count);

  final ValueNotifier<int> count;

  @override
  void paint(Canvas canvas, int width, int height) {
    final pen = canvas.styles.pen(const Pen(fg: Color.cyan));
    for (var x = 0; x < width; x++) {
      canvas.text(x, 0, x == count.value % width ? '•' : '·', pen);
    }
  }

  @override
  bool shouldRepaint(_Dots oldDelegate) => !identical(oldDelegate.count, count);
}

/// Two boxed panes side by side, the second collapsible.
final class _Split extends StatefulWidget {
  const _Split();

  @override
  State<_Split> createState() => _SplitState();
}

final class _SplitState extends State<_Split> {
  final _split = SplitController(fractions: [1, 2]);

  @override
  void dispose() {
    _split.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SplitView(
    controller: _split,
    shareEdges: true,
    focusedStyle: const Style(fg: Color.cyan),
    panes: const [
      SplitPane(
        minSize: 3,
        child: Box(border: Border.all(merge: true)),
      ),
      SplitPane(
        maxSize: 8,
        collapsible: true,
        child: Box(border: Border.all(merge: true)),
      ),
    ],
  );
}

/// Panels docked in two groups side by side, the first of two tabs.
final class _Dock extends StatefulWidget {
  const _Dock();

  @override
  State<_Dock> createState() => _DockState();
}

final class _DockState extends State<_Dock> {
  final _dock = DockController(
    DockLayout(
      root: DockSplit(Axis.horizontal, [
        DockTabs(['files', 'find']),
        DockTabs(['log']),
      ]),
    ),
  );

  @override
  void dispose() {
    _dock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DockArea(
    controller: _dock,
    panels: const [
      DockPanel(id: 'files', title: 'Files', child: Text('files')),
      DockPanel(id: 'find', title: 'Find', child: Text('find')),
      DockPanel(id: 'log', title: 'Log', child: Text('log')),
    ],
  );
}
