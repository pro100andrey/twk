// CustomPaint: cells painted under and over the child, as big as the
// child or its size; repainted on a new painter that says so and on its
// repaint listenable, with nothing built again; hit where its painters say.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// The render objects a hit test of the last frame finds at [x], [y], the
/// deepest first.
List<RenderObject> hitsAt(TwkTester t, int x, int y) {
  final result = HitTestResult();
  t.binding.twkApp.owner.hitTest(result, x, y);
  return [for (var i = 0; i < result.length; i++) result[i]];
}

/// Fills its cells with [glyph], or with [notifier]'s value where given,
/// which it repaints on; counts its paints and the size it painted at.
/// Hit where [hits] says, when given.
final class Fill extends CellPainter {
  Fill(
    this.glyph, {
    this.notifier,
    this.repaints = false,
    this.hits,
    this.at,
  }) : super(repaint: notifier);

  final String glyph;
  final ValueNotifier<int>? notifier;

  /// What [shouldRepaint] answers.
  final bool repaints;
  final bool? Function(int x, int y)? hits;

  /// Only this cell, (x, y), when given.
  final (int, int)? at;

  static var paints = 0;
  static var sizes = <(int, int)>[];

  @override
  void paint(Canvas canvas, int width, int height) {
    paints++;
    sizes.add((width, height));
    final pen = canvas.styles.pen(const Pen());
    final g = notifier == null ? glyph : '${notifier!.value}';
    if (at case (final x, final y)) {
      canvas.text(x, y, g, pen);
      return;
    }
    for (var y = 0; y < height; y++) {
      canvas.text(0, y, g * width, pen);
    }
    // moved and clipped to nothing: undone after it
    canvas
      ..translate(5, 1)
      ..clipRect(0, 0, 0, 0);
  }

  @override
  bool shouldRepaint(Fill oldDelegate) => repaints;

  @override
  bool? hitTest(int x, int y) => hits?.call(x, y);
}

/// A [ValueNotifier] that says whether it has listeners.
final class Watched extends ValueNotifier<int> {
  Watched() : super(0);

  bool get listened => hasListeners;
}

/// Shows what [builder] builds of a count that [HostState.bump] counts up;
/// counts its builds.
final class Host extends StatefulWidget {
  const Host(this.builder, {super.key});

  final Widget Function(int n) builder;

  @override
  State<Host> createState() => HostState();
}

final class HostState extends State<Host> {
  var n = 0;
  static var builds = 0;

  void bump() => setState(() => n++);

  @override
  Widget build(BuildContext context) {
    builds++;
    return widget.builder(n);
  }
}

void main() {
  setUp(() {
    Fill.paints = 0;
    Fill.sizes = [];
    HostState.builds = 0;
  });

  testTwk('the painter paints under the child, the foreground painter over '
      "it, all of them at the child's size", (t) async {
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: CustomPaint(
          painter: Fill('.'),
          foregroundPainter: Fill('#', at: (3, 0)),
          child: const SizedBox(width: 6, height: 2, child: Text('ab')),
        ),
      ),
      size: (10, 3),
    );
    expect(t.lines.take(3), ['ab.#..', '......', '']);
    final paint = t.renderObject(find.byType(CustomPaint));
    expect((paint.width, paint.height), (6, 2));
    expect(Fill.sizes, [(6, 2), (6, 2)]);
  });

  testTwk('without a child it is as big as its size, within the '
      'constraints', (t) async {
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomPaint(painter: Fill('x'), size: (3, 2)),
          SizedBox(
            width: 2,
            child: CustomPaint(painter: Fill('y'), size: (3, 1)),
          ),
          CustomPaint(painter: Fill('z')),
          const Text('end'),
        ],
      ),
      size: (10, 5),
    );
    expect(t.lines.take(5), ['xxx', 'xxx', 'yy', 'end', '']);
    final paint = t.renderObject(find.byType(CustomPaint).first);
    expect(paint.getMaxIntrinsicWidth(0), 3);
    expect(paint.getMaxIntrinsicHeight(0), 2);
  });

  testTwk('a repaint listenable that notifies repaints it, building '
      'nothing and painting no other painter', (t) async {
    final value = ValueNotifier(1);
    addTearDown(value.dispose);
    final other = Fill('-');
    await t.pumpWidget(
      Host(
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomPaint(painter: other, size: (4, 1)),
            CustomPaint(
              painter: Fill('', notifier: value),
              size: (4, 1),
            ),
          ],
        ),
      ),
      size: (10, 3),
    );
    expect(t.lines.take(2), ['----', '1111']);
    expect((HostState.builds, Fill.paints), (1, 2));
    value.value = 2;
    await t.pump();
    expect(t.lines.take(2), ['----', '2222']);
    expect(HostState.builds, 1, reason: 'nothing built');
    expect(Fill.paints, 3, reason: 'the one that notified painted');
    value.value = 3;
    await t.pump();
    expect(t.lines[1], '3333');
    expect(Fill.paints, 4);
  });

  testTwk('a painter listens while it is in the tree, and a new one in '
      'place of the one before', (t) async {
    final first = Watched()..value = 1;
    final second = Watched()..value = 5;
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final host = GlobalKey<HostState>();
    await t.pumpWidget(
      Host(
        key: host,
        (n) => Align(
          alignment: Alignment.topLeft,
          child: n < 2
              ? CustomPaint(
                  painter: Fill(
                    '',
                    notifier: n == 0 ? first : second,
                    repaints: true,
                  ),
                  size: (2, 1),
                )
              : const Text('gone'),
        ),
      ),
      size: (10, 2),
    );
    expect(t.lines.first, '11');
    expect((first.listened, second.listened), (true, false));
    host.currentState!.bump();
    await t.pump();
    expect(t.lines.first, '55');
    expect((first.listened, second.listened), (false, true));
    final paints = Fill.paints;
    first.value = 2;
    await t.pump();
    expect(Fill.paints, paints, reason: 'the old one not listened to');
    second.value = 6;
    await t.pump();
    expect(t.lines.first, '66');
    host.currentState!.bump();
    await t.pump();
    expect(t.lines.first, 'gone');
    expect(second.listened, isFalse, reason: 'out of the tree');
  });

  testTwk('a new painter repaints when it says so, or is of another type, '
      'and not otherwise', (t) async {
    final host = GlobalKey<HostState>();
    await t.pumpWidget(
      Host(
        key: host,
        (n) => Align(
          alignment: Alignment.topLeft,
          child: CustomPaint(
            painter: n == 3 ? _Other() : Fill('$n', repaints: n == 2),
            size: (3, 1),
          ),
        ),
      ),
      size: (10, 2),
    );
    expect((t.lines.first, Fill.paints), ('000', 1));
    host.currentState!.bump();
    await t.pump();
    expect(HostState.builds, 2);
    expect((t.lines.first, Fill.paints), ('000', 1), reason: 'said not to');
    host.currentState!.bump();
    await t.pump();
    expect((t.lines.first, Fill.paints), ('222', 2), reason: 'said to');
    host.currentState!.bump();
    await t.pump();
    expect(t.lines.first, 'ooo', reason: 'another type');
  });

  testTwk('the painter is hit where the child is not, by default in every '
      'cell, and where its hitTest says', (t) async {
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: Row(
          children: [
            CustomPaint(
              painter: Fill('.'),
              child: const SizedBox(
                width: 4,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text('ab'),
                ),
              ),
            ),
            CustomPaint(
              painter: Fill(':', hits: (x, y) => x == 1),
              size: (3, 1),
            ),
            CustomPaint(
              painter: Fill('!', hits: (x, y) => false),
              size: (2, 1),
            ),
          ],
        ),
      ),
      size: (12, 2),
    );
    final paints = find.byType(CustomPaint);
    final first = t.renderObject(paints.first);
    final second = t.renderObject(paints.at(1));
    final third = t.renderObject(paints.at(2));
    final text = t.renderObject(find.text('ab'));
    expect(hitsAt(t, 0, 0).first, text);
    expect(hitsAt(t, 0, 0), contains(first), reason: 'its child is hit');
    expect(hitsAt(t, 3, 0).first, first, reason: 'where the child is not');
    expect(hitsAt(t, 4, 0), isNot(contains(second)));
    expect(hitsAt(t, 5, 0).first, second);
    expect(hitsAt(t, 6, 0), isNot(contains(second)));
    for (final x in [7, 8]) {
      expect(hitsAt(t, x, 0), isNot(contains(third)), reason: 'cell $x');
    }
  });

  testTwk('the foreground painter, hit where it says, is hit over the '
      'child; by default the child is hit through it', (t) async {
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: Row(
          children: [
            CustomPaint(
              foregroundPainter: Fill('#', at: (0, 0), hits: (x, y) => x == 0),
              child: const Text('ab'),
            ),
            CustomPaint(
              foregroundPainter: Fill('#', at: (0, 0)),
              child: const Text('cd'),
            ),
          ],
        ),
      ),
      size: (10, 2),
    );
    expect(t.lines.first, '#b#d');
    final paints = find.byType(CustomPaint);
    final first = t.renderObject(paints.first);
    final second = t.renderObject(paints.at(1));
    final ab = t.renderObject(find.text('ab'));
    final cd = t.renderObject(find.text('cd'));
    expect(hitsAt(t, 0, 0).first, first, reason: 'over the child');
    expect(hitsAt(t, 0, 0), isNot(contains(ab)));
    expect(hitsAt(t, 1, 0).first, ab);
    expect(hitsAt(t, 2, 0).first, cd, reason: 'through it');
    expect(hitsAt(t, 2, 0), contains(second));
  });

  testTwk('a painter that does not say where it is hit is hit in every cell', (
    t,
  ) async {
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: CustomPaint(painter: _Other(), size: (3, 2)),
      ),
      size: (5, 3),
    );
    final paint = t.renderObject(find.byType(CustomPaint));
    for (final (x, y) in [(0, 0), (2, 0), (1, 1)]) {
      expect(hitsAt(t, x, y).first, paint, reason: 'cell $x, $y');
    }
    expect(hitsAt(t, 3, 0), isNot(contains(paint)));
  });

  testTwk('the debug tree shows its size and the types of its painters, '
      'each once, and none of what is left out', (t) async {
    await t.pumpWidget(
      Column(
        children: [
          CustomPaint(painter: _Other(), size: (3, 1)),
          CustomPaint(foregroundPainter: Fill('x')),
        ],
      ),
      size: (5, 3),
    );
    final paints = find.byType(CustomPaint);
    expect(
      '${t.element(paints.first).describe()}',
      'CustomPaint ‹size: "3×1", painter: _Other›',
    );
    expect(
      '${t.element(paints.at(1)).describe()}',
      'CustomPaint ‹foregroundPainter: Fill›',
    );
  });
}

/// Paints `o` in every cell.
final class _Other extends CellPainter {
  @override
  void paint(Canvas canvas, int width, int height) =>
      canvas.text(0, 0, 'o' * width, canvas.styles.pen(const Pen()));

  @override
  bool shouldRepaint(_Other oldDelegate) => false;
}
