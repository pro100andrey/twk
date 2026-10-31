// Popovers: shown under their child while open; flipped above it and to
// end at its right edge near the edges of the overlay, moved in; following
// a child that moves, also inside a repaint boundary that repaints alone;
// asked to close as the focus leaves the child and the popover, by Escape
// and by a press outside both, Escape hinted; the fades in and out; their
// entry; no Overlay.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../data/shot.dart' show Counted, PaintCount;

/// A box saying [text].
Widget boxed(String text) => Box(border: const Border.all(), child: Text(text));

/// A popover saying [text] by [child] at [left], [top] of a 20 × 8
/// overlay.
Widget at(
  int left,
  int top, {
  bool open = true,
  String text = 'pop',
  Widget child = const Text('anchor'),
}) => Overlay(
  child: Stack(
    children: [
      Positioned(
        left: left,
        top: top,
        child: Popover(open: open, popover: boxed(text), child: child),
      ),
    ],
  ),
);

/// A [Focus] shown as its [label], after `>` while it has the primary
/// focus and ` ` while not.
final class Field extends StatelessWidget {
  const Field(this.label, {this.node, this.autofocus = false, super.key});

  final String label;
  final FocusNode? node;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    autofocus: autofocus,
    debugLabel: label,
    child: _Mark(label),
  );
}

final class _Mark extends StatelessWidget {
  const _Mark(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text('${Focus.of(context).hasPrimaryFocus ? '>' : ' '}$label');
}

/// [child] [dx] cells in, in a repaint boundary that lays it out and
/// repaints alone when [dx] changes.
final class Shifted extends SingleChildRenderObjectWidget {
  const Shifted(this.dx, {super.child, super.key});

  final ValueNotifier<int> dx;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderShifted(dx);
}

final class _RenderShifted extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderShifted(this.dx) {
    dx.addListener(markNeedsLayout);
  }

  final ValueNotifier<int> dx;

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    child
      ?..layout(BoxConstraints(0, width, 0, height), parentUsesSize: true)
      ..parentData.dx = dx.value;
  }

  @override
  void paint(PaintContext ctx) {
    ctx.canvas.fill(
      0,
      0,
      width,
      height,
      const Style().penIn(ctx.canvas.styles),
    );
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}

void main() {
  testTwk('a popover shows under its child, from its left edge, while it is '
      'open', (t) async {
    await t.pumpWidget(at(2, 1, open: false), size: (20, 8));
    expect(t, matchesScreen('\n  anchor'));
    await t.pumpWidget(at(2, 1));
    expect(
      t,
      matchesScreen('''

  anchor
  ┌───┐
  │pop│
  └───┘'''),
    );
    await t.pumpWidget(at(2, 1, open: false));
    expect(t, matchesScreen('\n  anchor'));
    await t.pumpWidget(at(2, 1, text: 'again'));
    expect(t, hasTextAt(2, 3, '│again│'));
  });

  testTwk('a popover built open shows from the frame after', (t) async {
    await t.pumpWidget(at(2, 1), size: (20, 8), duration: Duration.zero);
    expect(t, matchesScreen('\n  anchor'));
    await t.pump();
    expect(t, hasTextAt(2, 3, '│pop│'));
  });

  testTwk('a popover goes above its child where there is no room under it, '
      'ends at its right edge where there is none on the right, and is '
      'moved in from the edges', (t) async {
    await t.pumpWidget(at(16, 7, child: const Text('ab')), size: (20, 8));
    await t.pump();
    expect(t.lines.skip(4), [
      '             ┌───┐',
      '             │pop│',
      '             └───┘',
      '                ab',
    ]);
    expect(t.lines.take(4).where((l) => l.isNotEmpty), isEmpty);

    // more room on the right, which it does not fit: moved in
    await t.pumpWidget(
      at(6, 0, text: '0123456789abc', child: const Text('ab')),
    );
    expect(t.lines.take(4), [
      '      ab',
      '     ┌─────────────┐',
      '     │0123456789abc│',
      '     └─────────────┘',
    ]);
  });

  testTwk('a popover follows its child as that is laid out somewhere '
      'else, in the same frame, and paints no more', (t) async {
    final above = ValueNotifier(1);
    final count = PaintCount();
    await t.pumpWidget(
      Overlay(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListenableBuilder(
              listenable: above,
              builder: (context, _) => SizedBox(height: above.value),
            ),
            const Popover(
              open: true,
              popover: Box(border: Border.all(), child: Text('pop')),
              child: Text('anchor'),
            ),
            Counted(count),
          ],
        ),
      ),
      size: (20, 8),
    );
    await t.pump();
    expect(t, hasTextAt(0, 3, '│pop│'));
    above.value = 3;
    final frames = t.terminal.frames.length;
    final paints = count.paints;
    await t.pump();
    expect(t.terminal.frames.length - frames, 1);
    await t.pump();
    expect(count.paints - paints, 1);
    expect(
      t,
      matchesScreen('''



anchor
┌───┐
│pop│
└───┘'''),
    );
  });

  testTwk('a popover follows its child moved inside a repaint boundary that '
      'repaints alone, from the next frame', (t) async {
    final dx = ValueNotifier(1);
    await t.pumpWidget(
      Overlay(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              height: 1,
              child: Shifted(
                dx,
                child: const Popover(
                  open: true,
                  popover: Box(border: Border.all(), child: Text('pop')),
                  child: Text('anchor'),
                ),
              ),
            ),
          ],
        ),
      ),
      size: (20, 8),
    );
    await t.pump();
    expect(t, hasTextAt(1, 2, '│pop│'));
    dx.value = 6;
    await t.pump();
    await t.pump();
    expect(
      t,
      matchesScreen('''
      anchor
      ┌───┐
      │pop│
      └───┘'''),
    );
  });

  testTwk('a popover asks to close when the focus goes from its child or '
      'from it to a node in neither, and on Escape in either', (t) async {
    final log = <String>[];
    final anchor = FocusNode();
    final inside = FocusNode();
    final other = FocusNode();
    addTearDown(anchor.dispose);
    addTearDown(inside.dispose);
    addTearDown(other.dispose);
    await t.pumpWidget(
      Overlay(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Popover(
              open: true,
              onDismiss: () => log.add('dismiss'),
              popover: Field('inside', node: inside),
              child: Field('anchor', node: anchor, autofocus: true),
            ),
            const SizedBox(height: 2),
            Field('other', node: other),
          ],
        ),
      ),
      size: (20, 5),
    );
    await t.pump();
    expect(t, matchesScreen('>anchor\n inside\n\n other'));
    inside.requestFocus();
    await t.pump();
    expect(t, matchesScreen(' anchor\n>inside\n\n other'));
    expect(log, isEmpty);
    other.requestFocus();
    await t.pump();
    expect(log, ['dismiss']);

    // nothing while the focus moves between other nodes
    log.clear();
    t.binding.focusManager.rootScope.requestFocus();
    await t.pump();
    expect(log, isEmpty);

    inside.requestFocus();
    await t.pump();
    await t.press('escape');
    await t.pump();
    expect(log, ['dismiss']);
    anchor.requestFocus();
    await t.pump();
    expect(log, ['dismiss']);
    await t.press('escape');
    await t.pump();
    expect(log, ['dismiss', 'dismiss']);
  });

  testTwk('a closed popover asks nothing, and leaves Escape to the nodes '
      'above', (t) async {
    final log = <String>[];
    final other = FocusNode();
    addTearDown(other.dispose);
    await t.pumpWidget(
      Overlay(
        child: KeyBindings(
          {'escape': () => log.add('escape')},
          child: Column(
            children: [
              Popover(
                open: false,
                onDismiss: () => log.add('dismiss'),
                popover: boxed('pop'),
                child: const Field('anchor', autofocus: true),
              ),
              Field('other', node: other),
            ],
          ),
        ),
      ),
      size: (20, 5),
    );
    await t.pump();
    await t.press('escape');
    other.requestFocus();
    await t.pump();
    expect(log, ['escape']);
  });

  testTwk('while open, Escape is bound with the hint close, in the child '
      'and in the popover', (t) async {
    var open = true;
    final inside = FocusNode();
    addTearDown(inside.dispose);
    Widget app() => Overlay(
      child: Popover(
        open: open,
        onDismiss: () => open = false,
        popover: Field('in', node: inside),
        child: const Field('anchor', autofocus: true),
      ),
    );
    List<String> keys() => [
      for (final k in t.binding.focusManager.activeKeys) '$k',
    ];
    await t.pumpWidget(app(), size: (20, 5));
    await t.pump();
    expect(keys(), contains('escape close'));
    inside.requestFocus();
    await t.pump();
    expect(keys(), contains('escape close'));
    await t.press('escape');
    expect(open, isFalse);
    await t.pumpWidget(app());
    expect(keys(), isNot(contains('escape close')));
  });

  testTwk('a popover fades in over fadeIn as it opens and out over fadeOut '
      'as it closes', (t) async {
    const theme = ThemeData.dark;
    const ms = Duration(milliseconds: 1);
    Widget app({required bool open}) => Theme(
      data: theme,
      child: Box(
        style: theme.background,
        child: Overlay(
          child: Align(
            alignment: Alignment.topLeft,
            child: Popover(
              open: open,
              fadeIn: ms * 120,
              fadeOut: ms * 100,
              popover: Box(style: theme.surface, child: const Text('pop')),
              child: const Text('anchor'),
            ),
          ),
        ),
      ),
    );
    final surface = theme.surface.bg!;
    final background = theme.background.bg!;
    await t.pumpWidget(app(open: false), size: (20, 5));
    await t.pumpWidget(app(open: true));
    expect(t, styleAt(0, 1, hasBg(background)));
    await t.pump(ms * 50);
    expect(t, styleAt(0, 1, isNot(anyOf(hasBg(background), hasBg(surface)))));
    await t.pump(ms * 80);
    await t.pump();
    expect(t, styleAt(0, 1, hasBg(surface)));
    expect(t, hasTextAt(0, 1, 'pop'));
    await t.pumpWidget(app(open: false));
    await t.pump(ms * 50);
    expect(t, styleAt(0, 1, isNot(anyOf(hasBg(background), hasBg(surface)))));
    await t.pump(ms * 60);
    await t.pump();
    expect(t, styleAt(0, 1, hasBg(background)));
    expect(t, matchesScreen('anchor'));
  });

  testTwk('a popover asks to close on a press outside it and its child, '
      'which reaches what is there', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Overlay(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onDown: (event) => log.add('app ${event.x},${event.y}'),
          child: Stack(
            children: [
              Positioned(
                left: 2,
                top: 1,
                child: Popover(
                  open: true,
                  onDismiss: () => log.add('dismiss'),
                  popover: boxed('pop'),
                  child: const Text('anchor'),
                ),
              ),
            ],
          ),
        ),
      ),
      size: (20, 8),
    );
    await t.pump();
    await t.click(3, 3);
    await t.click(7, 1);
    await t.pump();
    expect(log, ['app 7,1']);
    await t.click(12, 6);
    await t.pump();
    expect(log, ['app 7,1', 'dismiss', 'app 12,6']);
  });

  testTwk('a popover keeps an entry in the overlay while it is in the tree, '
      'open or not', (t) async {
    final overlay = GlobalKey();
    Widget app({required bool shown}) => Overlay(
      key: overlay,
      child: shown
          ? Popover(open: false, popover: boxed('pop'), child: const Text('a'))
          : const Text('a'),
    );
    await t.pumpWidget(app(shown: true));
    await t.pump();
    final state = overlay.currentState! as OverlayState;
    expect(state.entries, hasLength(1));
    await t.pumpWidget(app(shown: false));
    expect(state.entries, isEmpty);
  });

  testTwk('a Popover without an Overlay above fails to build, saying where '
      'to place one', (t) async {
    await t.pumpWidget(
      const Popover(open: true, popover: Text('pop'), child: Text('a')),
    );
    const failed =
        'Popover failed to build: Bad state: Popover: no Overlay above it: '
        'place an Overlay above it, as App does around the whole app: '
        'App(child: …)';
    expect(
      [
        for (final r in t.logs.records)
          if (r.level == LogLevel.error) '${r.message}: ${r.error}',
      ],
      [failed],
    );
  });

  testTwk('a popover moved in the tree with a GlobalKey shows by its child '
      'in its new place', (t) async {
    final key = GlobalKey();
    Widget app({required bool moved}) {
      final popover = Popover(
        key: key,
        open: true,
        popover: const Text('pop'),
        child: const Text('anchor'),
      );
      return Overlay(
        child: Align(
          alignment: Alignment.topLeft,
          child: moved
              ? Padding(padding: const EdgeInsets.only(left: 4), child: popover)
              : popover,
        ),
      );
    }

    await t.pumpWidget(app(moved: false), size: (20, 4));
    await t.pump();
    expect(t, matchesScreen('anchor\npop'));
    await t.pumpWidget(app(moved: true));
    await t.pump();
    expect(t, matchesScreen('    anchor\n    pop'));
  });

  testTwk('matchAnchorWidth: the popover at least as wide as its anchor, '
      'following it in the frame its width changes, the overlay not '
      'otherwise laid out again', (t) async {
    final width = ValueNotifier(10);
    addTearDown(width.dispose);
    await t.pumpWidget(
      Overlay(
        child: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<int>(
            valueListenable: width,
            builder: (context, w, _) => SizedBox(
              width: w,
              child: const Popover(
                open: true,
                matchAnchorWidth: true,
                popover: ColoredBox(color: Color.red, child: Text('x')),
                child: Text('a'),
              ),
            ),
          ),
        ),
      ),
      size: (30, 4),
    );
    expect(t, styleAt(9, 1, hasBg(Color.red)));
    expect(t, styleAt(10, 1, isNot(hasBg(Color.red))));
    width.value = 16;
    await t.pump();
    expect(t, styleAt(15, 1, hasBg(Color.red)));
    expect(t, styleAt(16, 1, isNot(hasBg(Color.red))));
    width.value = 4;
    await t.pump();
    expect(t, styleAt(3, 1, hasBg(Color.red)));
    expect(t, styleAt(4, 1, isNot(hasBg(Color.red))));
  });

  testTwk('without matchAnchorWidth the popover is as wide as it likes', (
    t,
  ) async {
    await t.pumpWidget(
      const Overlay(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 10,
            child: Popover(
              open: true,
              popover: ColoredBox(color: Color.red, child: Text('x')),
              child: Text('a'),
            ),
          ),
        ),
      ),
      size: (30, 4),
    );
    expect(t, styleAt(0, 1, hasBg(Color.red)));
    expect(t, styleAt(1, 1, isNot(hasBg(Color.red))));
  });
}
