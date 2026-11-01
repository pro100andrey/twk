// The marks a widget draws as text keep the width rule of the theme's
// Glyphs: one that is not one cell wide is Glyphs.ascii's, so the columns
// of the row it stands in do not shift: a tree table's expanders, the
// arrow of the digits typed to a Pagination, the one of a LogView's new
// lines, the arrows a KeyHintsBar names keys by, the buttons of a Window.
// And the edges of a few lists the set and its controllers keep to
// themselves.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';

/// A mark two columns wide everywhere.
const wide = '【';

Widget themed(Glyphs glyphs, Widget child) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: child,
);

List<String> warnings(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level == LogLevel.warning) r.message,
];

/// A stream whose subscriptions count the cancels they get.
final class CountingStream extends Stream<String> {
  var cancels = 0;

  @override
  StreamSubscription<String> listen(
    void Function(String event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    // the wrapper counts the cancels of this one, which is its own
    // ignore: cancel_subscriptions
    final inner = const Stream<String>.empty().listen(null);
    return _Counted(inner, () => cancels++);
  }
}

final class _Counted implements StreamSubscription<String> {
  _Counted(this._inner, this._onCancel);

  final StreamSubscription<String> _inner;
  final void Function() _onCancel;

  @override
  Future<void> cancel() {
    _onCancel();
    return _inner.cancel();
  }

  @override
  void onData(void Function(String data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  bool get isPaused => false;

  @override
  Future<E> asFuture<E>([E? futureValue]) => Future.value(futureValue);
}

void main() {
  group('TreeTable', () {
    const roots = [
      _N('src', [_N('a.dart', [])]),
      _N('test', [_N('b.dart', [])]),
    ];
    Widget tree() => TreeTable<_N>(
      roots: roots,
      children: (n) => n.children,
      nodeKey: (n) => n.name,
      columns: [TableColumn(title: 'Name', cell: (n) => TableCell(n.name))],
      controller: TreeController(expanded: ['src']),
    );

    testTwk('an expander two columns wide is the ASCII one, warned of', (
      t,
    ) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(expanded: wide, collapsed: '🙂'),
          tree(),
        ),
        size: (14, 5),
      );
      expect(t.lines.take(4), [
        'Name',
        'v src',
        '└── a.dart',
        '> test',
      ]);
      expect(warnings(t), hasLength(2));
    });

    test('on an ambiguous-wide terminal expanders that are ambiguous do '
        'not shift the columns', () async {
      final app = await WideApp.start(
        themed(Glyphs.unicode.copyWith(expanded: '●', collapsed: '○'), tree()),
        width: 14,
        height: 4,
      );
      final lines = app.lines();
      await app.quit();
      expect(lines, ['Name', 'v src', '+-- a.dart', '> test']);
    });
  });

  testTwk('the arrow before the digits typed to a Pagination is one cell', (
    t,
  ) async {
    final node = FocusNode(debugLabel: 'pages');
    addTearDown(node.dispose);
    await t.pumpWidget(
      themed(
        Glyphs.unicode.copyWith(arrowRight: wide),
        SizedBox(
          width: 60,
          child: Pagination(
            page: 0,
            pageCount: 42,
            focusNode: node,
            onChanged: (_) {},
          ),
        ),
      ),
      size: (60, 2),
    );
    node.requestFocus();
    await t.pump();
    await t.press('1');
    await t.pump();
    expect(t.lines.first.trimRight(), endsWith('Last »  > 1'));
    expect(warnings(t), hasLength(1));
  });

  testTwk('the arrow of the new lines of a LogView is one cell', (t) async {
    final c = LogController();
    addTearDown(c.dispose);
    for (var i = 0; i < 10; i++) {
      c.add('line $i');
    }
    await t.pumpWidget(
      themed(
        Glyphs.unicode.copyWith(arrowDown: wide),
        LogView(
          controller: c,
          showTime: false,
          showLevel: false,
          autofocus: true,
          scrollbar: ScrollbarVisibility.never,
        ),
      ),
      size: (30, 4),
    );
    await t.press('up');
    await t.pump();
    await t.pump();
    c.add('line 10');
    await t.pump();
    expect(t.lines.last.trimRight(), endsWith(' v 1 new line'));
    expect(warnings(t), hasLength(1));
  });

  testTwk('the arrows a KeyHintsBar names keys by are one cell each', (
    t,
  ) async {
    await t.pumpWidget(
      themed(
        Glyphs.unicode.copyWith(arrowUp: wide, arrowDown: '🙂'),
        KeyBindings(
          {'up': () {}, 'down': () {}},
          hints: const {'up': 'move', 'down': 'move'},
          child: const Focus(autofocus: true, child: KeyHintsBar()),
        ),
      ),
      size: (20, 1),
    );
    expect(t.lines.single.trimRight(), '^v move');
    expect(warnings(t), hasLength(2));
  });

  test('on an ambiguous-wide terminal the bar names the arrows in ASCII, '
      'so a click lands on the key under it', () async {
    final seen = <String>[];
    final app = await WideApp.start(
      KeyBindings(
        {'up': () => seen.add('up'), 'down': () => seen.add('down')},
        hints: const {'up': 'move', 'down': 'move'},
        child: const Focus(
          autofocus: true,
          child: KeyHintsBar(pressable: true),
        ),
      ),
      width: 20,
      height: 1,
    );
    final lines = app.lines();
    await app.click(1, 0);
    await app.quit();
    expect(lines.single, '^v move');
    expect(seen, ['down']);
  });

  testTwk('the buttons of a Window are one cell each', (t) async {
    await t.pumpWidget(
      themed(
        Glyphs.unicode.copyWith(minimise: wide, maximise: wide, close: wide),
        WindowLayer(
          windows: [
            Window(
              title: 'W',
              controller: WindowController(
                width: 16,
                height: 3,
              ),
              onClose: () {},
              child: const Text('body'),
            ),
          ],
          child: const Text(''),
        ),
      ),
      size: (16, 3),
    );
    expect(t.lines.first.trimRight(), endsWith('─ + x'));
    expect(warnings(t), hasLength(2));
  });

  group('edges', () {
    test('copyWith keeps its own copy of shades', () {
      final shades = [' ', 'a', 'b'];
      final glyphs = Glyphs.unicode.copyWith(shades: shades);
      shades[1] = 'z';
      expect(glyphs.shades, [' ', 'a', 'b']);
      expect(() => glyphs.shades.add('c'), throwsUnsupportedError);
      expect(glyphs.copyWith().shades, [' ', 'a', 'b']);
    });

    test('a subscription the caller cancels is not cancelled again by '
        'dispose', () async {
      final source = CountingStream();
      final c = LogController();
      final subscription = c.listen(source);
      await subscription.cancel();
      c.dispose();
      expect(source.cancels, 1);
    });

    test('a subscription not cancelled is cancelled by dispose', () {
      final source = CountingStream();
      LogController()
        ..listen(source)
        ..dispose();
      expect(source.cancels, 1);
    });

    test('addSpans keeps its own copy of the spans', () {
      final spans = [const Span('a'), const Span('b')];
      final c = LogController()..addSpans(spans);
      addTearDown(c.dispose);
      spans.clear();
      expect(c[0].text, 'ab');
      expect(c[0].spans, hasLength(2));
    });
  });
}

final class _N {
  const _N(this.name, this.children);

  final String name;
  final List<_N> children;
}
