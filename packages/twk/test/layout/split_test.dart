// Split panes: the panes' shares of the room, kept across resizes, within
// their least and most; a divider dragged by the mouse and moved by the
// keys while it has the focus, collapsing and expanding panes; nested
// splits, and dividers joined with the borders of boxes that share their
// edges; the controller's sizes and shares, saved and restored.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../gestures/shape_run.dart';

import 'view.dart' show Fill;

/// [child] in a repaint boundary as big as it.
final class Boundary extends SingleChildRenderObjectWidget {
  const Boundary({super.child});

  @override
  SingleChildRenderObjectElement createElement() => _BoundaryElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBoundary();
}

final class _BoundaryElement extends SingleChildRenderObjectElement {
  _BoundaryElement(super.widget);

  @override
  _RenderBoundary get renderObject => super.renderObject as _RenderBoundary;

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) =>
      renderObject.child = child;

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) => throw UnsupportedError('one child does not move');

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) =>
      renderObject.child = null;
}

final class _RenderBoundary extends RenderObject
    with RenderObjectWithChildMixin {
  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    child!.layout(c, parentUsesSize: true);
    width = child!.width;
    height = child!.height;
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);
}

/// [char] filling a pane.
SplitPane pane(
  String char, {
  int minSize = 1,
  int? maxSize,
  bool collapsible = false,
}) => SplitPane(
  child: Fill(char),
  minSize: minSize,
  maxSize: maxSize,
  collapsible: collapsible,
);

/// A [Focus] named [label], a row of it.
Widget field(String label) => Focus(debugLabel: label, child: Text(label));

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// Presses the left button at ([x], [y]), drags to each of [to] and
/// releases it at the last, pumping a frame after each.
Future<void> drag(TwkTester t, int x, int y, List<(int, int)> to) async {
  await t.mouse(MouseKind.down, x, y);
  await t.pump();
  for (final (dx, dy) in to) {
    await t.mouse(MouseKind.drag, dx, dy);
    await t.pump();
  }
  final (ux, uy) = to.isEmpty ? (x, y) : to.last;
  await t.mouse(MouseKind.up, ux, uy);
  await t.pump();
}

/// Presses each key of [keys], pumping a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

/// The shares rounded to two places, to compare.
List<double> rounded(List<double> shares) => [
  for (final s in shares) (s * 100).round() / 100,
];

void main() {
  group('SplitView', () {
    testTwk('shares the room equally by default, a line between each two '
        'panes, side by side or one below another', (t) async {
      final c = SplitController();
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            controller: c,
            panes: [pane('a'), pane('b'), pane('c')],
          ),
        ),
        size: (11, 2),
      );
      expect(t.lines, ['aaa│bbb│ccc', 'aaa│bbb│ccc']);
      expect(c.sizes, [3, 3, 3]);
      expect(rounded(c.fractions), [0.33, 0.33, 0.33]);
      await t.resize(11, 3);
      final key = GlobalKey();
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            key: key,
            controller: c,
            direction: Axis.vertical,
            type: BorderType.double,
            panes: [pane('a'), pane('b')],
          ),
        ),
      );
      expect(t.lines, ['aaaaaaaaaaa', '═══════════', 'bbbbbbbbbbb']);
      expect(c.sizes, [1, 1]);
      expect(c.fractions, [0.5, 0.5]);
      expect(
        '${key.currentContext!.findRenderObject()!.describe()}',
        contains('‹direction: vertical, own: [1, 1],'),
      );
    });

    testTwk('keeps the shares of its panes across resizes', (t) async {
      final c = SplitController(fractions: [1, 3]);
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(controller: c, panes: [pane('a'), pane('b')]),
        ),
        size: (21, 1),
      );
      expect(t.lines, ['aaaaa│bbbbbbbbbbbbbbb']);
      expect(c.fractions, [0.25, 0.75]);
      await t.resize(41, 1);
      await t.pump();
      expect(c.sizes, [10, 30]);
      await t.resize(9, 1);
      await t.pump();
      expect(t.lines, ['aa│bbbbbb']);
      // a share left after a drag too
      await drag(t, 2, 0, [(4, 0)]);
      expect(t.lines, ['aaaa│bbbb']);
      await t.resize(19, 1);
      await t.pump();
      expect(t.lines, ['aaaaaaaaa│bbbbbbbbb']);
    });

    testTwk('a divider dragged with the left button follows the mouse, in '
        'the focused style while dragged; a press elsewhere drags nothing', (
      t,
    ) async {
      final c = SplitController();
      var told = 0;
      c.addListener(() => told++);
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(controller: c, panes: [pane('a'), pane('b')]),
        ),
        size: (21, 2),
      );
      expect(t.lines.first, 'aaaaaaaaaa│bbbbbbbbbb');
      expect(t, styleAt(10, 0, isNot(hasFg(Color.blue))));
      await t.mouse(MouseKind.down, 10, 1);
      await t.pump();
      expect(t, styleAt(10, 0, hasFg(Color.blue)));
      await t.mouse(MouseKind.drag, 13, 0);
      await t.pump();
      await t.mouse(MouseKind.drag, 14, 1);
      await t.pump();
      expect(t.lines.first, 'aaaaaaaaaaaaaa│bbbbbb');
      expect(c.sizes, [14, 6]);
      expect(rounded(c.fractions), [0.7, 0.3]);
      expect(told, 2);
      await t.mouse(MouseKind.up, 14, 1);
      await t.pump();
      expect(t, styleAt(14, 0, isNot(hasFg(Color.blue))));
      // in a pane, and with the right button
      await drag(t, 3, 0, [(8, 0)]);
      await t.mouse(MouseKind.down, 14, 0, button: 2);
      await t.mouse(MouseKind.drag, 16, 0, button: 2);
      await t.mouse(MouseKind.up, 16, 0, button: 2);
      await t.pump();
      expect(t.lines.first, 'aaaaaaaaaaaaaa│bbbbbb');
      expect(told, 2);
    });

    testTwk('a pane gets no fewer cells than its least and no more than its '
        'most; the cells all panes leave stay empty, and a short room is '
        'shared by their least', (t) async {
      final c = SplitController();
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            controller: c,
            panes: [pane('a', minSize: 6), pane('b', minSize: 4)],
          ),
        ),
        size: (21, 1),
      );
      await drag(t, 10, 0, [(2, 0)]);
      expect(t.lines, ['aaaaaa│bbbbbbbbbbbbbb']);
      await drag(t, 6, 0, [(20, 0)]);
      expect(t.lines, ['aaaaaaaaaaaaaaaa│bbbb']);
      c.fractions = [1, 9];
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            controller: c,
            panes: [pane('a', minSize: 6), pane('b', minSize: 4, maxSize: 12)],
          ),
        ),
      );
      expect(t.lines, ['aaaaaaaa│bbbbbbbbbbbb']);
      // the most of the pane after it stops the divider too
      await drag(t, 8, 0, [(2, 0)]);
      expect(t.lines, ['aaaaaaaa│bbbbbbbbbbbb']);
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            controller: c,
            panes: [pane('a', maxSize: 5), pane('b', maxSize: 5)],
          ),
        ),
      );
      expect(t.lines, ['aaaaa│bbbbb']);
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            controller: c,
            panes: [pane('a', minSize: 30), pane('b', minSize: 10)],
          ),
        ),
      );
      expect(t.lines, ['aaaaaaaaaaaaaaa│bbbbb']);
    });

    testTwk('Tab focuses a divider: the arrows move it a cell, Home and End '
        'as far as it goes, hinted', (t) async {
      final c = SplitController();
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            children: [
              Expanded(
                child: SplitView(controller: c, panes: [pane('a'), pane('b')]),
              ),
              Expanded(
                child: SplitView(
                  direction: Axis.vertical,
                  panes: [pane('c'), pane('d')],
                ),
              ),
            ],
          ),
        ),
        size: (11, 10),
      );
      expect(t.lines.first, 'aaaaa│bbbbb');
      await press(t, 'right');
      expect(t.lines.first, 'aaaaa│bbbbb');
      await press(t, 'tab');
      expect(t, styleAt(5, 0, hasFg(Color.blue)));
      expect(
        [for (final k in t.binding.focusManager.activeKeys) '$k'],
        ['left divider left', 'right divider right', 'home', 'end'],
      );
      await press(t, 'right right');
      expect(t.lines.first, 'aaaaaaa│bbb');
      await press(t, 'left');
      expect(t.lines.first, 'aaaaaa│bbbb');
      await press(t, 'home');
      expect(t.lines.first, 'a│bbbbbbbbb');
      await press(t, 'end');
      expect(t.lines.first, 'aaaaaaaaa│b');
      expect(c.sizes, [9, 1]);
      await press(t, 'tab');
      expect(t, styleAt(9, 0, isNot(hasFg(Color.blue))));
      expect(
        [for (final k in t.binding.focusManager.activeKeys) '$k'],
        ['up divider up', 'down divider down', 'home', 'end'],
      );
      await press(t, 'down');
      expect(t.lines.sublist(5), [
        'ccccccccccc',
        'ccccccccccc',
        'ccccccccccc',
        '───────────',
        'ddddddddddd',
      ]);
      await press(t, 'home');
      expect(t.lines.sublist(5), [
        'ccccccccccc',
        '───────────',
        'ddddddddddd',
        'ddddddddddd',
        'ddddddddddd',
      ]);
    });

    testTwk('a divider takes the arrows from the moment it has the focus: '
        'those typed right after the Tab that focuses it, in one read', (
      t,
    ) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            children: [
              Expanded(child: SplitView(panes: [pane('a'), pane('b')])),
              Expanded(
                child: SplitView(
                  direction: Axis.vertical,
                  panes: [pane('c'), pane('d')],
                ),
              ),
            ],
          ),
        ),
        size: (11, 10),
      );
      await t.type('\t\x1b[C\t\x1b[B');
      await t.pump();
      expect(t.lines, [
        for (var i = 0; i < 5; i++) 'aaaaaa│bbbb',
        'ccccccccccc',
        'ccccccccccc',
        'ccccccccccc',
        '───────────',
        'ddddddddddd',
      ]);
    });

    testTwk('each key of those in one read moves a divider: two arrows two '
        'cells, five arrows five, Home and an arrow from as far as it goes, '
        'collapsing a pane on the way', (t) async {
      final c = SplitController();
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            children: [
              SizedBox(
                height: 1,
                child: SplitView(
                  controller: c,
                  panes: [pane('a', minSize: 6, collapsible: true), pane('b')],
                ),
              ),
              Expanded(
                child: SplitView(
                  direction: Axis.vertical,
                  panes: [pane('c'), pane('d')],
                ),
              ),
            ],
          ),
        ),
        size: (21, 12),
      );
      await press(t, 'tab');
      await t.type('\x1b[C\x1b[C');
      await t.pump();
      expect(t.lines.first, 'aaaaaaaaaaaa│bbbbbbbb');
      expect(c.sizes, [12, 8]);
      await t.type('\x1b[D' * 5);
      await t.pump();
      expect(t.lines.first, 'aaaaaaa│bbbbbbbbbbbbb');
      await t.type('\x1b[D\x1b[D');
      await t.pump();
      expect(t.lines.first, '│bbbbbbbbbbbbbbbbbbbb');
      expect(c.collapsed, {0});
      await t.type('\x1b[F\x1b[D\x1b[H\x1b[C');
      await t.pump();
      expect(t.lines.first, 'aaaaaa│bbbbbbbbbbbbbb');
      expect(c.collapsed, isEmpty);
      // one below another
      await press(t, 'tab');
      await t.type('\x1b[B\x1b[B\x1b[B');
      await t.pump();
      expect(t.lines.sublist(1), [
        for (var i = 0; i < 8; i++) 'c' * 21,
        '─' * 21,
        for (var i = 0; i < 2; i++) 'd' * 21,
      ]);
    });

    testTwk('a divider dragged over a collapsible pane past half its least '
        'collapses it, and back out expands it; the pane keeps its share', (
      t,
    ) async {
      final c = SplitController();
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            controller: c,
            panes: [pane('a', minSize: 6, collapsible: true), pane('b')],
          ),
        ),
        size: (21, 1),
      );
      await t.mouse(MouseKind.down, 10, 0);
      await t.mouse(MouseKind.drag, 3, 0);
      await t.pump();
      expect(t.lines, ['aaaaaa│bbbbbbbbbbbbbb']);
      await t.mouse(MouseKind.drag, 2, 0);
      await t.pump();
      expect(t.lines, ['│bbbbbbbbbbbbbbbbbbbb']);
      expect(c.collapsed, {0});
      expect(c.sizes, [0, 20]);
      expect(c.fractions, [0.5, 0.5]);
      await t.mouse(MouseKind.drag, 4, 0);
      await t.pump();
      expect(t.lines, ['aaaaaa│bbbbbbbbbbbbbb']);
      expect(c.collapsed, isEmpty);
      await t.mouse(MouseKind.drag, 0, 0);
      await t.mouse(MouseKind.up, 0, 0);
      await t.pump();
      expect(t.lines, ['│bbbbbbbbbbbbbbbbbbbb']);
      c.expand(0);
      await t.pump();
      expect(t.lines, ['aaaaaaaaaa│bbbbbbbbbb']);
    });

    testTwk('the keys collapse a collapsible pane moving past its least, and '
        'expand it moving into it; the controller collapses any pane', (
      t,
    ) async {
      final c = SplitController(fractions: [3, 7]);
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            controller: c,
            panes: [pane('a', minSize: 6, collapsible: true), pane('b')],
          ),
        ),
        size: (21, 1),
      );
      await press(t, 'tab left');
      expect(t.lines, ['│bbbbbbbbbbbbbbbbbbbb']);
      expect(c.isCollapsed(0), isTrue);
      expect(rounded(c.fractions), [0.3, 0.7]);
      await press(t, 'left');
      expect(t.lines, ['│bbbbbbbbbbbbbbbbbbbb']);
      await press(t, 'right');
      expect(t.lines, ['aaaaaa│bbbbbbbbbbbbbb']);
      await press(t, 'home');
      expect(t.lines, ['│bbbbbbbbbbbbbbbbbbbb']);
      c
        ..expand(0)
        ..collapse(1);
      await t.pump();
      expect(t.lines, ['aaaaaaaaaaaaaaaaaaaa│']);
      expect(c.sizes, [20, 0]);
      // not collapsible: the keys stop at its least
      await press(t, 'end left right');
      expect(t.lines, ['aaaaaaaaaaaaaaaaaaa│b']);
      expect(c.collapsed, isEmpty);
    });

    testTwk('the focus leaves a collapsed pane, and Tab passes it by', (
      t,
    ) async {
      final c = SplitController();
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            controller: c,
            panes: [
              SplitPane(child: field('left')),
              SplitPane(child: field('right')),
            ],
          ),
        ),
        size: (21, 1),
      );
      final order = <String?>[];
      for (var i = 0; i < 3; i++) {
        await press(t, 'tab');
        order.add(focused(t));
      }
      expect(order, ['left', null, 'right']);
      await press(t, 'tab');
      expect(focused(t), 'left');
      c.collapse(0);
      await t.pump();
      // the next stop after the pane, the divider, which has no label
      expect(t.binding.focusManager.primaryFocus, isNotNull);
      expect(focused(t), isNull);
      order.clear();
      for (var i = 0; i < 3; i++) {
        await press(t, 'tab');
        order.add(focused(t));
      }
      expect(order, ['right', null, 'right']);
      expect(order, isNot(contains('left')));
    });

    testTwk('splits nest: each divider drags its own panes, the panes '
        'inside keeping their shares', (t) async {
      final inner = SplitController();
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            panes: [
              pane('a'),
              SplitPane(
                child: SplitView(
                  controller: inner,
                  direction: Axis.vertical,
                  panes: [pane('b'), pane('c')],
                ),
              ),
            ],
          ),
        ),
        size: (21, 7),
      );
      expect(t.lines, [
        'aaaaaaaaaa│bbbbbbbbbb',
        'aaaaaaaaaa│bbbbbbbbbb',
        'aaaaaaaaaa│bbbbbbbbbb',
        'aaaaaaaaaa├──────────',
        'aaaaaaaaaa│cccccccccc',
        'aaaaaaaaaa│cccccccccc',
        'aaaaaaaaaa│cccccccccc',
      ]);
      await drag(t, 15, 3, [(15, 1)]);
      expect(inner.sizes, [1, 5]);
      await drag(t, 10, 5, [(5, 5)]);
      expect(t.lines, [
        'aaaaa│bbbbbbbbbbbbbbb',
        'aaaaa├───────────────',
        'aaaaa│ccccccccccccccc',
        'aaaaa│ccccccccccccccc',
        'aaaaa│ccccccccccccccc',
        'aaaaa│ccccccccccccccc',
        'aaaaa│ccccccccccccccc',
      ]);
      await t.resize(21, 13);
      await t.pump();
      expect(inner.sizes, [2, 10]);
    });

    testTwk('a divider joins the dividers of a split view filling a pane '
        'beside it where they meet it', (t) async {
      SplitPane column(String a, String b) => SplitPane(
        child: SplitView(direction: Axis.vertical, panes: [pane(a), pane(b)]),
      );
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(panes: [column('a', 'b'), column('c', 'd')]),
        ),
        size: (9, 5),
      );
      expect(t.lines, [
        'aaaa│cccc',
        'aaaa│cccc',
        '────┼────',
        'bbbb│dddd',
        'bbbb│dddd',
      ]);
      await drag(t, 6, 2, [(6, 3)]);
      expect(t.lines, [
        'aaaa│cccc',
        'aaaa│cccc',
        '────┤cccc',
        'bbbb├────',
        'bbbb│dddd',
      ]);
      // one in a repaint boundary, which may repaint alone, is not joined
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            panes: [
              column('a', 'b'),
              SplitPane(
                child: Boundary(
                  child: SplitView(
                    direction: Axis.vertical,
                    panes: [pane('c'), pane('d')],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      expect(t.lines[2], '────┤────');
      // one inside a box does not reach it
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            panes: [
              column('a', 'b'),
              SplitPane(
                child: Box(
                  padding: const EdgeInsets.only(left: 1),
                  child: SplitView(
                    direction: Axis.vertical,
                    panes: [pane('c'), pane('d')],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      expect(t.lines[2], '────┤ ───');
    });

    testTwk("with shareEdges the panes share the dividers' cells, so that "
        'boxes with merged borders share their edges, joined where they '
        'meet; the outer divider is dragged at a joint', (t) async {
      const box = Box(border: Border.all(merge: true));
      final outer = SplitController();
      final key = GlobalKey();
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            key: key,
            controller: outer,
            shareEdges: true,
            panes: const [
              SplitPane(child: box),
              SplitPane(
                child: SplitView(
                  direction: Axis.vertical,
                  shareEdges: true,
                  panes: [
                    SplitPane(child: box),
                    SplitPane(child: box),
                  ],
                ),
              ),
            ],
          ),
        ),
        size: (11, 7),
      );
      expect(t.lines, [
        '┌────┬────┐',
        '│    │    │',
        '│    │    │',
        '│    ├────┤',
        '│    │    │',
        '│    │    │',
        '└────┴────┘',
      ]);
      expect(outer.sizes, [6, 6]);
      expect(
        '${key.currentContext!.findRenderObject()!.describe()}',
        contains('‹own: [5, 5], shared edges,'),
      );
      await drag(t, 5, 3, [(7, 3)]);
      expect(t.lines, [
        '┌──────┬──┐',
        '│      │  │',
        '│      │  │',
        '│      ├──┤',
        '│      │  │',
        '│      │  │',
        '└──────┴──┘',
      ]);
      expect(outer.sizes, [8, 4]);
    });

    testTwk('with shareEdges a divider over the edge of a box keeps its '
        'titles', (t) async {
      Box titled(String title) => Box(
        border: const Border.all(merge: true),
        titles: [BorderTitle(title)],
      );
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            direction: Axis.vertical,
            shareEdges: true,
            panes: [
              SplitPane(child: titled('a')),
              SplitPane(child: titled('b')),
            ],
          ),
        ),
        size: (7, 6),
      );
      expect(t.lines, [
        '┌a────┐',
        '│     │',
        '│     │',
        '├b────┤',
        '│     │',
        '└─────┘',
      ]);
    });

    testTwk('along an axis with no bound it is as long as its panes want, '
        'across one as long as the longest', (t) async {
      await t.pumpWidget(
        const Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 6,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SplitView(
                        direction: Axis.vertical,
                        panes: [
                          SplitPane(child: Text('ab')),
                          SplitPane(child: Text('c\nd')),
                        ],
                      ),
                      Row(
                        children: [
                          SplitView(
                            panes: [
                              SplitPane(child: Text('ab')),
                              SplitPane(child: Text('cde\nf')),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 1,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SplitView(
                    panes: [
                      SplitPane(child: Text('ab')),
                      SplitPane(child: Text('cde')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        size: (8, 7),
      );
      expect(t.lines, [
        'ab',
        '────────',
        'c',
        'd',
        'ab  │cde',
        '    │f',
        'ab│cde',
      ]);
    });

    testTwk('the controller restores the shares and the collapsed panes, '
        'and refuses those of no pane', (t) async {
      final c = SplitController(collapsed: {2});
      await t.pumpWidget(
        Theme.terminal(
          child: SplitView(
            controller: c,
            panes: [pane('a'), pane('b'), pane('c')],
          ),
        ),
        size: (12, 1),
      );
      expect(t.lines, ['aaaaa│bbbbb│']);
      c
        ..fractions = [1, 3, 4]
        ..collapsed = {};
      await t.pump();
      expect(t.lines, ['a│bbbb│ccccc']);
      expect(c.fractions, [0.125, 0.375, 0.5]);
      expect(() => c.fractions = [1, 1], throwsArgumentError);
      expect(() => c.fractions = [0, 0, 0], throwsArgumentError);
      expect(() => c.fractions = [1, -1, 2], throwsArgumentError);
      expect(() => c.collapse(3), throwsRangeError);
      expect(() => c.collapsed = {-1}, throwsRangeError);
      expect(() => SplitController(collapsed: {-1}), throwsRangeError);
    });
  });

  group('the pointer over a divider', () {
    /// Two panes along `direction`.
    Widget split({
      Axis direction = Axis.horizontal,
      bool pointerShapes = true,
    }) => SplitView(
      direction: direction,
      pointerShapes: pointerShapes,
      panes: const [
        SplitPane(child: Text('a')),
        SplitPane(child: Text('b')),
      ],
    );

    test('is a resize across, between panes side by side', () async {
      final run = ShapeRun(split(), width: 21);
      await run.settle();
      await run.move(10, 1);
      expect(run.shapes(), ['ew-resize']);
      await run.move(3, 1);
      expect(run.shapes(), ['']);
      await run.quit();
    });

    test('is a resize down, between panes one below another', () async {
      final run = ShapeRun(
        split(direction: Axis.vertical),
        width: 10,
        height: 5,
      );
      await run.settle();
      await run.move(3, 2);
      expect(run.shapes(), ['ns-resize']);
      await run.move(3, 0);
      expect(run.shapes(), ['']);
      await run.quit();
    });

    test('is left alone with pointerShapes false', () async {
      final run = ShapeRun(
        split(pointerShapes: false),
        width: 21,
      );
      await run.settle();
      await run.move(10, 1);
      await run.move(3, 1);
      await run.quit();
      expect(run.written(), isNot(contains('\x1b]22;')));
    });
  });
}
