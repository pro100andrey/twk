// The console over a log sink: records listed as they are logged, in the
// colors of their levels; the level filter, scrolling, selection, copying
// to the clipboard and saving; opening on an error; the overlay in either
// screen mode and in an app; and a burst of records, after which a frame
// formats only the records it shows.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/src/debug/console.dart' show RenderConsolePanel;
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show Multiplexer, clipboardSequence;
import 'package:twk_test/twk_test.dart' show FakeClock, Shot;
import 'package:twk_test/vt_terminal.dart';

import '../binding/harness.dart';
import '../data/shot.dart' show Counted, PaintCount;
import '../layout/view.dart' show View;

final _at = DateTime(2026, 10, 19, 9, 5, 7, 42);

/// A record logged at 09:05:07.042.
LogRecord record(
  String message, {
  LogLevel level = LogLevel.info,
  Object? error,
  StackTrace? stack,
}) => LogRecord(_at, level, message, error: error, stack: stack);

/// A sink holding [messages] logged at info, keeping the last [capacity].
LogSink sinkOf(List<String> messages, {int capacity = 1000}) {
  final sink = LogSink(capacity: capacity);
  for (final m in messages) {
    sink.add(record(m));
  }
  return sink;
}

/// The row a record of [text] at [level] shows as.
String row(String level, String text) =>
    ' 09:05:07.042 ${level.padRight(5)} $text';

/// The console of [controller], opened, over a screen [rows] rows tall and
/// [width] wide, in [theme].
Shot panel(
  ConsoleController controller, {
  int width = 40,
  int rows = 5,
  ThemeData theme = ThemeData.dark,
}) {
  controller.open();
  final shown = Shot(
    Theme(
      data: theme,
      child: Console(
        controller: controller,
        rows: rows,
        child: const SizedBox(),
      ),
    ),
    width,
    rows,
  );
  expect(shown.vt.errors, isEmpty);
  return shown;
}

/// Counts how many times the errors that share it are formatted.
final class Formats {
  var count = 0;
}

/// An error that counts its formatting in [formats].
final class CountedError {
  CountedError(this.formats);

  final Formats formats;

  @override
  String toString() {
    formats.count++;
    return 'e';
  }
}

/// A widget whose build throws.
final class Throws extends StatelessWidget {
  const Throws();

  @override
  Widget build(BuildContext context) => throw StateError('boom');
}

void main() {
  group('records', () {
    test('are listed as they are logged, oldest first, each with its time, '
        'level and message', () {
      final sink = sinkOf(['started']);
      final shot = panel(ConsoleController(sink));
      expect(shot.rows, [
        ' console  debug+  1 of 1',
        row('INFO', 'started'),
        '',
        '',
        '',
      ]);
      sink
        ..add(record('slow frame', level: LogLevel.warning, error: '40 ms'))
        ..add(record('gone', level: LogLevel.error))
        ..add(record('detail', level: LogLevel.debug));
      shot.frame();
      expect(shot.rows, [
        ' console  debug+  4 of 4',
        row('INFO', 'started'),
        row('WARN', 'slow frame: 40 ms'),
        row('ERROR', 'gone'),
        row('DEBUG', 'detail'),
      ]);
    });

    test('show the first line of the message and of its error, cut at the '
        'edge, and at their end what they leave out: more lines, a stack', () {
      final sink = LogSink()
        ..add(record('one\ntwo'))
        ..add(
          record(
            'failed',
            level: LogLevel.error,
            error: 'boom\nat main',
            stack: StackTrace.current,
          ),
        )
        ..add(record('a long message'));
      expect(panel(ConsoleController(sink), width: 32, rows: 4).rows, [
        ' console  debug+  3 of 3',
        '${row('INFO', 'one')}      +1',
        '${row('ERROR', 'fa')} +1 stack',
        row('INFO', 'a long messa'),
      ]);
    });

    test('are drawn in the theme: the level in its color, the time muted, '
        'the message in the text color, on the surface; the header is '
        'underlined, its title bold', () {
      const t = ThemeData.dark;
      final sink = LogSink();
      for (final level in LogLevel.values) {
        sink.add(record('m', level: level));
      }
      final shot = panel(ConsoleController(sink));
      final bg = t.surface.bg!;
      expect(shot.colors(0)[1], ('c', t.primary.fg!, bg));
      expect(shot.attrs(0)[1] & Attr.bold, Attr.bold);
      expect(shot.attrs(0)[30] & Attr.underlineMask, Attr.underline);
      for (final (y, color) in [
        (1, t.muted.fg!),
        (2, t.info.fg!),
        (3, t.warning.fg!),
        (4, t.error.fg!),
      ]) {
        final cells = shot.colors(y);
        expect(cells[1], ('0', t.muted.fg!, bg));
        expect((cells[14].$2, cells[14].$3), (color, bg));
        expect(cells[20], ('m', t.text.fg!, bg));
        expect(cells[39].$3, bg);
      }
    });

    test('drop out with the oldest records of the sink', () {
      final sink = sinkOf(['a', 'b'], capacity: 3);
      final controller = ConsoleController(sink);
      final shot = panel(controller);
      sink
        ..add(record('c'))
        ..add(record('d'));
      shot.frame();
      expect(shot.rows, [
        ' console  debug+  3 of 3',
        row('INFO', 'b'),
        row('INFO', 'c'),
        row('INFO', 'd'),
        '',
      ]);
      expect((controller.kept, controller.length), (3, 3));
      expect(controller.recordAt(0).message, 'b');
    });

    test('are no longer taken once the controller is disposed', () {
      final sink = sinkOf(['a']);
      final controller = ConsoleController(sink)..dispose();
      sink.add(record('b'));
      expect(controller.kept, 1);
    });
  });

  group('the level filter', () {
    test('lists the records at its level and above, counted in the header, '
        'those logged later too', () {
      final sink = LogSink();
      for (final level in LogLevel.values) {
        sink.add(record(level.name, level: level));
      }
      final controller = ConsoleController(sink, level: LogLevel.warning);
      final shot = panel(controller);
      expect(shot.rows, [
        ' console  warning+  2 of 4',
        row('WARN', 'warning'),
        row('ERROR', 'error'),
        '',
        '',
      ]);
      controller.level = LogLevel.info;
      shot.frame();
      expect(shot.rows, [
        ' console  info+  3 of 4',
        row('INFO', 'info'),
        row('WARN', 'warning'),
        row('ERROR', 'error'),
        '',
      ]);
      sink
        ..add(record('later', level: LogLevel.debug))
        ..add(record('later', level: LogLevel.error));
      shot.frame();
      expect(shot.rows, [
        ' console  info+  4 of 6',
        row('INFO', 'info'),
        row('WARN', 'warning'),
        row('ERROR', 'error'),
        row('ERROR', 'later'),
      ]);
      expect(controller.length, 4);
      expect(controller.recordAt(3).level, LogLevel.error);
    });

    test('deselects the selected record when it hides it', () {
      final sink = LogSink()
        ..add(record('w', level: LogLevel.warning))
        ..add(record('i'));
      final controller = ConsoleController(sink)..selectPrevious();
      expect(controller.selected?.message, 'i');
      controller.level = LogLevel.warning;
      expect(controller.selected, isNull);
      controller
        ..selectPrevious()
        ..level = LogLevel.debug;
      expect(controller.selected?.message, 'w');
    });
  });

  group('scrolling', () {
    test('follows the newest record until scrolled back, keeps the records '
        'shown as more come, stops at the oldest and follows again at the '
        'end', () {
      final sink = sinkOf(['0', '1', '2', '3', '4', '5']);
      final controller = ConsoleController(sink);
      final shot = panel(controller, rows: 4);
      expect(shot.rows.skip(1), [
        row('INFO', '3'),
        row('INFO', '4'),
        row('INFO', '5'),
      ]);
      controller.scrollBy(-2);
      shot.frame();
      expect(controller.below, 2);
      expect(shot.rows, [
        ' console  debug+  6 of 6  2 below',
        row('INFO', '1'),
        row('INFO', '2'),
        row('INFO', '3'),
      ]);
      sink.add(record('6'));
      shot.frame();
      expect(shot.rows, [
        ' console  debug+  7 of 7  3 below',
        row('INFO', '1'),
        row('INFO', '2'),
        row('INFO', '3'),
      ]);
      controller.scrollBy(-10);
      shot.frame();
      expect(controller.below, 4);
      expect(shot.rows.skip(1), [
        row('INFO', '0'),
        row('INFO', '1'),
        row('INFO', '2'),
      ]);
      controller.scrollBy(1);
      shot.frame();
      expect(shot.rows[1], row('INFO', '1'));
      controller.scrollBy(10);
      sink.add(record('7'));
      shot.frame();
      expect(controller.below, 0);
      expect(shot.rows, [
        ' console  debug+  8 of 8',
        row('INFO', '5'),
        row('INFO', '6'),
        row('INFO', '7'),
      ]);
      controller.scrollBy(-3);
      expect(controller.below, 3);
      controller.scrollToEnd();
      expect(controller.below, 0);
    });

    test('lists fewer records than rows from the top', () {
      final controller = ConsoleController(sinkOf(['0', '1']));
      final shot = panel(controller, rows: 4);
      controller.scrollBy(-1);
      shot.frame();
      expect(controller.below, 0);
      expect(shot.rows, [
        ' console  debug+  2 of 2',
        row('INFO', '0'),
        row('INFO', '1'),
        '',
      ]);
    });
  });

  group('selection', () {
    test('starts at the bottom row, moves a record at a time, keeps the '
        'selected record in view, and shows it in the selection style', () {
      const t = ThemeData.dark;
      final controller = ConsoleController(
        sinkOf(['0', '1', '2', '3', '4', '5']),
      );
      final shot = panel(controller, rows: 4);
      controller.selectPrevious();
      shot.frame();
      expect(controller.selected?.message, '5');
      expect(shot.colors(3)[20], ('5', t.text.fg!, t.selection.bg!));
      expect(shot.colors(3)[39].$3, t.selection.bg);
      expect(shot.colors(2)[20], ('4', t.text.fg!, t.surface.bg!));
      for (var i = 0; i < 3; i++) {
        controller.selectPrevious();
      }
      shot.frame();
      expect(controller.selected?.message, '2');
      expect(controller.below, 1);
      expect(shot.rows.skip(1), [
        row('INFO', '2'),
        row('INFO', '3'),
        row('INFO', '4'),
      ]);
      expect(shot.colors(1)[20].$3, t.selection.bg);
      expect(shot.colors(3)[20].$3, t.surface.bg);
      for (var i = 0; i < 5; i++) {
        controller.selectNext();
      }
      shot.frame();
      expect(controller.selected?.message, '5');
      expect(controller.below, 0);
      controller.deselect();
      shot.frame();
      expect(controller.selected, isNull);
      expect(shot.colors(3)[20].$3, t.surface.bg);
    });

    test('with none selected, selectNext starts at the top row; '
        'selectPrevious stops at the oldest record', () {
      final controller = ConsoleController(
        sinkOf(['0', '1', '2', '3', '4', '5']),
      );
      final shot = panel(controller, rows: 4);
      controller.selectNext();
      expect(controller.selected?.message, '3');
      for (var i = 0; i < 9; i++) {
        controller.selectPrevious();
      }
      shot.frame();
      expect(controller.selected?.message, '0');
      expect(shot.rows[1], row('INFO', '0'));
    });

    test('a selected record that drops out of the sink is deselected', () {
      final sink = sinkOf(['a', 'b', 'c'], capacity: 3);
      final controller = ConsoleController(sink);
      for (var i = 0; i < 3; i++) {
        controller.selectPrevious();
      }
      expect(controller.selected?.message, 'a');
      sink.add(record('d'));
      expect(controller.selected, isNull);
    });
  });

  group('copy', () {
    test('puts the selected record on the clipboard as OSC 52, as the log '
        'writes it, error and stack too', () {
      final r = record(
        'failed',
        level: LogLevel.error,
        error: 'boom',
        stack: StackTrace.fromString('#0 main (app.dart:1:1)'),
      );
      final controller =
          ConsoleController(
              LogSink()
                ..add(r)
                ..add(record('after')),
            )
            ..selectPrevious()
            ..selectPrevious();
      final term = HeadlessTerminal();
      expect(controller.copy(term), isTrue);
      expect(term.frames, [utf8.encode(clipboardSequence('$r'))]);
      expect('$r', contains('#0 main'));
    });

    test('inside a multiplexer, wraps it for the multiplexer', () {
      final controller = ConsoleController(sinkOf(['a']))..selectPrevious();
      final term = HeadlessTerminal(multiplexer: Multiplexer.tmux);
      expect(controller.copy(term), isTrue);
      expect(term.frames, [
        utf8.encode(
          clipboardSequence(
            '${controller.selected}',
            multiplexer: Multiplexer.tmux,
          ),
        ),
      ]);
    });

    test('writes nothing with no record selected', () {
      final controller = ConsoleController(sinkOf(['a']));
      final term = HeadlessTerminal();
      expect(controller.copy(term), isFalse);
      expect(term.frames, isEmpty);
    });
  });

  group('clear', () {
    test('lists what is taken after it, counts what it cleared, and keeps '
        'to it when the level changes', () {
      final sink = sinkOf(['a', 'b', 'c']);
      final controller = ConsoleController(sink)
        ..selectPrevious()
        ..clear();
      final shot = panel(controller);
      expect(controller.selected, isNull);
      expect(shot.rows.first, ' console  debug+  0 of 0  3 cleared');
      sink
        ..add(record('d'))
        ..add(record('e', level: LogLevel.debug));
      shot.frame();
      expect(shot.rows.take(3), [
        ' console  debug+  2 of 2  3 cleared',
        row('INFO', 'd'),
        row('DEBUG', 'e'),
      ]);
      controller.level = LogLevel.info;
      shot.frame();
      expect(shot.rows.take(3), [
        ' console  info+  1 of 2  3 cleared',
        row('INFO', 'd'),
        '',
      ]);
      // the sink keeps them all
      expect(sink.records.map((r) => r.message), ['a', 'b', 'c', 'd', 'e']);
    });

    test('counts no more what dropped out of the sink', () {
      final sink = sinkOf(['a', 'b', 'c'], capacity: 4);
      final controller = ConsoleController(sink)..clear();
      expect(controller.cleared, 3);
      sink
        ..add(record('d'))
        ..add(record('e'))
        ..add(record('f'));
      expect((controller.cleared, controller.length), (1, 3));
    });
  });

  group('save', () {
    test('writes the records listed, oldest first, as the log file keeps '
        'them, in place of what the file held', () async {
      final dir = Directory.systemTemp.createTempSync('twk_console');
      addTearDown(() => dir.deleteSync(recursive: true));
      final saved = File('${dir.path}/saved.log')..writeAsStringSync('old\n');
      final logged = LogSink(path: '${dir.path}/app.log');
      final sink = LogSink();
      final records = [
        record('a'),
        record('b', level: LogLevel.warning, error: 'x\ny'),
        record('c', level: LogLevel.debug),
        record('d', level: LogLevel.error, stack: StackTrace.current),
      ];
      for (final r in records) {
        sink.add(r);
        if (r.level != LogLevel.debug) {
          logged.add(r);
        }
      }
      await ConsoleController(sink, level: LogLevel.info).save(saved.path);
      expect(
        saved.readAsStringSync(),
        File('${dir.path}/app.log').readAsStringSync(),
      );
      expect(saved.readAsStringSync(), startsWith('09:05:07.042 info a\n'));
    });
  });

  group('opening on an error', () {
    test('opens the console when asked to, on an error only', () {
      final sink = LogSink();
      final quiet = ConsoleController(sink);
      final controller = ConsoleController(sink, openOnError: true);
      sink.add(record('w', level: LogLevel.warning));
      expect(controller.isOpen, isFalse);
      sink.add(record('e', level: LogLevel.error));
      expect(controller.isOpen, isTrue);
      expect(quiet.isOpen, isFalse);
    });

    test('follows the newest record, so that the error shows', () {
      final sink = sinkOf(['0', '1', '2', '3', '4']);
      final controller = ConsoleController(sink, openOnError: true);
      final shot = panel(controller, rows: 3);
      controller
        ..scrollBy(-2)
        ..close();
      shot.frame();
      sink.add(record('e', level: LogLevel.error));
      expect((controller.isOpen, controller.below), (true, 0));
      shot.frame();
      expect(shot.rows.last, row('ERROR', 'e'));
    });
  });

  group('Console', () {
    test('full screen, covers the bottom rows of its child while open; '
        'closed, the child shows whole', () {
      final controller = ConsoleController(sinkOf(['hello']));
      final dots = '.' * 30;
      final v = View(30, 6)
        ..pump(
          Console(controller: controller, rows: 3, child: const Fill('.')),
        );
      expect(v.rows(), List.filled(6, dots));
      controller.toggle();
      v.frame();
      expect(controller.isOpen, isTrue);
      expect(v.rows(), [
        dots,
        dots,
        dots,
        ' console  debug+  1 of 1',
        row('INFO', 'hello'),
        '',
      ]);
      controller.toggle();
      v.frame();
      expect(controller.isOpen, isFalse);
      expect(v.rows(), List.filled(6, dots));
    });

    test('is at most as tall as the child', () {
      final controller = ConsoleController(sinkOf(['hello']))..open();
      final v = View(30, 2)
        ..pump(
          Console(controller: controller, rows: 12, child: const Fill('.')),
        );
      expect(v.rows(), [' console  debug+  1 of 1', row('INFO', 'hello')]);
    });

    test('rebuilt with other rows, resizes; in another theme, repaints in '
        'it', () {
      final controller = ConsoleController(sinkOf(['hello']))..open();
      Widget console(int rows, ThemeData theme) => Theme(
        data: theme,
        child: Console(
          controller: controller,
          rows: rows,
          child: const Fill('.'),
        ),
      );
      final dots = '.' * 30;
      final shown = Shot(console(2, ThemeData.dark), 30, 4);
      expect(shown.rows, [
        dots,
        dots,
        ' console  debug+  1 of 1',
        row('INFO', 'hello'),
      ]);
      shown.pump(console(3, ThemeData.dark));
      expect(shown.rows, [
        dots,
        ' console  debug+  1 of 1',
        row('INFO', 'hello'),
        '',
      ]);
      expect(shown.colors(2)[1].$3, ThemeData.dark.surface.bg);
      shown.pump(console(3, ThemeData.nord));
      expect(shown.colors(2)[1].$3, ThemeData.nord.surface.bg);
      expect(shown.colors(2)[14].$2, ThemeData.nord.info.fg);
    });

    test('rebuilt with another controller, lists its records and hears the '
        'old one no more', () {
      final old = ConsoleController(sinkOf(['old']))..open();
      final next = ConsoleController(sinkOf(['next']))..open();
      final v = View(30, 3)
        ..pump(Console(controller: old, rows: 2, child: const Fill('.')));
      expect(v.rows().last, row('INFO', 'old'));
      v.pump(Console(controller: next, rows: 2, child: const Fill('.')));
      expect(v.rows().last, row('INFO', 'next'));
      final panel = _panelOf(v.root);
      expect(panel.controller, same(next));
      expect(old.hasListeners, isFalse);
      old.sink.add(record('later'));
      v.frame();
      expect(v.rows().last, row('INFO', 'next'));
      next.sink.add(record('newer'));
      v.frame();
      expect(v.rows().last, row('INFO', 'newer'));
    });

    test('its panel is as tall as its rows while open, at least, and takes '
        'no room closed; it says so when described', () {
      final controller = ConsoleController(sinkOf(['hello']));
      final v = View(30, 6)
        ..pump(
          Theme(
            data: ThemeData.nord,
            child: Console(
              controller: controller,
              rows: 3,
              child: const Fill('.'),
            ),
          ),
        );
      final panel = _panelOf(v.root);
      expect((panel.rows, panel.theme), (3, ThemeData.nord));
      expect(panel.getMinIntrinsicHeight(30), 0);
      expect(panel.getMaxIntrinsicHeight(30), 0);
      expect('${panel.describe()}', contains('rows: 3'));
      expect('${panel.describe()}', isNot(contains('open')));
      controller.open();
      v.frame();
      expect(panel.getMinIntrinsicHeight(30), 3);
      expect(panel.getMaxIntrinsicHeight(30), 3);
      expect('${panel.describe()}', contains('open'));
    });

    test('opening and closing neither rebuilds the child nor loses its '
        'state; a record repaints the panel alone', () {
      final sink = sinkOf(['hello']);
      final controller = ConsoleController(sink);
      final key = GlobalKey<ProbeState>();
      final count = PaintCount();
      final v = View(30, 6)
        ..pump(
          Console(
            controller: controller,
            rows: 3,
            child: Probe(key: key, (_) => Counted(count)),
          ),
        );
      final state = key.currentState!;
      controller.open();
      v.frame();
      controller
        ..close()
        ..open();
      v.frame();
      expect(key.currentState, same(state));
      expect(state.builds, 1);
      final paints = count.paints;
      sink.add(record('more'));
      v.frame();
      expect(v.rows().last, row('INFO', 'more'));
      expect(count.paints, paints);
    });

    test('in the inline mode goes below the app, and the region grows by '
        'it', () async {
      final sink = sinkOf(['hello']);
      final controller = ConsoleController(sink);
      final clock = FakeClock();
      final term = clock.run(
        () => VtTerminal(width: 30, height: 7, history: [r'$ app']),
      );
      final key = GlobalKey<ProbeState>();
      final binding = clock.run(
        () => AppBinding(
          term,
          maxFps: 1000,
          logs: sink,
          clock: clock.stopwatch,
        ),
      );
      final done = clock.run(
        () => binding.run(
          Probe(
            key: key,
            (_) => Console(
              controller: controller,
              rows: 3,
              child: const Label('app'),
            ),
          ),
        ),
      );
      await clock.settle();
      expect(term.lines, [r'$ app', 'app', '', '', '', '', '']);
      controller.open();
      await clock.settle();
      expect(term.lines, [
        r'$ app',
        'app',
        ' console  debug+  1 of 1',
        row('INFO', 'hello'),
        '',
        '',
        '',
      ]);
      AppBinding.of(key.currentContext!).quit();
      await clock.elapseUntil(done);
    });

    test('in an app, lists the records as they are logged, and opens on '
        'the error a build logs', () async {
      late ConsoleController controller;
      final key = GlobalKey<ProbeState>();
      final run = Run(
        Probe(
          key: key,
          (s) => Console(
            controller: controller,
            rows: 4,
            child: s.count == 0 ? const Label('app') : const Throws(),
          ),
        ),
        width: 120,
        height: 6,
      );
      controller = ConsoleController(run.logs, openOnError: true);
      await run.settle();
      expect(run.rows, ['app', '', '', '', '', '']);
      run.logs.add(record('hello'));
      await run.settle();
      expect(run.rows, ['app', '', '', '', '', '']);
      key.currentState!.change(() => key.currentState!.count++);
      await run.settle();
      expect(controller.isOpen, isTrue);
      expect(run.rows[2], ' console  debug+  2 of 2');
      expect(run.rows[3], row('INFO', 'hello'));
      expect(run.rows[4], contains('ERROR'));
      expect(run.rows[4], contains('Throws failed to build: Bad state: boom'));
      run.logs.add(record('live'));
      await run.settle();
      expect(run.rows[5], row('INFO', 'live'));
      run.term.type('\x03');
      await run.ended();
    });
  });

  group('a burst of 10k records', () {
    test('the next frame formats only the records it shows, wherever it '
        'is scrolled to', () {
      final formats = Formats();
      final sink = LogSink(capacity: 10000);
      final controller = ConsoleController(sink);
      final shot = panel(controller, rows: 6, width: 60);
      for (var i = 0; i < 10000; i++) {
        sink.add(record('$i', error: CountedError(formats)));
      }
      shot.frame();
      expect(formats.count, 5);
      expect(shot.rows.first, ' console  debug+  10000 of 10000');
      expect(shot.rows.last, row('INFO', '9999: e'));
      formats.count = 0;
      controller.scrollBy(-10000);
      shot.frame();
      expect(formats.count, 5);
      expect(shot.rows[1], row('INFO', '0: e'));
      formats.count = 0;
      controller.level = LogLevel.warning;
      shot.frame();
      expect(formats.count, 0);
      expect(shot.rows.first, ' console  warning+  0 of 10000');
    });

    test('through a sink that keeps fewer, the console keeps what the sink '
        'keeps', () {
      final sink = LogSink();
      final controller = ConsoleController(sink);
      final shot = panel(controller, rows: 3);
      for (var i = 0; i < 10000; i++) {
        sink.add(record('$i'));
      }
      shot.frame();
      expect(shot.rows, [
        ' console  debug+  1000 of 1000',
        row('INFO', '9998'),
        row('INFO', '9999'),
      ]);
      controller.scrollBy(-10000);
      shot.frame();
      expect(shot.rows[1], row('INFO', '9000'));
    });
  });
}

/// The render object of the console panel below [root].
RenderConsolePanel _panelOf(Element root) {
  RenderConsolePanel? found;
  void visit(Element e) {
    if (e.renderObject case final RenderConsolePanel panel) {
      found ??= panel;
    }
    e.visitChildren(visit);
  }

  visit(root);
  return found!;
}
