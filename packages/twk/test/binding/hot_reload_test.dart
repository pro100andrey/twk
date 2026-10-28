// What a hot reload of the app's code (`twk run`) has the binding do:
// ext.twk.reassemble rebuilds every element, the states kept, lays out and
// paints every render object again and writes the whole screen again;
// ext.twk.log puts what the tool says in the app's log, an error opening
// the console; Ctrl+G h and Ctrl+G H ask the tool for a reload or a
// restart.
import 'dart:convert';
import 'dart:developer' show ServiceExtensionResponse;

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

// what the code of the widgets and render objects below reads: a reload
// that changes the code is a change of these that marks nothing
var _label = 'count';
var _fill = '.';
var _width = 3;

/// What [method] answers with [parameters] in [t]'s app, as JSON; a
/// [TestFailure] for an error.
Future<Map<String, Object?>> call(
  TwkTester t,
  String method, [
  Map<String, String> parameters = const {},
]) async {
  final response = await t.binding.callServiceExtension(method, parameters);
  if (response.isError()) {
    fail('$method: ${response.errorCode} ${response.errorDetail}');
  }
  return jsonDecode(response.result!) as Map<String, Object?>;
}

/// The error code and message [method] answers with in [t]'s app.
Future<(int, String)> error(
  TwkTester t,
  String method, [
  Map<String, String> parameters = const {},
]) async {
  final response = await t.binding.callServiceExtension(method, parameters);
  expect(response.isError(), isTrue, reason: '$method answered');
  final detail = jsonDecode(response.errorDetail!) as Map<String, Object?>;
  return (response.errorCode!, detail['message']! as String);
}

void main() {
  setUp(() {
    _label = 'count';
    _fill = '.';
    _width = 3;
  });

  group('ext.twk.reassemble', () {
    testTwk('rebuilds every element with the code changed, the states '
        'kept, and lays out and paints every render object again', (t) async {
      await t.pumpWidget(const _Counter(), size: (20, 4));
      await t.type('++');
      await t.pump();
      expect(t.lines, ['count', '2', '...', '']);
      final builds = _Title.builds;

      _label = 'clicks';
      _fill = '#';
      _width = 5;
      await t.pump();
      expect(t.lines, ['count', '2', '...', ''], reason: 'nothing marked');

      expect(await call(t, 'ext.twk.reassemble'), {'version': 1});
      await t.pump();
      expect(t.lines, ['clicks', '2', '#####', '']);
      expect(_Title.builds, builds + 1);
      await t.type('+');
      await t.pump();
      expect(t.lines, ['clicks', '3', '#####', '']);
    });

    test('before the first frame leaves the app to it', () async {
      final clock = FakeClock();
      final term = clock.run(() => HeadlessTerminal(width: 20, height: 4));
      final binding = clock.run(
        () => AppBinding(term, clock: clock.stopwatch)..reassemble(),
      );
      final ran = clock.run(() => binding.run(const _Counter()));
      await clock.elapse(const Duration(milliseconds: 50));
      binding.quit();
      await clock.elapseUntil(ran);
      expect(utf8.decode(term.frames.first), contains('count'));
    });

    testTwk('writes the whole screen again, what did not change too', (
      t,
    ) async {
      await t.pumpWidget(const _Counter(), size: (20, 4));
      final written = t.terminal.frames.length;
      await call(t, 'ext.twk.reassemble');
      await t.pump();
      final frames = t.terminal.frames.skip(written).map(utf8.decode).join();
      expect(frames, contains('count'));
      expect(frames, contains('...'));
    });

    testTwk('keeps the debug panels shown', (t) async {
      await t.pumpWidget(const _Counter(), size: (40, 12));
      t.binding.debug.console.open();
      t.logs.add(LogRecord(DateTime.now(), LogLevel.info, 'a record'));
      await t.pump();
      expect(t.lines.join('\n'), contains('a record'));
      await call(t, 'ext.twk.reassemble');
      await t.pump();
      expect(t.lines.first, 'count');
      expect(t.lines.join('\n'), contains('a record'));
    });
  });

  group('ext.twk.log', () {
    testTwk("adds a record to the app's log, info by default", (t) async {
      await t.pumpWidget(const _Counter(), size: (20, 4));
      expect(
        await call(t, 'ext.twk.log', {'message': 'reloaded'}),
        {'version': 1},
      );
      await call(t, 'ext.twk.log', {
        'message': 'slow',
        'level': 'warning',
        'error': 'took 3 s',
      });
      final [reloaded, slow] = t.logs.records.toList();
      expect(
        (reloaded.level, reloaded.message, reloaded.error),
        (
          LogLevel.info,
          'reloaded',
          null,
        ),
      );
      expect(
        (slow.level, slow.message, slow.error),
        (
          LogLevel.warning,
          'slow',
          'took 3 s',
        ),
      );
      expect(t.binding.debug.console.isOpen, isFalse);
    });

    testTwk('opens the console on an error', (t) async {
      await t.pumpWidget(const _Counter(), size: (40, 12));
      await call(t, 'ext.twk.log', {
        'message': 'hot reload failed',
        'level': 'error',
        'error': "Expected ';' after this.",
      });
      await t.pump();
      expect(t.binding.debug.console.isOpen, isTrue);
      expect(t.lines.join('\n'), contains('hot reload failed'));
      expect(t.lines.first, 'count', reason: 'the app goes on');
    });

    testTwk('answers a message missing or a level not known with an '
        'error', (t) async {
      await t.pumpWidget(const _Counter(), size: (20, 4));
      expect(await error(t, 'ext.twk.log'), (
        ServiceExtensionResponse.invalidParams,
        'no message',
      ));
      expect(await error(t, 'ext.twk.log', {'message': 'm', 'level': 'loud'}), (
        ServiceExtensionResponse.invalidParams,
        'level: debug, info, warning or error, not loud',
      ));
      expect(t.logs.records, isEmpty);
    });
  });

  group('the hot reload keys', () {
    late List<String> posted;
    late bool listened;
    setUp(() {
      posted = [];
      listened = true;
      final post = AppBinding.postEvent;
      AppBinding.postEvent = (kind, [_ = const {}]) {
        if (listened) {
          posted.add(kind);
        }
        return listened;
      };
      addTearDown(() => AppBinding.postEvent = post);
    });

    testTwk('Ctrl+G h asks the tool for a hot reload, Ctrl+G H for a hot '
        'restart, with or without the kitty keyboard protocol', (t) async {
      await t.pumpWidget(const _Counter(), size: (20, 4));
      t.binding.debug.keys = true;
      await t.press('ctrl+g h');
      await t.press('ctrl+g H');
      // Shift+h as the kitty keyboard protocol reports it
      await t.press('ctrl+g');
      await t.input(utf8.encode('\x1b[104;2u'));
      expect(posted, ['twk.reload', 'twk.restart', 'twk.restart']);
      await t.type('+');
      await t.pump();
      expect(t.lines[1], '1', reason: 'the keys were taken');
    });

    testTwk('only while the debug keys are taken', (t) async {
      await t.pumpWidget(const _Counter(), size: (20, 4));
      await t.press('ctrl+g h');
      expect(posted, isEmpty);
    });

    testTwk('say in the log when no tool listens', (t) async {
      await t.pumpWidget(const _Counter(), size: (20, 4));
      t.binding.debug.keys = true;
      listened = false;
      await t.press('ctrl+g h');
      await t.press('ctrl+g H');
      expect(
        [for (final r in t.logs.records) (r.level, r.message)],
        [
          (LogLevel.warning, 'no hot reload: the app runs without twk run'),
          (LogLevel.warning, 'no hot restart: the app runs without twk run'),
        ],
      );
    });
  });
}

/// [_label] over a count that `+` adds one to, over a [_Bar].
final class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

final class _CounterState extends State<_Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => InputListener(
    onEvent: (event) {
      if (event is! KeyEvent || event.char != '+') {
        return false;
      }
      setState(() => _count++);
      return true;
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const _Title(), Text('$_count'), const _Bar()],
    ),
  );
}

/// [_label], which it reads as it builds; const, so that a rebuild above
/// it does not reach it.
final class _Title extends StatelessWidget {
  const _Title();

  /// How many times one built.
  static var builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return Text(_label);
  }
}

/// A row [_width] cells wide, filled with [_fill]: read as it is laid out
/// and painted.
final class _Bar extends LeafRenderObjectWidget {
  const _Bar();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBar();
}

final class _RenderBar extends RenderObject {
  @override
  bool get isRepaintBoundary => true;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_width);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    canvas.fill(
      0,
      0,
      width,
      height,
      canvas.styles.pen(const Pen(bg: Color.defaultColor)),
      _fill.codeUnitAt(0),
    );
  }
}
