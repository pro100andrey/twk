// RepaintBoundary: its child a repaint boundary of the core, as big as the
// child; a mark inside it repaints it alone, nothing around it, over what
// was under it in the cells the child leaves.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [glyph] in every cell, or [notifier]'s value in the cell it says when
/// given ([at] its row), which it repaints on; counts the paints of each
/// glyph.
final class Mark extends CellPainter {
  Mark(this.glyph, {this.notifier, this.at = 0}) : super(repaint: notifier);

  final String glyph;
  final ValueNotifier<int>? notifier;
  final int at;

  static final paints = <String, int>{};

  @override
  void paint(Canvas canvas, int width, int height) {
    paints[glyph] = (paints[glyph] ?? 0) + 1;
    final pen = canvas.styles.pen(const Pen());
    final n = notifier;
    if (n != null) {
      canvas.text(n.value, at, glyph, pen);
      return;
    }
    for (var y = 0; y < height; y++) {
      canvas.text(0, y, glyph * width, pen);
    }
  }

  @override
  bool shouldRepaint(Mark oldDelegate) => false;
}

/// [inner] on a row of dots, in a [RepaintBoundary] when [boundary].
Widget scene(Widget inner, {required bool boundary}) => Align(
  alignment: Alignment.topLeft,
  child: CustomPaint(
    painter: Mark('.'),
    child: SizedBox(
      width: 6,
      height: 1,
      child: boundary ? RepaintBoundary(child: inner) : inner,
    ),
  ),
);

void main() {
  setUp(Mark.paints.clear);

  testTwk('its render object is a repaint boundary as big as the child', (
    t,
  ) async {
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(child: Text('inside')),
      ),
      size: (10, 2),
    );
    expect(t.lines.first, 'inside');
    final boundary = t.renderObject(find.byType(RepaintBoundary));
    expect(boundary.isRepaintBoundary, isTrue);
    expect((boundary.width, boundary.height), (6, 1));
    expect(boundary.getMaxIntrinsicWidth(1), 6);
  });

  testTwk('a mark inside it repaints it alone, not what is around it; '
      'without it, the rows of what is around it repaint too', (t) async {
    for (final boundary in [true, false]) {
      Mark.paints.clear();
      final x = ValueNotifier(1);
      addTearDown(x.dispose);
      await t.pumpWidget(
        scene(
          CustomPaint(painter: Mark('x', notifier: x)),
          boundary: boundary,
        ),
        size: (10, 2),
      );
      expect(t.lines.first, '.x....', reason: 'boundary $boundary');
      final around = Mark.paints['.'];
      x.value = 3;
      await t.pump();
      expect(t.lines.first, '...x..', reason: 'boundary $boundary');
      expect(
        Mark.paints['.'],
        boundary ? around : around! + 1,
        reason: 'boundary $boundary',
      );
      await t.pumpWidget(const SizedBox());
    }
  });

  testTwk('the cells the child leaves show what was under it as it repaints '
      'on its own', (t) async {
    final x = ValueNotifier(0);
    addTearDown(x.dispose);
    await t.pumpWidget(
      scene(CustomPaint(painter: Mark('x', notifier: x)), boundary: true),
      size: (10, 2),
    );
    for (var i = 0; i < 6; i++) {
      x.value = i;
      await t.pump();
      expect(t.lines.first, '${'.' * i}x${'.' * (5 - i)}', reason: 'at $i');
    }
    expect(Mark.paints['.'], 1, reason: 'never repainted around it');
  });
}
