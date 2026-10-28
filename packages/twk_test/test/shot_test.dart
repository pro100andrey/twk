// A Shot: a widget tree or a render tree on a screen of its own, each
// frame written to the emulator, read back as rows, colors and attributes.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Counts its builds in [builds] and shows `n` and its count.
final class _Counting extends StatefulWidget {
  const _Counting(this.builds, {super.key});

  final List<int> builds;

  @override
  State<_Counting> createState() => _CountingState();
}

final class _CountingState extends State<_Counting> {
  var count = 0;

  void increment() => setState(() => count++);

  @override
  Widget build(BuildContext context) {
    widget.builds.add(count);
    return Text('n $count');
  }
}

void main() {
  test('a widget tree shows on the emulator: its rows, every one of the '
      "screen's, and each cell's glyph, colors and attributes", () {
    final shot = Shot(
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ab',
            style: Style(fg: Color.red, bg: Color.rgb(1, 2, 3)),
          ),
          Text('c', style: Style(attrs: Attr.bold)),
        ],
      ),
      3,
      3,
    );
    expect(shot.vt.errors, isEmpty);
    expect(shot.rows, ['ab', 'c', '']);
    expect(shot.colors(0), [
      ('a', Color.red, const Color.rgb(1, 2, 3)),
      ('b', Color.red, const Color.rgb(1, 2, 3)),
      (' ', Color.defaultColor, Color.defaultColor),
    ]);
    expect(shot.attrs(1), [Attr.bold, 0, 0]);
    expect(shot.anyWide, isFalse);
    expect(shot.root.widget, isA<RootWidget>());
    expect(shot.top, isA<RenderObject>());
  });

  test('pump shows another widget, the state of the one that matches '
      'kept; frame builds what was marked dirty, and writes nothing when '
      'nothing changed', () {
    final builds = <int>[];
    final key = GlobalKey<_CountingState>();
    final shot = Shot(_Counting(builds, key: key), 6, 1);
    expect(shot.rows, ['n 0']);
    key.currentState!.increment();
    expect(shot.rows, ['n 0'], reason: 'no frame ran yet');
    shot.frame();
    expect(shot.rows, ['n 1']);
    shot.pump(_Counting(builds, key: key));
    expect(shot.rows, ['n 1']);
    expect(builds, [0, 1, 1]);
    expect(shot.screen.render(), isNull, reason: 'the frame wrote it all');
  });

  test('a wide glyph shows once in its row, and anyWide tells it is there; '
      'with ambiguousWidth 2 an ambiguous character is two columns, on the '
      'screen and on the emulator', () {
    final wide = Shot(const Text('界x'), 4, 1);
    expect(wide.rows, ['界x']);
    expect(wide.anyWide, isTrue);
    final ambiguous = Shot(const Text('±x'), 4, 1, ambiguousWidth: 2);
    expect(ambiguous.vt.errors, isEmpty);
    expect(ambiguous.rows, ['±x']);
    expect(ambiguous.vt.cell(2, 0).text, 'x');
  });

  test('a render tree shows as a widget tree does; it has no widgets to '
      'pump nor elements', () {
    final shot = Shot.render(RenderProgressBar(value: 0.5), 10, 1);
    expect(shot.rows, ['█████']);
    expect(shot.top, isA<RenderProgressBar>());
    expect(() => shot.pump(const Text('x')), throwsStateError);
    expect(() => shot.root, throwsStateError);
  });

  test('with under, what a repaint boundary at the root leaves unpainted '
      'shows that character', () {
    final shot = Shot.render(_RenderA(), 4, 2, under: '.');
    expect(shot.rows, ['a...', '....']);
  });
  test("the tree's own warnings are kept in logs, not printed", () {
    final shot = Shot(
      const SizedBox(
        height: 2,
        child: Column(children: [Text('a'), Text('b'), Text('c')]),
      ),
      4,
      2,
    );
    expect(shot.rows, [' a', ' b']);
    var asserts = false;
    assert(asserts = true, 'only in debug');
    expect(shot.logs, hasLength(asserts ? 1 : 0));
    if (asserts) {
      expect(shot.logs.single.message, contains('overflowed by 1 row'));
    }
  });
}

/// A repaint boundary that paints `a` in its first cell, and nothing in
/// the rest.
final class _RenderA extends RenderObject {
  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) =>
      ctx.canvas.text(0, 0, 'a', ctx.canvas.styles.pen(const Pen()));
}
