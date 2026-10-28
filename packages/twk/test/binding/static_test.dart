// Static: in the inline mode each item goes to the terminal's history once,
// in order, built under the widgets above it and laid out at the
// terminal's width, then unmounted, and the region fits what is left; in
// the fullscreen mode the items stay in place, one below another. Either
// way an item is built once.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show FakeClock, FakeStderr;
import 'package:twk_test/vt_terminal.dart';

import 'harness.dart';

void main() {
  test('in the inline mode each item goes to the history above the region '
      'once, in order, as the list grows', () async {
    final items = <String>[];
    final built = <String>[];
    final run = _Inline(
      (_) => column([
        Static<String>(
          items: [...items],
          builder: (_, item) {
            built.add(item);
            return Label(item);
          },
        ),
        const Label('> prompt'),
      ]),
      history: [r'$ app'],
    );
    await run.settle();
    expect(run.term.lines, [r'$ app', '> prompt', '', '']);
    run.state.change(() => items.addAll(['one', 'two']));
    await run.settle();
    expect(run.term.lines, [r'$ app', 'one', 'two', '> prompt']);
    run.state.change(() => items.addAll(['three', 'four', 'five']));
    await run.settle();
    // the history scrolls up into the scrollback
    expect(run.term.lines, [
      r'$ app',
      'one',
      'two',
      'three',
      'four',
      'five',
      '> prompt',
    ]);
    run.state.change(() {});
    await run.settle();
    expect(built, ['one', 'two', 'three', 'four', 'five']);
    await run.quit();
    expect(run.term.lines.skip(6), ['> prompt', '']);
  });

  test('the frame that writes an item fits the region to what it shows '
      'then: the rows of what left it in the same build take the item, '
      'the history not scrolled; without a commit the region keeps its '
      'rows', () async {
    var live = ['a1', 'a2', 'a3'];
    final items = <String>[];
    final run = _Inline(
      (_) => column([
        Static<String>(items: [...items], builder: (_, item) => Label(item)),
        for (final line in live) Label(line),
        const Label('> prompt'),
      ]),
      history: [r'$ app'],
      height: 5,
    );
    await run.settle();
    expect(run.term.lines, [r'$ app', 'a1', 'a2', 'a3', '> prompt']);
    run.state.change(() => live = ['a1']);
    await run.settle();
    expect(run.regionRows, 4);
    run.state.change(() {
      items.add('a');
      live = [];
    });
    await run.settle();
    expect(run.regionRows, 1);
    expect(run.term.vt.history, isEmpty);
    expect(run.term.lines, [r'$ app', 'a', '> prompt', '', '']);
    await run.quit();
    // on the line below the region
    expect(run.term.vt.cy, 3);
  });

  test('an item is built under the widgets above the Static and laid out at '
      "the terminal's width, as tall as it asks to be", () async {
    final items = <String>[];
    final run = _Inline(
      (_) => _Prefix(
        '#',
        child: Static<String>(
          items: [...items],
          builder: (context, item) => column([
            Row(
              children: [
                Label('${_Prefix.of(context)} $item'),
                const Spacer(),
                const Label('|'),
              ],
            ),
            const Label('  more'),
          ]),
        ),
      ),
      width: 12,
      height: 6,
    );
    await run.settle();
    run.state.change(() => items.add('a'));
    await run.settle();
    expect(run.term.lines.take(2), ['# a        |', '  more']);
    await run.quit();
  });

  test("once its rows are written, an item's widgets are unmounted, their "
      'states disposed', () async {
    final items = <String>[];
    final disposed = <String>[];
    final run = _Inline(
      (_) => Static<String>(
        items: [...items],
        builder: (_, item) => Probe(
          (_) => Label(item),
          onDispose: () => disposed.add(item),
        ),
      ),
    );
    await run.settle();
    run.state.change(() => items.addAll(['one', 'two']));
    await run.settle();
    expect(disposed, ['one', 'two']);
    expect(run.term.lines.take(2), ['one', 'two']);
    await run.quit();
  });

  test('items are told apart by their index: a changed or shorter list '
      'commits nothing, an item past those built is new', () async {
    var items = ['a', 'b'];
    final run = _Inline(
      (_) => Static<String>(items: items, builder: (_, item) => Label(item)),
    );
    await run.settle();
    run.state.change(() => items = ['x']);
    await run.settle();
    run.state.change(() => items = ['x', 'y', 'c']);
    await run.settle();
    expect(run.term.lines.take(4), ['a', 'b', 'c', '']);
    await run.quit();
  });

  test('what a Static built before it leaves the tree is still '
      'written', () async {
    var shown = true;
    final run = _Inline(
      (_) => shown
          ? Static<String>(
              items: const ['one', 'two'],
              builder: (_, item) => Probe(
                (_) => Label(item),
                // the last item has the app show something else instead
                onInit: item == 'two'
                    ? (s) => s.context
                          .findAncestorStateOfType<ProbeState>()!
                          .change(() => shown = false)
                    : null,
              ),
            )
          : const Label('> done'),
    );
    await run.settle();
    expect(run.term.lines.take(3), ['one', 'two', '> done']);
    await run.quit();
  });

  test('an item whose layout throws in the inline mode is logged with the '
      'path of its widget, and its message goes to the history in its '
      'place', () async {
    final items = <String>[];
    final run = _Inline(
      (_) => Static<String>(
        items: [...items],
        builder: (_, item) => item == 'bad' ? const _Boom() : Label(item),
      ),
      width: 30,
    );
    await run.settle();
    run.state.change(() => items.addAll(['bad', 'good']));
    await run.settle();
    expect(run.term.lines.take(2), ['Bad state: boom', 'good']);
    expect(run.logs.records.where((r) => r.level == LogLevel.error), [
      isA<LogRecord>().having(
        (r) => r.message,
        'message',
        endsWith('→ Static<String> → _Item<String> → _Boom failed to lay out'),
      ),
    ]);
    await run.quit();
  });

  test('in the fullscreen mode the items are shown in place, one below '
      'another at its width, each built once and kept mounted', () async {
    final items = <String>[];
    final built = <String>[];
    final disposed = <String>[];
    final key = GlobalKey<ProbeState>();
    final run = Run(
      Probe(
        key: key,
        (_) => column([
          Static<String>(
            items: [...items],
            builder: (_, item) {
              built.add(item);
              return Probe(
                (_) => _Width(item),
                onDispose: () => disposed.add(item),
              );
            },
          ),
          const Label('> prompt'),
        ]),
      ),
      width: 8,
      height: 5,
    );
    await run.settle();
    expect(run.rows, ['> prompt', '', '', '', '']);
    key.currentState!.change(() => items.addAll(['one', 'two']));
    await run.settle();
    expect(run.rows, ['one 8', 'two 8', '> prompt', '', '']);
    key.currentState!.change(() => items.add('three'));
    await run.settle();
    expect(run.rows, ['one 8', 'two 8', 'three 8', '> prompt', '']);
    expect(built, ['one', 'two', 'three']);
    expect(disposed, isEmpty);
    run.term.type('\x03');
    await run.ended();
    expect(disposed, unorderedEquals(['one', 'two', 'three']));
  });
}

/// As narrow as the constraints allow, one row; shows [text] and its width.
final class _Width extends LeafRenderObjectWidget {
  const _Width(this.text);

  final String text;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWidth(text);
}

final class _RenderWidth extends RenderObject {
  _RenderWidth(this.text);

  final String text;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.minW;
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) =>
      ctx.canvas.text(0, 0, '$text $width', ctx.canvas.styles.pen(const Pen()));
}

/// An app run inline by an [AppBinding] on a [VtTerminal] below lines of
/// history, stderr caught, on [clock]: what a builder builds from the
/// [state] of the [Probe] that shows it.
final class _Inline {
  _Inline(
    Widget Function(ProbeState state) builder, {
    List<String> history = const [],
    int width = 20,
    int height = 4,
  }) {
    clock.run(() {
      term = VtTerminal(width: width, height: height, history: history);
      done = IOOverrides.runZoned(
        () => AppBinding(
          term,
          maxFps: 1000,
          logs: logs,
          clock: clock.stopwatch,
        ).run(Probe(key: _key, builder)),
        stderr: () => _err,
      );
    });
  }

  /// The time of the app.
  final clock = FakeClock();
  late final VtTerminal term;
  final logs = LogSink();
  final _key = GlobalKey<ProbeState>();
  late final Future<void> done;
  // ignore: close_sinks, stands in for stderr, which stays open
  late final _err = FakeStderr();

  ProbeState get state => _key.currentState!;

  /// How many rows the region has.
  int get regionRows =>
      AppBinding.of(_key.currentContext!).twkApp.screen.height;

  /// Lets the frame loop run for 30 ms of the app's clock.
  Future<void> settle() => clock.settle();

  /// Ends the app and runs it until it has ended.
  Future<void> quit() {
    AppBinding.of(_key.currentContext!).quit();
    return clock.elapseUntil(done);
  }
}

/// Gives the widgets below it a prefix.
final class _Prefix extends InheritedWidget {
  const _Prefix(this.prefix, {required super.child});

  final String prefix;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Prefix>()!.prefix;

  @override
  bool updateShouldNotify(_Prefix oldWidget) => prefix != oldWidget.prefix;
}

/// One row whose layout throws.
final class _Boom extends LeafRenderObjectWidget {
  const _Boom();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBoom();
}

final class _RenderBoom extends RenderObject {
  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) => throw StateError('boom');

  @override
  void paint(PaintContext ctx) {}
}
