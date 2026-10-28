// The pointer over the links of a Markdown view: a hand (OSC 22
// `pointer`) over a link or an image in a paragraph, a heading or a
// table, the terminal's own elsewhere; the mouse's motion asked for only
// while the view has a link and the terminal shows the pointer's shape.
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

/// An app run full screen on a terminal in memory, 30 × 14 cells, that
/// shows the pointer's shape unless [shapes] is false.
///
/// It runs on a [FakeClock]: its frames are timers, which fire when
/// [settle] moves the clock on, however long the machine takes to run
/// them.
final class _Run {
  _Run(Widget app, {bool shapes = true}) {
    term = clock.run(
      () => HeadlessTerminal(width: 30, height: 14, pointerShapes: shapes),
    );
    _done = clock.run(
      () => AppBinding(term, maxFps: 1000, clock: clock.stopwatch).run(app),
    )..ignore(); // an error it ends with is thrown by quit
  }

  final clock = FakeClock();
  late final HeadlessTerminal term;
  late final Future<void> _done;
  var _read = 0;

  /// Lets the frame loop run: builds, frames and the timers they start,
  /// over 30 ms of the app's clock.
  Future<void> settle() => clock.elapse(const Duration(milliseconds: 30));

  /// Runs [fn] in the app's zone, then lets the frame loop run.
  Future<void> act(void Function() fn) async {
    clock.run(fn);
    await settle();
  }

  /// What the app wrote since the last call.
  String written() {
    final s = utf8.decode([
      for (final f in term.frames.skip(_read)) ...f,
    ], allowMalformed: true);
    _read = term.frames.length;
    return s;
  }

  /// The shapes the app set since the last call, `` for the terminal's
  /// own.
  List<String> shapes() => [
    for (final m in RegExp('\x1b]22;([^\x1b]*)\x1b\\\\').allMatches(written()))
      m[1]!,
  ];

  /// The mouse moved to the cell ([x], [y]) with no button held.
  Future<void> move(int x, int y) async {
    term.type('\x1b[<35;${x + 1};${y + 1}M');
    await settle();
  }

  /// Quits the app and runs it until it has ended, throwing the error it
  /// ended with.
  ///
  /// The app's future completes in the clock's zone, as the clock moves:
  /// awaited without moving it, it never would.
  Future<void> quit() async {
    term.type('\x03');
    // fails 100 settles after quit rather than hanging
    await clock.elapseUntil(
      _done,
      step: const Duration(milliseconds: 30),
      within: const Duration(seconds: 3),
    );
  }
}

/// Shows the document [docs] has at the step it is at, from 0, which
/// [_StepsState.next] moves on.
final class _Steps extends StatefulWidget {
  const _Steps(this.docs, {super.key});

  final List<String> docs;

  @override
  State<_Steps> createState() => _StepsState();
}

final class _StepsState extends State<_Steps> {
  var _step = 0;

  void next() => setState(() => _step++);

  @override
  Widget build(BuildContext context) => MarkdownView(widget.docs[_step]);
}

// 0 see the docs now
// 2 Title
// 4 logo and ref
// 6 a │ b
// 7 ──┼───
// 8 l │ x
const document =
    'see [the docs](https://x.dev) now\n'
    '\n'
    '# [Title](https://t.dev)\n'
    '\n'
    '![logo](https://i.dev/logo.png) and [ref]\n'
    '\n'
    '| a | b |\n'
    '|---|---|\n'
    '| [l](https://l.dev) | x |\n'
    '\n'
    '[ref]: https://r.dev\n';

void main() {
  test('a hand over a link, an image, a reference and a link in a table, '
      "the terminal's own elsewhere", () async {
    final run = _Run(const MarkdownView(document));
    await run.settle();
    expect(run.term.mouseTracking, MouseTracking.motion);
    await run.move(0, 0);
    expect(run.shapes(), isEmpty);
    await run.move(4, 0);
    expect(run.shapes(), ['pointer']);
    await run.move(11, 0);
    expect(run.shapes(), isEmpty);
    await run.move(12, 0);
    expect(run.shapes(), ['']);
    await run.move(2, 2);
    expect(run.shapes(), ['pointer'], reason: 'a link in a heading');
    await run.move(2, 3);
    expect(run.shapes(), [''], reason: 'the blank row under it');
    await run.move(3, 4);
    expect(run.shapes(), ['pointer'], reason: 'an image');
    await run.move(6, 4);
    expect(run.shapes(), ['']);
    await run.move(9, 4);
    expect(run.shapes(), ['pointer'], reason: 'a reference defined later');
    await run.move(20, 4);
    expect(run.shapes(), [''], reason: 'right of the text');
    await run.move(0, 8);
    expect(run.shapes(), ['pointer'], reason: 'a link in a table');
    await run.move(4, 8);
    expect(run.shapes(), ['']);
    await run.move(0, 6);
    expect(run.shapes(), isEmpty, reason: 'the header of the table');
    await run.move(0, 8);
    expect(run.shapes(), ['pointer']);
    await run.move(0, 12);
    expect(run.shapes(), [''], reason: 'out of the view');
    await run.quit();
    expect(run.shapes(), isEmpty);
  });

  test('the mouse followed only while the view has a link', () async {
    final key = GlobalKey<_StepsState>();
    final run = _Run(
      _Steps(key: key, const [
        'plain text',
        'plain text and [a link](https://x.dev)\n\nmore',
        // the paragraph with the link kept, not made again
        'plain text and [a link](https://x.dev)\n\nmore words',
        'plain text again',
      ]),
    );
    await run.settle();
    expect(run.term.mouseTracking, MouseTracking.off);
    await run.act(key.currentState!.next);
    expect(run.term.mouseTracking, MouseTracking.motion);
    await run.move(17, 0);
    expect(run.shapes(), ['pointer']);
    await run.move(17, 2);
    expect(run.shapes(), ['']);
    await run.act(key.currentState!.next);
    expect(run.term.mouseTracking, MouseTracking.motion);
    await run.move(16, 0);
    expect(run.shapes(), ['pointer']);
    await run.act(key.currentState!.next);
    expect(run.term.mouseTracking, MouseTracking.off);
    expect(run.shapes(), [''], reason: 'the link gone from under the mouse');
    await run.quit();
  });

  test('nothing followed nor set where the terminal does not show the '
      "pointer's shape", () async {
    final run = _Run(const MarkdownView(document), shapes: false);
    await run.settle();
    // the table's own listener asks for drags
    expect(run.term.mouseTracking, MouseTracking.drags);
    await run.move(4, 0);
    await run.move(12, 0);
    await run.quit();
    expect(run.shapes(), isEmpty);
  });
}
