// Anchors: a follower in an overlay's entry placed by its target under the
// overlay, under it from its left edge or centred on it, moved in from the
// edges; another link followed as it is given; nothing shown while the
// target is in no tree; sizes without a child, and none shown once it
// is taken away; a target moved as its
// parent paints, to rows the frame does not repaint; and the arithmetic
// the menus place by too.
import 'package:test/test.dart';
import 'package:twk/src/overlay/anchor.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Shows what [builder] builds from its step, which [HostState.change]
/// sets.
final class Host extends StatefulWidget {
  const Host(this.builder, {super.key});

  final Widget Function(int step) builder;

  @override
  State<Host> createState() => HostState();
}

final class HostState extends State<Host> {
  var _step = 0;

  void change(int step) => setState(() => _step = step);

  @override
  Widget build(BuildContext context) => widget.builder(_step);
}

void main() {
  testTwk('a follower is placed under its target from its left edge, or '
      'centred on it; given another link it follows that one', (t) async {
    final one = AnchorLink();
    final two = AnchorLink();
    var link = one;
    var centred = false;
    final key = GlobalKey<HostState>();
    await t.pumpWidget(
      Overlay(
        child: Host(
          key: key,
          (step) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (step == 0) AnchorTarget(link: one, child: const Text('one')),
              const SizedBox(height: 1),
              if (step == 0)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: AnchorTarget(link: two, child: const Text('two-two')),
                ),
            ],
          ),
        ),
      ),
      size: (14, 6),
    );
    final entry = OverlayEntry(
      builder: (_) =>
          AnchorFollower(link: link, centred: centred, child: const Text('x')),
      fadeIn: Duration.zero,
      fadeOut: Duration.zero,
    );
    Overlay.of(key.currentContext!).insert(entry);
    await t.pump();
    expect(t, hasTextAt(0, 1, 'x'));
    link = two;
    entry.markNeedsBuild();
    await t.pump();
    expect(t, hasTextAt(4, 3, 'x'));
    RenderAnchorFollower follower() =>
        t.renderObject<RenderAnchorFollower>(find.byType(AnchorFollower));
    expect(follower().link, same(two));
    expect(follower().centred, isFalse);
    centred = true;
    entry.markNeedsBuild();
    await t.pump();
    expect(t, hasTextAt(7, 3, 'x'));
    expect(follower().centred, isTrue);
    expect(one.covers(7, 3), isFalse);
    expect(two.covers(7, 3), isTrue, reason: 'the follower');
    expect(two.covers(5, 2), isTrue, reason: 'the target');
    expect(two.covers(0, 0), isFalse);
    key.currentState!.change(1);
    await t.pump();
    expect(t, matchesScreen(''), reason: 'no target: nothing shown');
    expect(two.covers(7, 3), isFalse);
  });

  testTwk('a target given another link is the target of that one', (t) async {
    final one = AnchorLink();
    final two = AnchorLink();
    final key = GlobalKey<HostState>();
    await t.pumpWidget(
      Overlay(
        child: Host(
          key: key,
          (step) => Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: AnchorTarget(
                link: step == 0 ? one : two,
                child: const Text('target'),
              ),
            ),
          ),
        ),
      ),
      size: (12, 3),
    );
    RenderAnchorTarget target() =>
        t.renderObject<RenderAnchorTarget>(find.byType(AnchorTarget));
    expect(target().link, same(one));
    final overlay = Overlay.of(key.currentContext!);
    for (final (link, text) in [(one, '1'), (two, '2')]) {
      overlay.insert(
        OverlayEntry(
          builder: (_) => AnchorFollower(link: link, child: Text(text)),
          fadeIn: Duration.zero,
          fadeOut: Duration.zero,
        ),
      );
    }
    await t.pump();
    expect(t, matchesScreen('  target\n  1'));
    key.currentState!.change(1);
    await t.pump();
    await t.pump();
    expect(t, matchesScreen('  target\n  2'));
    expect(target().link, same(two));
  });

  testTwk('a target and a follower without a child are as small as they '
      'may be; a target is as big as its child intrinsically', (t) async {
    final link = AnchorLink();
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicWidth(
            child: IntrinsicHeight(
              child: AnchorTarget(
                key: const ValueKey('with'),
                link: link,
                child: const Text('ab'),
              ),
            ),
          ),
          AnchorTarget(key: const ValueKey('without'), link: AnchorLink()),
          const Text('end'),
        ],
      ),
      size: (6, 3),
    );
    expect(
      t.rect(find.byKey(const ValueKey('with'))),
      (x: 0, y: 0, width: 2, height: 1),
    );
    expect(
      t.rect(find.byKey(const ValueKey('without'))),
      (x: 0, y: 1, width: 0, height: 0),
    );
    expect(t.lines, ['ab', 'end', '']);
  });

  testTwk("a target's intrinsic sizes are its child's, at least and at "
      'most; without a child, none', (t) async {
    await t.pumpWidget(
      Column(
        children: [
          AnchorTarget(
            key: const ValueKey('with'),
            link: AnchorLink(),
            child: const Text('ab cde'),
          ),
          AnchorTarget(key: const ValueKey('without'), link: AnchorLink()),
        ],
      ),
      size: (8, 3),
    );
    final target = t.renderObject<RenderAnchorTarget>(
      find.byKey(const ValueKey('with')),
    );
    // its longest word at least, its whole line at most
    expect(target.getMinIntrinsicWidth(1), 3);
    expect(target.getMaxIntrinsicWidth(1), 6);
    // wrapped at its longest word: two rows
    expect(target.getMinIntrinsicHeight(3), 2);
    expect(target.getMaxIntrinsicHeight(3), 2);
    expect(target.getMinIntrinsicHeight(6), 1);
    final empty = t.renderObject<RenderAnchorTarget>(
      find.byKey(const ValueKey('without')),
    );
    expect(empty.getMinIntrinsicWidth(1), 0);
    expect(empty.getMinIntrinsicHeight(1), 0);
  });

  testTwk('a follower without a child shows nothing and covers no cell, '
      'by its target as anywhere, also once its child is taken away', (
    t,
  ) async {
    final link = AnchorLink();
    final key = GlobalKey();
    await t.pumpWidget(
      Overlay(
        child: AnchorTarget(
          key: key,
          link: link,
          child: const Text('target'),
        ),
      ),
      size: (8, 3),
    );
    var child = false;
    final entry = OverlayEntry(
      builder: (_) =>
          AnchorFollower(link: link, child: child ? const Text('x') : null),
      fadeIn: Duration.zero,
      fadeOut: Duration.zero,
    );
    Overlay.of(key.currentContext!).insert(entry);
    await t.pump();
    expect(t, matchesScreen('target'));
    expect(link.covers(0, 0), isFalse, reason: 'not the target either');
    expect(link.covers(0, 1), isFalse);

    child = true;
    entry.markNeedsBuild();
    await t.pump();
    // the target fills the overlay: the follower goes over its last row
    expect(t, hasTextAt(0, 2, 'x'));
    expect(link.covers(0, 2), isTrue);
    child = false;
    entry.markNeedsBuild();
    await t.pump();
    expect(t, matchesScreen('target'));
    expect(link.covers(0, 0), isFalse);
    expect(link.covers(0, 2), isFalse);
  });

  testTwk('a target its parent moves as it paints, to rows the frame does '
      'not repaint, has the follower where it was in that frame, and by '
      'it in the next, as a whole repaint shows it', (t) async {
    final link = AnchorLink();
    final key = GlobalKey();
    await t.pumpWidget(
      Overlay(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('top'),
            SizedBox(
              key: key,
              height: 3,
              child: _MovedInPaint(
                child: AnchorTarget(link: link, child: const Text('target')),
              ),
            ),
          ],
        ),
      ),
      size: (8, 8),
    );
    Overlay.of(key.currentContext!).insert(
      OverlayEntry(
        builder: (_) => AnchorFollower(link: link, child: const Text('x\ny')),
        fadeIn: Duration.zero,
        fadeOut: Duration.zero,
      ),
    );
    await t.pump();
    // the target as tall as the box, the follower under it
    expect(t.lines, ['top', 'target', '', '', 'x', 'y', '', '']);
    final frames = t.frames.length;
    // down a row, its parent marked for paint alone: the frame repaints
    // its rows and those the follower was on, not the one it goes to
    t.renderObject<_RenderMovedInPaint>(find.byType(_MovedInPaint))
      ..dy = 1
      ..markNeedsPaint();
    await t.pump();
    // where it was in that frame; under the target in the next, which
    // repaints all of it
    expect(
      [for (final f in t.frames.sublist(frames)) f.lines],
      [
        ['top', '', 'target', '', 'x', 'y', '', ''],
        ['top', '', 'target', '', '', 'x', 'y', ''],
      ],
    );
    final moved = t.lines;
    t.binding.twkApp.owner.markAllDirty();
    await t.pump();
    expect(t.lines, moved, reason: 'as a whole repaint shows it');
  });

  test('placeAlong puts a box after when it fits there, else on the side '
      'with more room, moved in as far as it has to; within keeps a place '
      'in its range', () {
    // after 2, in 10 cells: fits
    expect(placeAlong(2, 0, 4, 10), 2);
    // after 8: does not fit; more room before 6 than after 8
    expect(placeAlong(8, 6, 4, 10), 2);
    // after 3, ending at 1: more room after, moved in
    expect(placeAlong(3, 1, 9, 10), 1);
    expect(within(5, 3), 3);
    expect(within(-2, 3), 0);
    expect(within(2, -1), 0);
  });
}

/// Its child where [_RenderMovedInPaint.dy] says, set as it paints: a
/// target that moves without a layout.
final class _MovedInPaint extends SingleChildRenderObjectWidget {
  const _MovedInPaint({super.child});

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderMovedInPaint createRenderObject(BuildContext context) =>
      _RenderMovedInPaint();
}

/// As big as it may be, its child laid out as big too, and painted [dy]
/// rows down.
final class _RenderMovedInPaint extends RenderObject
    with RenderObjectWithChildMixin {
  var dy = 0;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    child!.layout(c, parentUsesSize: true);
  }

  @override
  void paint(PaintContext ctx) {
    final child = this.child!;
    child.parentData.dy = dy;
    paintChild(ctx, child);
  }
}
