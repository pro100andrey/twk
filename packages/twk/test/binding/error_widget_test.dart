// A build that throws under runApp: a red block with the message in place
// of what the widget builds, the error logged with where the widget is,
// and the app going on; the block's own layout and its text's colour.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'harness.dart';

final class _Throws extends StatelessWidget {
  const _Throws();

  @override
  Widget build(BuildContext context) => throw StateError('boom');
}

void main() {
  test('a build that throws shows a red block with the message in its '
      'place; its siblings stay', () async {
    final run = Run(
      column(const [Label('above'), _Throws(), Label('below')]),
      width: 16,
    );
    await run.settle();
    expect(run.rows, ['above', 'Bad state: boom', 'below', '']);
    expect(
      [for (var x = 0; x < 16; x++) run.redAt(x, 1)],
      [
        for (var x = 0; x < 16; x++) x < 15,
      ],
    );
    expect(run.redAt(0, 0), isFalse);
    run.term.type('\x03');
    await run.ended();
  });

  test('the error is logged with the path of the widget and the stack, and '
      'reaches stderr once the terminal is restored', () async {
    final run = Run(const Column(children: [Label('a'), _Throws()]));
    await run.settle();
    final [record] = run.logs.records;
    expect(record.level, LogLevel.error);
    expect(record.message, 'Column → _Throws failed to build');
    expect(record.error, isA<StateError>());
    expect('${record.stack}', contains('_Throws.build'));
    run.term.type('\x03');
    await run.ended();
    expect(run.stderrLines, ['restored: $record']);
  });

  test('the app goes on, and the block goes once the widget builds without '
      'an error', () async {
    final key = GlobalKey<ProbeState>();
    final run = Run(
      Probe(
        key: key,
        (s) => s.count == 0
            ? throw StateError('not yet')
            : Label('count ${s.count}'),
      ),
    );
    await run.settle();
    expect(run.rows.first, 'Bad state: not yet');
    final state = key.currentState!;
    state.change(() => state.count++);
    await run.settle();
    expect(run.rows.first, 'count 1');
    expect(run.redAt(0, 0), isFalse);
    run.term.type('\x03');
    await run.ended();
  });

  test('a build that throws again shows its new message', () async {
    final key = GlobalKey<ProbeState>();
    final run = Run(
      Probe(key: key, (s) => throw StateError('try ${s.count}')),
    );
    await run.settle();
    expect(run.rows.first, 'Bad state: try 0');
    final state = key.currentState!;
    state.change(() => state.count++);
    await run.settle();
    expect(run.rows.first, 'Bad state: try 1');
    run.term.type('\x03');
    await run.ended();
  });

  group('the block', () {
    // the block of ErrorWidget(StateError(message)) laid out within [c]
    RenderObject laidOut(String message, BoxConstraints c) {
      final element = RootWidget(
        child: ErrorWidget(StateError(message)),
      ).attach(BuildOwner());
      return element.renderObject!..layout(c);
    }

    test('is as wide as its longest line and as tall as its lines within '
        'the constraints', () {
      final box = laidOut('boom\nand more', const BoxConstraints(0, 40, 0, 9));
      expect((box.width, box.height), (15, 2));
      final tight = laidOut('boom', const BoxConstraints.tight(30, 5));
      expect((tight.width, tight.height), (30, 5));
    });

    test('breaks its lines between words where it can, within a word where '
        'it must', () {
      final box = laidOut('boom and more', const BoxConstraints(0, 10, 0, 9));
      expect((box.width, box.height), (10, 3));
      expect(
        renderToString(box, 10, 3, styles: StyleTable()),
        'Bad state:\nboom and\nmore',
      );
      final narrow = laidOut('abcdef', const BoxConstraints(0, 4, 0, 9));
      expect(
        renderToString(narrow, 4, 5, styles: StyleTable()),
        'Bad\nstat\ne:\nabcd\nef',
      );
    });

    testTwk('its text is bright white on a dark theme, plain white on a '
        'light one, whose palette may make bright white dark', (t) async {
      for (final (theme, fg) in [
        (ThemeData.dark, Color.brightWhite),
        (ThemeData.light, const Color.rgb(255, 255, 255)),
        (ThemeData.dark, Color.brightWhite),
      ]) {
        await t.pumpWidget(
          Theme(data: theme, child: ErrorWidget(StateError('boom'))),
          size: (16, 1),
        );
        expect(
          t,
          styleAt(0, 0, allOf(hasFg(fg), hasBg(Color.red))),
          reason: '${theme.brightness}',
        );
      }
    });

    test('asks for as many rows as its lines at a width', () {
      final box = laidOut('boom and more', const BoxConstraints(0, 10, 0, 9));
      expect(box.getMaxIntrinsicHeight(10), 3);
      expect(box.getMinIntrinsicHeight(30), 1);
      expect(box.getMaxIntrinsicWidth(1), 'Bad state: boom and more'.length);
      expect(box.getMinIntrinsicWidth(1), 1, reason: 'it breaks its lines');
    });
  });
}
