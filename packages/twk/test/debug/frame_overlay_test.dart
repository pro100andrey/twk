// The debug aids of the binding: the keys, taken only while debugging is
// on; the frame overlay, its numbers those the binding and the core
// measured, its own frames and cost left out, shown and hidden without
// repainting the app; the console and the debug paints turned on by the
// keys.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show clipboardSequence;
import 'package:twk_test/twk_test.dart';

import '../binding/harness.dart';

/// [child] under a listener that takes every key and adds it to [keys], as
/// a key binding names it.
Widget listening(List<String> keys, Widget child) => InputListener(
  onEvent: (e) {
    if (e is KeyEvent) {
      keys.add('${KeyCombo.fromEvent(e)}');
    }
    return true;
  },
  child: child,
);

/// A repaint boundary [rows] rows tall, as wide as it may be, filled with
/// [char]; it counts its paints in [count].
final class Area extends LeafRenderObjectWidget {
  const Area(this.char, this.rows, this.count, {super.key});

  final String char;
  final int rows;
  final PaintCount count;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderArea(char, rows, count);
}

final class _RenderArea extends RenderObject {
  _RenderArea(this.char, this.rows, this.count);

  final String char;
  final int rows;
  final PaintCount count;

  @override
  bool get isRepaintBoundary => true;

  @override
  int computeMaxIntrinsicHeight(int width) => rows;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.constrainH(rows);
  }

  @override
  void paint(PaintContext ctx) {
    count.paints++;
    ctx.canvas.fill(
      0,
      0,
      width,
      height,
      ctx.canvas.styles.pen(const Pen()),
      char.codeUnitAt(0),
    );
  }
}

/// Paints counted.
final class PaintCount {
  var paints = 0;
}

/// A repaint boundary one row tall and as wide as it may be that shows
/// [text]: a new text repaints it alone.
final class Line extends LeafRenderObjectWidget {
  const Line(this.text, {super.key});

  final String text;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderLine(text);

  @override
  void updateRenderObject(BuildContext context, RenderLine renderObject) =>
      renderObject.show(text);
}

/// What a [Line] lays out and paints.
final class RenderLine extends RenderObject {
  RenderLine(this._text);

  String _text;

  /// Shows [t] from the next frame on.
  void show(String t) {
    if (t != _text) {
      _text = t;
      markNeedsPaint();
    }
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    final pen = ctx.canvas.styles.pen(const Pen());
    ctx.canvas
      ..fill(0, 0, width, height, pen)
      ..text(0, 0, _text, pen);
  }
}

/// An app whose last row, below the overlay, shows the count of the state
/// of [key].
Widget counter(GlobalKey<ProbeState> key) => Probe(
  key: key,
  (s) => Column(
    children: [
      const Expanded(child: SizedBox()),
      Line('count ${s.count}'),
    ],
  ),
);

/// The numbers the overlay at the right edge of [t]'s screen shows: by the
/// name of each row, the last frame's and the median.
Map<String, (String, String)> shown(TwkTester t) {
  final width = t.terminal.width;
  final x = width - 31;
  return {
    for (final line in t.lines.sublist(2, 12))
      line.padRight(width).substring(x + 1, x + 15).trim(): (
        line.padRight(width).substring(x + 15, x + 22).trim(),
        line.padRight(width).substring(x + 22, x + 30).trim(),
      ),
  };
}

/// The frames a second the overlay shows; null when it is not shown.
int? fps(TwkTester t) {
  final match = RegExp(r'frames +(\d+) fps$').firstMatch(t.lines.first);
  return match == null ? null : int.parse(match[1]!);
}

/// An app that shows a line at the bottom left of the room it gets: in the
/// inline mode, at the bottom of the region.
const bottomLeft = Align(alignment: Alignment.bottomLeft, child: Label('app'));

/// Shows the overlay of [t]'s app with the debug keys, and lets a second
/// pass, so that the next frame of the app shows at once.
Future<void> showOverlay(TwkTester t) async {
  t.binding.debug.keys = true;
  await t.press('ctrl+g o');
  await t.pump(const Duration(seconds: 1));
}

void main() {
  test('a BuildOwner counts the builds of its elements: mounted, dirty and '
      'updated', () {
    final owner = BuildOwner();
    final outer = GlobalKey<ProbeState>();
    final inner = GlobalKey<ProbeState>();
    RootWidget(
      child: Probe(
        key: outer,
        (s) => Probe(key: inner, (s) => Label('${s.count}')),
      ),
    ).attach(owner);
    expect(owner.rebuilds, 3, reason: 'the root and the probes built');
    inner.currentState!.change(() {});
    owner.buildScope();
    expect(owner.rebuilds, 4);
    outer.currentState!.change(() {});
    owner.buildScope();
    expect(owner.rebuilds, 6, reason: 'outer, and inner updated by it');
    owner.buildScope();
    expect(owner.rebuilds, 6);
  });

  // The app is compiled once and run three times: compiled from source on
  // each run, three runs took past 30 s on a loaded machine. The timeout
  // is for the compile, which a loaded machine stretches to tens of
  // seconds; what the app prints does not hang on the time it takes.
  group('TWK_DEBUG', timeout: const Timeout(Duration(minutes: 3)), () {
    late String app;
    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('debug_app');
      addTearDown(() => dir.delete(recursive: true));
      app = '${dir.path}${Platform.pathSeparator}debug_app.dill';
      final res = await runProcess(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        '-o',
        app,
        'test/debug/debug_app.dart',
      ], group: true);
      expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
    });

    /// What debug_app.dart writes under [debug]: on stdout, and on stderr
    /// (the warnings of its log, once it ended).
    Future<(List<String>, String)> runBoth(String debug) async {
      final res = await runProcess(
        Platform.resolvedExecutable,
        [app],
        environment: {'TWK_DEBUG': debug},
      );
      expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
      return (
        const LineSplitter().convert(res.stdout as String),
        res.stderr as String,
      );
    }

    const none = 'overlay false, console false, rainbow false, relayout false';

    /// What debug_app.dart prints under [debug].
    Future<List<String>> run(String debug) async => (await runBoth(debug)).$1;

    test(
      'naming the aids turns them on from the start, and the keys',
      () async {
        final lines = await run('overlay,console,rainbow,relayout');
        expect(
          lines.first,
          'keys true, overlay true, console true, rainbow true, relayout true',
        );
        expect(lines[1], startsWith('app'));
        expect(lines[1], endsWith(' frames${' ' * 18}0 fps'));
        expect(lines, contains(startsWith(' console  debug+')));
      },
    );

    test('keys turns on the keys alone; naming none of the aids, nothing is '
        'on', () async {
      expect((await run('keys')).first, 'keys true, $none');
      final (lines, errors) = await runBoth('timelines');
      expect(lines, ['keys false, $none', 'app']);
      expect(
        errors,
        contains(
          "TWK_DEBUG names nothing it knows as 'timelines': it takes keys, "
          'overlay, console, rainbow, relayout, frames, timeline, logs, '
          'comma-separated',
        ),
      );
    });

    // of the core's, `logs` would serve the log from here and `frames`
    // writes the frames as lines, which the app's emulator refuses
    test(
      "the core's names are known: no warning, and none of the aids",
      () async {
        final (lines, errors) = await runBoth('timeline');
        expect(lines.first, 'keys false, $none');
        expect(errors, isNot(contains('TWK_DEBUG')));
      },
    );
  });

  group('the debug keys', () {
    testTwk('are not taken while debugging is off: Ctrl+G and what follows '
        'go to the app', (t) async {
      final keys = <String>[];
      await t.pumpWidget(listening(keys, const Label('app')), size: (40, 14));
      expect(t.binding.debug.keys, isFalse);
      await t.press('ctrl+g o ctrl+g c ctrl+g r');
      expect(keys, ['ctrl+g', 'o', 'ctrl+g', 'c', 'ctrl+g', 'r']);
      await t.pump();
      expect(fps(t), isNull);
      expect(t.binding.debug.console.isOpen, isFalse);
      expect(t.binding.debug.rainbow, isFalse);
    });

    testTwk('on, Ctrl+G and a key turn the aids on and off before the app '
        'sees them; Ctrl+G twice gives it a Ctrl+G, and any other key '
        'after Ctrl+G is dropped', (t) async {
      final keys = <String>[];
      await t.pumpWidget(listening(keys, const Label('app')), size: (40, 14));
      final debug = t.binding.debug..keys = true;
      await t.press('ctrl+g o');
      await t.pump();
      expect(debug.overlay, isTrue);
      expect(fps(t), isNotNull);
      await t.press('ctrl+g r ctrl+g l');
      expect((debug.rainbow, debug.relayout), (true, true));
      expect(t.binding.twkApp.owner.debugRepaintRainbow, isTrue);
      expect(t.binding.twkApp.owner.debugRelayoutHighlight, isTrue);
      await t.press('ctrl+g r ctrl+g l ctrl+g o');
      await t.pump();
      expect(
        (debug.overlay, debug.rainbow, debug.relayout),
        (
          false,
          false,
          false,
        ),
      );
      expect(fps(t), isNull);
      expect(t.lines.first, 'app');
      expect(keys, isEmpty);
      await t.press('ctrl+g ctrl+g ctrl+g q q');
      expect(keys, ['ctrl+g', 'q']);
    });

    testTwk('open the console over the bottom rows, select, scroll, filter, '
        'copy and close it; while it is open the keys it uses are its own', (
      t,
    ) async {
      final keys = <String>[];
      await t.pumpWidget(listening(keys, const Label('app')), size: (60, 14));
      t.binding.debug.keys = true;
      final time = DateTime(2026, 10, 19, 9, 5, 7, 42);
      for (var i = 0; i < 30; i++) {
        t.logs.add(
          LogRecord(time, i.isEven ? LogLevel.info : LogLevel.debug, 'm$i'),
        );
      }
      await t.press('up ctrl+g c');
      await t.pump();
      expect(keys, ['up']);
      final console = t.binding.debug.console;
      expect(console.isOpen, isTrue);
      expect(t.lines[4], startsWith(' console  debug+  30 of 30'));
      expect(t.lines.last, ' 09:05:07.042 DEBUG m29');
      await t.press('up up up down');
      expect(console.selected!.message, 'm28');
      await t.press('pageup');
      expect(console.below, 9);
      await t.press('end');
      expect(console.below, 0);
      await t.press('ctrl+g f');
      expect(console.level, LogLevel.info);
      expect(console.selected!.message, 'm28');
      final before = t.terminal.frames.length;
      await t.press('ctrl+g y');
      expect(
        t.terminal.frames.skip(before).map(utf8.decode).join(),
        contains(clipboardSequence('${console.selected}')),
      );
      // Enter shows the selected record whole, in twice the rows: here all
      // of the screen; Escape goes back to the list
      await t.press('enter');
      await t.pump();
      expect(console.shownRecord!.message, 'm28');
      expect(t.lines[0], ' 09:05:07.042 INFO  line 1 of 1  esc back');
      expect(t.lines[1], ' m28');
      await t.press('down escape');
      await t.pump();
      expect(console.shownRecord, isNull);
      expect(console.selected!.message, 'm28');
      await t.press('escape');
      expect((console.selected, console.isOpen), (null, true));
      // cleared, it lists what is logged after
      await t.press('ctrl+g x');
      await t.pump();
      expect(console.length, 0);
      expect(t.lines[4], startsWith(' console  info+  0 of 0  30 cleared'));
      t.logs.add(LogRecord(time, LogLevel.info, 'after'));
      await t.pump();
      expect(t.lines[4], startsWith(' console  info+  1 of 1  30 cleared'));
      expect(t.lines[5], ' 09:05:07.042 INFO  after');
      await t.press('escape');
      expect(console.isOpen, isFalse);
      await t.press('up escape');
      expect(keys, ['up', 'up', 'escape']);
      await t.pump();
      expect(t.lines.last, '');
    });

    testTwk('in the inline mode the console goes below the app, the region '
        'growing by it and shrinking once it is closed', (t) async {
      await t.pumpWidget(
        bottomLeft,
        mode: ScreenMode.inline,
        size: (40, 20),
        history: [r'$ run'],
      );
      t.binding.debug
        ..keys = true
        ..console.openOnError = false;
      t.logs.add(LogRecord(DateTime(2026), LogLevel.error, 'boom'));
      await t.press('ctrl+g c');
      await t.pump();
      expect(t.lines.take(4), [
        r'$ run',
        'app',
        ' console  debug+  1 of 1',
        ' 00:00:00.000 ERROR boom',
      ]);
      expect(t.lines[11], '');
      await t.press('escape');
      await t.pump();
      expect(t.lines.take(3), [r'$ run', 'app', '']);
    });

    testTwk('the console made, an error opens it', (t) async {
      await t.pumpWidget(const Label('app'), size: (40, 14));
      final console = t.binding.debug.console;
      expect(console.isOpen, isFalse);
      t.logs.add(LogRecord(DateTime(2026), LogLevel.error, 'boom'));
      await t.pump();
      expect(console.isOpen, isTrue);
      expect(t.lines.sublist(4, 6), [
        ' console  debug+  1 of 1',
        ' 00:00:00.000 ERROR boom',
      ]);
    });

    testTwk('Ctrl+G s saves what the console lists to a file and logs '
        'where', (t) async {
      await t.pumpWidget(const Label('app'), size: (60, 14));
      t.binding.debug.keys = true;
      t.logs.add(LogRecord(DateTime(2026), LogLevel.warning, 'saved'));
      await t.press('ctrl+g s');
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'twk_console_$pid.log';
      addTearDown(() {
        if (File(path).existsSync()) {
          File(path).deleteSync();
        }
      });
      // the file is written on the real clock
      await waitUntil(
        () => _logged(t, path),
        'the console saved to $path',
        between: () => t.pump(Duration.zero),
      );
      expect(t.logs.records.last.message, 'console saved to $path');
      expect(File(path).readAsStringSync(), contains('warning saved'));
    });
  });

  group('the frame overlay', () {
    testTwk('shows the numbers of the last frame of the app as the binding '
        'and the core measured them, in the corner over the app', (t) async {
      final key = GlobalKey<ProbeState>();
      await t.pumpWidget(counter(key), size: (40, 14));
      await showOverlay(t);
      key.currentState!.change(() => key.currentState!.count++);
      await t.pump(Duration.zero);
      final stats = t.binding.twkApp.stats;
      final present = t.binding.twkApp.screen.presenter.stats;
      final expected = {
        'build µs': '${stats.lastBuildMicros}',
        'layout µs': '${stats.lastLayoutMicros}',
        'paint µs': '${stats.lastPaintMicros}',
        'present µs': '${stats.lastPresentMicros}',
        'bytes': '${stats.lastBytes}',
        'cells written': '${present.cellsWritten}',
        'cells compared': '${present.cellsCompared}',
        'rows scrolled': '${present.scrolledRows}',
        'repaints': '${stats.lastRepaints}',
        'rebuilds': '1',
      };
      expect(t.lines.last, 'count 1');
      await t.pump();
      expect({
        for (final MapEntry(:key, :value) in shown(t).entries) key: value.$1,
      }, expected);
      expect(t.lines.first, endsWith(' frames${' ' * 18}1 fps'));
      expect(t.lines[1], endsWith('last  median'));
    });

    testTwk('is described in the render tree with the frames it counted', (
      t,
    ) async {
      final key = GlobalKey<ProbeState>();
      await t.pumpWidget(counter(key), size: (40, 14));
      await showOverlay(t);
      String overlay() {
        var root = key.currentContext!.findRenderObject()!;
        while (root.parent != null) {
          root = root.parent!;
        }
        return root
            .describe()
            .toStringDeep()
            .split('\n')
            .singleWhere((line) => line.contains('RenderFrameOverlay'));
      }

      expect(overlay(), contains('RenderFrameOverlay ‹frames: 1,'));
      // three frames of the app more
      for (var i = 0; i < 3; i++) {
        key.currentState!.change(() => key.currentState!.count++);
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(overlay(), contains('RenderFrameOverlay ‹frames: 4,'));
    });

    testTwk('leaves out the frames it is all of, and asks for one more a '
        'second after the last frame of the app: the frames a second count '
        'the frames of the app alone', (t) async {
      final key = GlobalKey<ProbeState>();
      await t.pumpWidget(counter(key), size: (40, 14));
      await showOverlay(t);
      for (var i = 0; i < 5; i++) {
        key.currentState!.change(() => key.currentState!.count++);
        await t.pump();
      }
      final bytes = '${t.binding.twkApp.stats.lastBytes}';
      await t.pump(const Duration(milliseconds: 300));
      expect(fps(t), 5);
      final frames = t.terminal.frames.length;
      expect(shown(t)['bytes']!.$1, bytes);
      expect(shown(t)['repaints']!.$1, '1');
      await t.pump(const Duration(seconds: 1));
      expect(t.terminal.frames.length, frames + 1);
      expect(fps(t), 0, reason: 'its own frames are not counted');
      expect(shown(t)['bytes']!.$1, bytes);
      await t.pumpUntilIdle();
      expect(t.terminal.frames.length, frames + 1);
    });

    testTwk('counts the frames of the app it shows new numbers in, less its '
        'own layout, paint and bytes: an app that works on its refreshes '
        'alone is in the medians', (t) async {
      final outer = GlobalKey<ProbeState>();
      final inner = GlobalKey<ProbeState>();
      await t.pumpWidget(
        Probe(
          key: outer,
          (o) => Column(
            children: [
              const Expanded(child: SizedBox()),
              Probe(key: inner, (i) => Line('count ${o.count} ${i.count}')),
            ],
          ),
        ),
        size: (40, 14),
      );
      await showOverlay(t);
      // a frame of the app, which the overlay shows a second after
      inner.currentState!.change(() => inner.currentState!.count++);
      var ticks = 0;
      // then the app works a second after each of its frames, as the
      // overlay refreshes: its timer is the older, so the two are one frame
      void tick() {
        outer.currentState!.change(() => outer.currentState!.count++);
        if (++ticks < 4) {
          // tick runs only from a timer on the tester's clock, so this one is
          // on it too
          // ignore: twk_lints/wall_time_in_tests
          Timer(const Duration(seconds: 1), tick);
        }
      }

      // on the tester's clock
      t.clock.run(() => Timer(const Duration(seconds: 1), tick));
      await t.pump(const Duration(milliseconds: 500));
      final small = shown(t);
      final frames = t.terminal.frames.length;
      final stats = t.binding.twkApp.stats;
      final present = t.binding.twkApp.screen.presenter.stats;
      // up to each frame of the app; the last one's numbers
      await t.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(seconds: 1));
      }
      expect(t.lines.last, 'count 4 1');
      final (bytes, written, compared, paint) = (
        stats.lastBytes,
        present.cellsWritten,
        present.cellsCompared,
        stats.lastPaintMicros,
      );
      expect(stats.lastRepaints, 2, reason: 'the app and the overlay marked');
      await t.pump(const Duration(seconds: 2));
      final numbers = shown(t);
      final rebuilds = numbers['rebuilds']!;
      expect(rebuilds.$1, isNot(small['rebuilds']!.$1), reason: 'a refresh');
      expect(rebuilds.$2, rebuilds.$1, reason: 'the medians: 4 of 6 frames');
      expect(numbers['repaints']!.$1, '1', reason: "the overlay's mark off");
      // the frames of the app were the overlay's, one more after each a
      // quarter of a second on showing what was counted in it, and one a
      // second after the last
      expect(t.terminal.frames.length, frames + 9);
      // of the app's line, as many cells as its frame of its own
      expect(numbers['cells written']!.$1, small['cells written']!.$1);
      expect(int.parse(numbers['cells written']!.$1), lessThan(written));
      expect(numbers['cells compared']!.$1, small['cells compared']!.$1);
      expect(int.parse(numbers['cells compared']!.$1), lessThan(compared));
      expect(int.parse(numbers['bytes']!.$1), inInclusiveRange(1, bytes - 1));
      expect(int.parse(numbers['paint µs']!.$1), lessThan(paint));
      expect(fps(t), 0);
    });

    testTwk('painted over again as it was where the app repainted under it, '
        'it takes its own paint off that frame', (t) async {
      final top = GlobalKey<ProbeState>();
      final bottom = GlobalKey<ProbeState>();
      await t.pumpWidget(
        Column(
          children: [
            Expanded(
              child: Probe(
                key: top,
                (s) => Align(
                  alignment: Alignment.topRight,
                  child: Label('under ${s.count}'),
                ),
              ),
            ),
            // two rows: the label above, under the overlay, has the rest
            SizedBox(height: 2, child: counter(bottom)),
          ],
        ),
        size: (40, 14),
      );
      await showOverlay(t);
      // a frame counted, not shown yet
      bottom.currentState!.change(() => bottom.currentState!.count++);
      await t.pump();
      bottom.currentState!.change(() => bottom.currentState!.count++);
      await t.pump();
      top.currentState!.change(() => top.currentState!.count++);
      await t.pump();
      final stats = t.binding.twkApp.stats;
      expect(stats.lastRepaints, 1, reason: 'the root, the overlay with it');
      expect(stats.lastBytes, 0, reason: 'the label under it, it as it was');
      final paint = stats.lastPaintMicros;
      await t.pump(const Duration(milliseconds: 300));
      expect(shown(t)['bytes']!.$1, '0');
      expect(int.parse(shown(t)['paint µs']!.$1), lessThan(paint));
    });

    testTwk('shown, it shows the last frame of the app at once', (t) async {
      await t.pumpWidget(const Label('app'), size: (40, 14));
      final stats = t.binding.twkApp.stats;
      final expected = {
        'build µs': '${stats.lastBuildMicros}',
        'layout µs': '${stats.lastLayoutMicros}',
        'paint µs': '${stats.lastPaintMicros}',
        'bytes': '${stats.lastBytes}',
      };
      t.binding.debug.keys = true;
      await t.press('ctrl+g o');
      await t.pump();
      final numbers = shown(t);
      expect({
        for (final key in expected.keys) key: numbers[key]!.$1,
      }, expected);
      expect(int.parse(numbers['rebuilds']!.$1), greaterThan(0));
    });

    testTwk('a repaint boundary of the app under it repaints on its own, and '
        'it is painted over it again', (t) async {
      final key = GlobalKey<ProbeState>();
      await t.pumpWidget(
        Probe(key: key, (s) => Line('line ${s.count}')),
        size: (40, 14),
      );
      await showOverlay(t);
      final header = t.lines.first;
      expect(header, startsWith('line 0    frames'));
      key.currentState!.change(() => key.currentState!.count++);
      await t.pump(Duration.zero);
      expect(t.binding.twkApp.stats.lastRepaints, 1);
      expect(t.lines.first, header.replaceFirst('0', '1'));
    });

    testTwk('is shown and hidden without repainting the app, but for the '
        'smallest repaint boundary under it once it is hidden', (t) async {
      final under = PaintCount();
      final below = PaintCount();
      await t.pumpWidget(
        Column(
          children: [Area('u', 12, under), Area('b', 2, below)],
        ),
        size: (40, 14),
      );
      expect((under.paints, below.paints), (1, 1));
      t.binding.debug.keys = true;
      await t.press('ctrl+g o');
      await t.pump();
      expect(fps(t), isNotNull);
      expect(t.lines[5], startsWith('u' * 9));
      expect((under.paints, below.paints), (1, 1));
      await t.press('ctrl+g o');
      await t.pump();
      expect(fps(t), isNull);
      expect(t.lines.take(12), everyElement('u' * 40));
      expect((under.paints, below.paints), (2, 1));
    });

    testTwk('in the inline mode the region grows to hold it, and shrinks '
        'once it is hidden', (t) async {
      await t.pumpWidget(
        bottomLeft,
        mode: ScreenMode.inline,
        size: (40, 20),
        history: [r'$ run'],
      );
      expect(t.lines.take(3), [r'$ run', 'app', '']);
      t.binding.debug.keys = true;
      await t.press('ctrl+g o');
      await t.pump();
      expect(t.lines[1], '${' ' * 10}frames${' ' * 18}0 fps');
      expect(t.lines[12], startsWith('app       rebuilds'));
      await t.press('ctrl+g o');
      await t.pump();
      expect(t.lines.take(3), [r'$ run', 'app', '']);
    });
  });
}

bool _logged(TwkTester t, String path) =>
    t.logs.records.any((r) => r.message.contains(path));
