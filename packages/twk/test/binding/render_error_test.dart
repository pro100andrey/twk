// What throws under runApp outside a build: a layout or a paint shows a red
// block with the message in place of the render object, a child that
// throws as it is created or updated shows an ErrorWidget in place of the
// widget above it; each is logged once with the path of its widget, and
// the rest of the frame is painted as ever.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

/// Eight `x`s, whose render object's layout or paint throws when told to.
final class _Bad extends LeafRenderObjectWidget {
  const _Bad({this.layout = false, this.paint = false});

  final bool layout;
  final bool paint;

  @override
  _RenderBad createRenderObject(BuildContext context) => _RenderBad()
    ..layoutThrows = layout
    ..paintThrows = paint;
}

final class _RenderBad extends RenderObject {
  var layoutThrows = false;
  var paintThrows = false;

  @override
  void performLayout(BoxConstraints c) {
    if (layoutThrows) {
      throw StateError('oops');
    }
    width = c.constrainW(8);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    if (paintThrows) {
      throw StateError('oops');
    }
    ctx.canvas.text(0, 0, 'xxxxxxxx', ctx.canvas.styles.pen(const Pen()));
  }
}

/// A leaf whose createRenderObject throws.
final class _BadCreate extends LeafRenderObjectWidget {
  const _BadCreate();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      throw StateError('no render object');
}

/// Shows [child].
final class _Wrapper extends StatelessWidget {
  const _Wrapper(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

void main() {
  test(
    'a layout that throws shows a red block with the message in place '
    'of the render object, logged once with the path of its widget',
    () async {
      final key = GlobalKey<ProbeState>();
      final run = Run(
        column([
          Probe(key: key, (s) => Label('above ${s.count}')),
          const _Wrapper(_Bad(layout: true)),
          const Label('below'),
        ]),
        width: 16,
      );
      await run.settle();
      expect(run.rows, ['above 0', 'Bad state: oops', 'below', '']);
      expect(
        [for (var x = 0; x < 16; x++) run.redAt(x, 1)],
        [for (var x = 0; x < 16; x++) x < 15],
      );
      final [record] = run.logs.records;
      expect(record.level, LogLevel.error);
      expect(record.message, 'Column → _Wrapper → _Bad failed to lay out');
      expect(record.error, isA<StateError>());
      expect('${record.stack}', contains('_RenderBad.performLayout'));

      final state = key.currentState!;
      state.change(() => state.count++);
      await run.settle();
      expect(run.rows, ['above 1', 'Bad state: oops', 'below', '']);
      expect(run.logs.records, hasLength(1));
      run.term.type('\x03');
      await run.ended();
    },
  );

  test('a paint that throws shows the message over the render object, cut '
      'off at its bounds, logged with the path of its widget', () async {
    final run = Run(
      column(const [Label('above'), _Bad(paint: true), Label('below')]),
      width: 16,
    );
    await run.settle();
    expect(run.rows, ['above', 'Bad', 'below', '']);
    expect(
      [for (var x = 0; x < 16; x++) run.redAt(x, 1)],
      [for (var x = 0; x < 16; x++) x < 8],
    );
    expect(run.logged(LogLevel.error), ['Column → _Bad failed to paint']);
    run.term.type('\x03');
    await run.ended();
  });

  test('a child that throws as it is created shows an ErrorWidget in place '
      'of the widget above it', () async {
    final run = Run(
      column(const [
        Label('above'),
        _Wrapper(_BadCreate()),
        _Wrapper(Label('below')),
      ]),
      width: 30,
    );
    await run.settle();
    expect(run.rows, ['above', 'Bad state: no render object', 'below', '']);
    expect(run.logged(LogLevel.error), ['Column → _Wrapper failed to build']);
    run.term.type('\x03');
    await run.ended();
  });

  test('a state whose initState throws, deep in what a widget builds, shows '
      'an ErrorWidget in place of the widget above it', () async {
    final run = Run(
      column([
        const Label('above'),
        _Wrapper(
          column([
            Probe(
              (s) => const Label('never'),
              onInit: (s) => throw StateError('no state'),
            ),
          ]),
        ),
        const Label('below'),
      ]),
      width: 30,
    );
    await run.settle();
    expect(run.rows, ['above', 'Bad state: no state', 'below', '']);
    expect(run.logged(LogLevel.error), ['Column → _Wrapper failed to build']);
    run.term.type('\x03');
    await run.ended();
  });
}
