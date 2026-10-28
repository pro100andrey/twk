// A PageRoute's transition: pushed, it slides in from the right over the
// route under it, which stays painted and dims in the theme's shade; popped,
// it slides out again; the focus, the results and the keys go as without
// one; a route of no duration, the default, shows at once.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);
const ThemeData theme = ThemeData.dark;
final Color background = theme.background.bg!;

/// A [Focus] shown as its [label], after `>` while it has the primary
/// focus and ` ` while not.
final class Field extends StatelessWidget {
  const Field(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, debugLabel: label, child: _Mark(label));
}

final class _Mark extends StatelessWidget {
  const _Mark(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text('${Focus.of(context).hasPrimaryFocus ? '>' : ' '}$label');
}

/// [field] under [keys], each doing what its callback does with the
/// context.
Widget screen(
  String field, [
  Map<String, void Function(BuildContext context)> keys = const {},
]) => Builder(
  builder: (context) => KeyBindings(
    {
      for (final MapEntry(:key, :value) in keys.entries)
        key: () => value(context),
    },
    child: Field(field),
  ),
);

/// A route of the screen `detail`, which `x` pops with `done`, coming in
/// over [push] and going out over [pop].
PageRoute<String> detail({
  Duration push = const Duration(milliseconds: 200),
  Duration? pop,
}) => PageRoute<String>(
  transitionDuration: push,
  reverseTransitionDuration: pop,
  builder: (_) => screen('detail', {'x': (c) => Navigator.pop(c, 'done')}),
);

/// A navigator on the dark theme whose first route reads `home home home`;
/// `n` pushes [route] and adds its result to [results].
Widget app(Route<String> Function() route, List<Object?> results) => Theme(
  data: theme,
  child: Box(
    style: theme.background,
    child: Navigator(
      home: screen('home home home', {
        'n': (c) => unawaited(Navigator.push(c, route()).then(results.add)),
      }),
    ),
  ),
);

Future<void> press(TwkTester t, String key) async {
  await t.press(key);
  await t.pump();
}

/// Where `detail` starts on the first row; -1 where it is not there.
int detailAt(TwkTester t) => t.lines[0].indexOf('detail');

void main() {
  test('a PageRoute comes and goes at once by default; the time to go is '
      'the time to come where none is given', () {
    final plain = PageRoute<void>(builder: (_) => const Text('x'));
    expect(plain.transitionDuration, Duration.zero);
    expect(plain.reverseTransitionDuration, Duration.zero);
    final slides = detail();
    expect(slides.transitionDuration, ms * 200);
    expect(slides.reverseTransitionDuration, ms * 200);
    expect(detail(pop: ms * 90).reverseTransitionDuration, ms * 90);
  });

  testTwk('pushed, a route slides in from the right over the route under '
      'it, which stays painted and dims in the theme shade; it takes the '
      'focus at once', (t) async {
    await t.pumpWidget(app(detail, []), size: (20, 2));
    expect(t.lines[0], '>home home home');
    await press(t, 'n');
    // the route under painted, the focus gone from it
    expect(t.lines[0], startsWith(' home'));
    await t.pump(ms * 80);
    final at = detailAt(t);
    expect(at, inInclusiveRange(4, 16), reason: t.lines.join('\n'));
    expect(t.lines[0], startsWith(' home'));
    expect(t.lines[0].substring(at - 1), startsWith('>detail'));
    // the route under dimmed, but not all the way; the route coming in on
    // the theme's background, which covers what it does not paint
    expect(t, styleAt(1, 0, isNot(hasBg(background))));
    expect(t, styleAt(1, 1, isNot(hasBg(background))));
    expect(t, styleAt(19, 1, hasBg(background)));
    expect(t, styleAt(at, 1, hasBg(background)));
    // further in, further left
    await t.pump(ms * 60);
    expect(detailAt(t), inInclusiveRange(1, at - 1));
    await t.pump(ms * 100);
    expect(t.lines, ['>detail', '']);
    expect(t, styleAt(10, 0, hasBg(background)));
  });

  testTwk('popped, a route slides out to the right, uncovering the one '
      'under it, which has the focus and the keys at once; its future '
      'completes at once', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(
      app(() => detail(push: ms * 100, pop: ms * 160), results),
      size: (20, 2),
    );
    await press(t, 'n');
    await t.pump(ms * 200);
    expect(t.lines[0], '>detail');
    await press(t, 'x');
    expect(results, ['done']);
    await t.pump(ms * 60);
    final at = detailAt(t);
    expect(at, inInclusiveRange(3, 16), reason: t.lines.join('\n'));
    expect(t.lines[0], startsWith('>home'));
    expect(t.lines[0].substring(at - 1), startsWith(' detail'));
    expect(t, styleAt(1, 0, isNot(hasBg(background))));
    expect(t, styleAt(at, 1, hasBg(background)));
    await t.pump(ms * 120);
    expect(t.lines, ['>home home home', '']);
    expect(t, styleAt(1, 0, hasBg(background)));
    // what was popped takes no keys: `n` pushes again from home
    await press(t, 'n');
    await t.pump(ms * 200);
    expect(t.lines[0], '>detail');
  });

  testTwk('a route popped while it comes in goes back out from where it '
      'was', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(app(detail, results), size: (20, 2));
    await press(t, 'n');
    await t.pump(ms * 80);
    final at = detailAt(t);
    await press(t, 'x');
    expect(results, ['done']);
    expect(t.lines[0], startsWith('>home'));
    expect(detailAt(t), inInclusiveRange(at, 19));
    await t.pump(ms * 300);
    expect(t.lines, ['>home home home', '']);
  });

  testTwk('a route that replaces another slides in over it, which goes once '
      'it is in', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    final results = <Object?>[];
    await t.pumpWidget(
      Theme(
        data: theme,
        child: Box(
          style: theme.background,
          child: Navigator(key: navigator, home: screen('home')),
        ),
      ),
      size: (20, 2),
    );
    unawaited(navigator.currentState!.push(detail()).then(results.add));
    await t.pump(ms * 300);
    final next = PageRoute<String>(
      transitionDuration: ms * 200,
      builder: (_) => screen('next'),
    );
    unawaited(navigator.currentState!.pushReplacement(next, result: 'gone'));
    await t.pump();
    expect(results, ['gone']);
    await t.pump(ms * 80);
    expect(t.lines[0], startsWith(' detail'));
    expect(t.lines[0], contains('>next'));
    await t.pump(ms * 200);
    expect(t.lines, ['>next', '']);
    navigator.currentState!.pop();
    await t.pump(ms * 100);
    // what it replaced went with it: home is under it
    expect(t.lines[0], startsWith('>home'));
    expect(t.lines[0], contains('next'));
    await t.pump(ms * 200);
    expect(t.lines, ['>home', '']);
  });

  testTwk('the mouse does not reach the route under one sliding in, and '
      'goes past one sliding out to the route in front', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    var pressed = 0;
    await t.pumpWidget(
      Theme(
        data: theme,
        child: Box(
          style: theme.background,
          child: Navigator(
            key: navigator,
            home: Button('press press press', onPressed: () => pressed++),
          ),
        ),
      ),
      size: (30, 2),
    );
    await t.click(2, 0);
    await t.pump();
    expect(pressed, 1);
    unawaited(navigator.currentState!.push(detail()));
    await t.pump(ms * 100);
    expect(detailAt(t), greaterThan(4), reason: t.lines.join('\n'));
    await t.click(2, 0);
    await t.pump();
    expect(pressed, 1);
    await t.pump(ms * 300);
    navigator.currentState!.pop();
    await t.pump(ms * 50);
    final at = detailAt(t);
    expect(at, inInclusiveRange(1, 16), reason: t.lines.join('\n'));
    await t.click(at + 2, 0);
    await t.pump();
    expect(pressed, 2);
  });

  testTwk('a route of no duration comes and goes at once', (t) async {
    await t.pumpWidget(
      app(() => detail(push: Duration.zero), []),
      size: (20, 2),
    );
    await press(t, 'n');
    expect(t.lines, ['>detail', '']);
    await press(t, 'x');
    expect(t.lines, ['>home home home', '']);
  });
}
