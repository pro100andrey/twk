// Implicit animations on the fake clock: each widget runs from the value
// it shows to the new one a frame at a time, from where it is when the
// value changes again on the way, and calls onEnd at the end; then the app
// asks for no frame and starts no timer. A widget of the app's own on
// ImplicitlyAnimatedWidget, TweenAnimationBuilder, AnimatedSize following
// its child, and the tweens of insets and styles.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

/// Starts an app at 100 frames a second, a frame each 10 ms, that shows
/// what [build] makes of the value of the notifier it returns, on a
/// terminal of [size].
Future<ValueNotifier<T>> start<T>(
  TwkTester t,
  T first,
  Widget Function(T value) build, {
  (int, int) size = (20, 1),
}) async {
  final value = ValueNotifier(first);
  await t.pumpWidget(
    ValueListenableBuilder<T>(
      valueListenable: value,
      builder: (_, v, _) => build(v),
    ),
    size: size,
    maxFps: 100,
  );
  return value;
}

/// What [shot] makes of the screen after each of [count] frames. The
/// first frame after a value changed builds with it, showing the old one
/// still; the run starts in the frame after it.
Future<List<R>> frames<R>(TwkTester t, int count, R Function() shot) async {
  final shots = <R>[];
  for (var i = 0; i < count; i++) {
    await t.pump();
    shots.add(shot());
  }
  return shots;
}

/// Pumps for 10 s and expects no frame written, nor any timer waiting.
Future<void> expectIdle(TwkTester t) async {
  expect(t.clock.pendingTimers, 0);
  final written = t.frames.length;
  await t.pump(const Duration(seconds: 10));
  expect(t.frames, hasLength(written));
  expect(t.clock.pendingTimers, 0);
}

/// The column of the first `x` on the first line.
int column(TwkTester t) => t.lines.first.indexOf('x');

/// The colors of the cell at [x], [y]: text and background.
(int, int) colors(TwkTester t, int x, int y) {
  final cell = t.cell(x, y);
  return (cell.fg, cell.bg);
}

/// A level from 0 to 9, on or off; an implicitly animated widget of the
/// app's own.
final class Level extends ImplicitlyAnimatedWidget {
  const Level({required this.on, required super.duration, super.key});

  final bool on;

  @override
  State<Level> createState() => _LevelState();
}

final class _LevelState extends ImplicitlyAnimatedWidgetState<Level> {
  Tween<int>? _level;

  @override
  void forEachTween(TweenVisitor visit) =>
      _level = visit(_level, widget.on ? 9 : 0, IntTween.new);

  @override
  Widget build(BuildContext context) => Text('${_level!.transform(progress)}');
}

/// [AnimatedPadding] of [left] cells on the left of an `x`.
Widget padded(
  int left, {
  Duration duration = const Duration(milliseconds: 100),
}) => AnimatedPadding(
  padding: EdgeInsets.only(left: left),
  duration: duration,
  child: const Text('x'),
);

void main() {
  testTwk('AnimatedPadding runs each side to its new width, a cell at a '
      'time; then the app asks for no frame', (t) async {
    final left = await start(t, 0, padded);
    expect(column(t), 0);
    left.value = 10;
    expect(await frames(t, 11, () => column(t)), [
      for (var i = 0; i <= 10; i++) i,
    ]);
    await expectIdle(t);
  });

  testTwk('a value changed on the way runs from where it is, in the whole '
      'duration again; the same value again starts nothing', (t) async {
    final left = await start(t, 0, padded);
    left.value = 10;
    await frames(t, 6, () {});
    expect(column(t), 5);
    // the frame that builds with it is the run's at 60 ms, 6 cells in
    left.value = 0;
    expect(await frames(t, 12, () => column(t)), [
      6,
      6,
      5,
      5,
      4,
      4,
      3,
      2,
      2,
      1,
      1,
      0,
    ]);
    await expectIdle(t);
    left.value = 0;
    await t.pump();
    await expectIdle(t);
  });

  testTwk('the curve maps the run; onEnd is called once it has ended', (
    t,
  ) async {
    var ends = 0;
    final left = await start(
      t,
      0,
      (left) => AnimatedPadding(
        padding: EdgeInsets.only(left: left),
        duration: ms * 40,
        curve: Curves.easeIn,
        onEnd: () => ends++,
        child: const Text('x'),
      ),
    );
    left.value = 12;
    expect(await frames(t, 5, () => column(t)), [
      for (var i = 0; i <= 4; i++)
        (12 * Curves.easeIn.transform(i / 4)).round(),
    ]);
    expect(ends, 1);
    await expectIdle(t);
    expect(ends, 1);
  });

  testTwk('AnimatedAlign moves its child across to its new place, to the '
      'nearest cell, a half towards the start', (t) async {
    final alignment = await start(
      t,
      Alignment.centerLeft,
      (alignment) => SizedBox(
        width: 9,
        height: 3,
        child: AnimatedAlign(
          alignment: alignment,
          duration: ms * 40,
          child: const Text('x'),
        ),
      ),
      size: (9, 3),
    );
    expect(t, hasTextAt(0, 1, 'x'));
    alignment.value = Alignment.bottomRight;
    final places = await frames(t, 5, () {
      for (final (y, line) in t.lines.indexed) {
        if (line.contains('x')) {
          return (line.indexOf('x'), y);
        }
      }
      return null;
    });
    expect(places, [(0, 1), (2, 1), (4, 1), (6, 2), (8, 2)]);
    await expectIdle(t);
  });

  testTwk('AnimatedPositioned runs an edge given before and after; one '
      'given now goes there at once', (t) async {
    final edges = await start<(int, int?)>(
      t,
      (2, null),
      (edges) => Stack(
        children: [
          AnimatedPositioned(
            left: edges.$1,
            top: edges.$2,
            duration: ms * 40,
            child: const Text('x'),
          ),
        ],
      ),
      size: (12, 3),
    );
    expect(t, hasTextAt(2, 0, 'x'));
    edges.value = (10, 2);
    final places = await frames(
      t,
      5,
      () => (t.lines.last.indexOf('x'), t.lines.length - 1),
    );
    expect(places, [(2, 2), (4, 2), (6, 2), (8, 2), (10, 2)]);
    await expectIdle(t);
  });

  testTwk('AnimatedOpacity fades its child in over what is under it, its '
      'colors mixed as by alpha', (t) async {
    const black = Color.rgb(0, 0, 0);
    const orange = Color.rgb(200, 100, 0);
    const purple = Color.rgb(100, 0, 200);
    final opacity = await start<double>(
      t,
      0,
      (opacity) => Box(
        style: const Style(bg: black),
        child: AnimatedOpacity(
          opacity: opacity,
          duration: ms * 20,
          child: const Text(
            'ab',
            style: Style(fg: orange, bg: purple),
          ),
        ),
      ),
      size: (4, 1),
    );
    expect(t.lines, ['']);
    expect(t, styleAt(0, 0, hasBg(black)));
    opacity.value = 1;
    final shots = await frames(
      t,
      3,
      () => (t.lines.single, colors(t, 0, 0)),
    );
    expect(shots, [
      ('', (0, black.value)),
      // halfway: alpha 128 of 255
      (
        'ab',
        (const Color.rgb(125, 50, 50).value, const Color.rgb(50, 0, 100).value),
      ),
      ('ab', (orange.value, purple.value)),
    ]);
    expect(t, styleAt(2, 0, hasBg(black)));
    await expectIdle(t);
  });

  testTwk('AnimatedDefaultTextStyle runs the colors, and fades in one it '
      'had none of', (t) async {
    final style = await start(
      t,
      const Style(fg: Color.rgb(0, 0, 0)),
      (style) => AnimatedDefaultTextStyle(
        style: style,
        duration: ms * 40,
        child: const Text('x'),
      ),
    );
    style.value = const Style(
      fg: Color.rgb(200, 100, 40),
      bg: Color.rgb(0, 0, 80),
    );
    final cells = await frames(t, 5, () => colors(t, 0, 0));
    expect(
      [for (final (fg, _) in cells) fg],
      [
        for (var i = 0; i <= 4; i++) Color.rgb(50 * i, 25 * i, 10 * i).value,
      ],
    );
    // the background over the terminal's default one, black here
    expect(
      [for (final (_, bg) in cells) bg],
      [
        0,
        for (final alpha in [64, 128, 191])
          Color.rgb(0, 0, (80 * alpha / 255).round()).value,
        const Color.rgb(0, 0, 80).value,
      ],
    );
    await expectIdle(t);
  });

  testTwk('AnimatedBox runs its size, padding and colors; a border of '
      'another type switches halfway', (t) async {
    final wide = await start(
      t,
      false,
      (wide) => Align(
        alignment: Alignment.topLeft,
        child: AnimatedBox(
          duration: ms * 40,
          width: wide ? 12 : 4,
          height: 3,
          style: Style(bg: wide ? const Color.rgb(0, 0, 200) : null),
          border: Border.all(
            type: wide ? BorderType.double : BorderType.single,
          ),
          padding: EdgeInsets.only(left: wide ? 4 : 0),
          child: const Text('x'),
        ),
      ),
      size: (14, 3),
    );
    expect(t.lines.first, '┌──┐');
    wide.value = true;
    final shots = await frames(t, 5, () => t.lines);
    expect(
      [for (final lines in shots) lines.first],
      [
        '┌──┐',
        '┌────┐',
        '╔══════╗',
        '╔════════╗',
        '╔══════════╗',
      ],
    );
    expect([for (final lines in shots) lines[1].indexOf('x')], [1, 2, 3, 4, 5]);
    expect(t, styleAt(1, 1, hasBg(const Color.rgb(0, 0, 200))));
    await expectIdle(t);
  });

  testTwk('TweenAnimationBuilder runs from its first value when it has one, '
      'and to a new value from the one it shows', (t) async {
    final value = await start(
      t,
      10,
      (value) => TweenAnimationBuilder<int>(
        value: value,
        from: 0,
        tween: IntTween.new,
        duration: ms * 50,
        builder: (_, value, _) => Text('$value'),
      ),
    );
    expect(await frames(t, 5, () => t.lines.single), [
      '2',
      '4',
      '6',
      '8',
      '10',
    ]);
    await expectIdle(t);
    value.value = 0;
    expect(await frames(t, 6, () => t.lines.single), [
      '10',
      '8',
      '6',
      '4',
      '2',
      '0',
    ]);
    await expectIdle(t);
  });

  testTwk("a widget of the app's own on ImplicitlyAnimatedWidget runs the "
      'tweens its state visits', (t) async {
    final on = await start(
      t,
      false,
      (on) => Level(on: on, duration: ms * 30),
    );
    expect(t.lines, ['0']);
    on.value = true;
    expect(await frames(t, 4, () => t.lines.single), ['0', '3', '6', '9']);
    await expectIdle(t);
  });

  testTwk('AnimatedSize takes its first size at once, then runs to the size '
      'of its child, which it cuts off on the way', (t) async {
    final text = await start(
      t,
      'ab',
      (text) => Row(
        children: [
          AnimatedSize(duration: ms * 40, child: Text(text)),
          const Text('|'),
        ],
      ),
    );
    expect(t.lines, ['ab|']);
    text.value = 'abcdefghij';
    expect(await frames(t, 5, () => t.lines.single), [
      'ab|',
      'abcd|',
      'abcdef|',
      'abcdefgh|',
      'abcdefghij|',
    ]);
    await expectIdle(t);
    text.value = 'a';
    expect(await frames(t, 3, () => t.lines.single), [
      'a${' ' * 9}|',
      'a${' ' * 7}|',
      'a${' ' * 5}|',
    ]);
  });

  testTwk('an implicit animation removed mid-run asks for no frame', (
    t,
  ) async {
    final left = await start(
      t,
      0,
      (left) => left < 0 ? const Text('gone') : padded(left),
    );
    left.value = 10;
    await frames(t, 4, () {});
    left.value = -1;
    await t.pump();
    expect(t.lines, ['gone']);
    // the frame the run asked for before
    await t.pump();
    await expectIdle(t);
  });

  test('EdgeInsetsTween rounds each side and keeps it from going below 0; '
      'StyleTween fades a color in through its alpha and switches the '
      'attributes halfway', () {
    const insets = EdgeInsetsTween(
      begin: EdgeInsets.only(left: 2, top: 1),
      end: EdgeInsets.only(left: 6, bottom: 3),
    );
    expect(
      insets.transform(0.5),
      const EdgeInsets.only(left: 4, top: 1, bottom: 2),
    );
    expect(insets.transform(-1), const EdgeInsets.only(top: 2));
    const style = StyleTween(
      begin: Style(fg: Color.rgb(0, 0, 0)),
      end: Style(fg: Color.rgb(100, 200, 0), bg: Color.blue, attrs: Attr.bold),
    );
    expect(
      style.transform(0.25),
      const Style(fg: Color.rgb(25, 50, 0), bg: Color.blue, bgAlpha: 64),
    );
    expect(
      style.transform(0.5),
      const Style(
        fg: Color.rgb(50, 100, 0),
        bg: Color.blue,
        bgAlpha: 128,
        attrs: Attr.bold,
      ),
    );
    expect(style.transform(1), style.end);
  });

  test('StyleTween runs an underline color both styles set, switches one '
      'set on one side only halfway, and fades out a color the end leaves '
      'unset', () {
    const both = StyleTween(
      begin: Style(underlineColor: Color.rgb(0, 0, 0)),
      end: Style(underlineColor: Color.rgb(100, 0, 0)),
    );
    expect(both.transform(0.5).underlineColor, const Color.rgb(50, 0, 0));
    const one = StyleTween(
      begin: Style(),
      end: Style(underlineColor: Color.red),
    );
    expect(one.transform(0.4).underlineColor, isNull);
    expect(one.transform(0.6).underlineColor, Color.red);
    const out = StyleTween(
      begin: Style(fg: Color.green),
      end: Style(),
    );
    expect(out.transform(0.25), const Style(fg: Color.green, fgAlpha: 191));
  });

  testTwk('AnimatedAlign and AnimatedSize are as big as their child '
      'intrinsically', (t) async {
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicWidth(
            child: IntrinsicHeight(
              child: AnimatedAlign(
                alignment: Alignment.center,
                duration: ms * 40,
                child: const Text('ab'),
              ),
            ),
          ),
          IntrinsicWidth(
            child: IntrinsicHeight(
              child: AnimatedSize(
                duration: ms * 40,
                child: const Text('abc'),
              ),
            ),
          ),
          const Text('end'),
        ],
      ),
      size: (10, 4),
    );
    expect(t.lines, ['ab', 'abc', 'end', '']);
    expect(t.rect(find.byType(AnimatedAlign)).width, 2);
    expect(t.rect(find.byType(AnimatedSize)).width, 3);
  });

  testTwk('AnimatedSize without a child is as small as it may be; built '
      'with another alignment, it places its child by it as it runs', (
    t,
  ) async {
    final shown = await start<(String?, Alignment)>(
      t,
      (null, Alignment.topLeft),
      (shown) => Row(
        children: [
          AnimatedSize(
            duration: ms * 40,
            alignment: shown.$2,
            child: shown.$1 == null ? null : Text(shown.$1!),
          ),
          const Text('|'),
        ],
      ),
    );
    expect(t.lines, ['|']);
    expect(t.rect(find.byType(AnimatedSize)).width, 0);
    shown.value = ('abcdefgh', Alignment.topLeft);
    await frames(t, 2, () {});
    expect(t.lines, ['abcdefgh|'], reason: 'its first size at once');
    shown.value = ('ab', Alignment.topRight);
    expect(await frames(t, 3, () => t.lines.single), [
      '      ab|',
      '     ab|',
      '   ab|',
    ]);
  });

  testTwk('the render tree says what size an AnimatedSize runs to while it '
      'runs', (t) async {
    final text = await start(
      t,
      'ab',
      (text) => Row(
        children: [
          AnimatedSize(duration: ms * 40, child: Text(text)),
          const Text('|'),
        ],
      ),
    );
    String described() => t
        .renderObject<RenderObject>(find.byType(AnimatedSize))
        .describe()
        .toString();
    expect(described(), isNot(contains('running to')));
    text.value = 'abcdef';
    await frames(t, 2, () {});
    expect(described(), contains('running to: 6×1'));
  });
}
