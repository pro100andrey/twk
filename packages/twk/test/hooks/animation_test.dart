// The hooks of animations: useAnimationController and useTicker, each
// through mounting, running in the app's frames, rebuilding with the same
// and with other keys, and unmounting.
import 'package:test/test.dart';
import 'package:twk/hooks.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'matchers.dart';

const ms = Duration(milliseconds: 1);

/// A ticker provider that counts the tickers it makes.
final class Provider implements TickerProvider {
  var tickers = 0;

  @override
  Ticker createTicker(TickerCallback onTick) {
    tickers++;
    return Ticker(onTick);
  }
}

void main() {
  group('useAnimationController', () {
    testTwk('runs in the frames of the app, the same controller through '
        'rebuilds, with the duration of the latest', (t) async {
      final controllers = <AnimationController>[];
      Widget animated(Duration duration) => HookBuilder(
        builder: (context) {
          final controller = useAnimationController(
            duration: duration,
            initialValue: 2,
            lowerBound: 2,
            upperBound: 4,
          );
          controllers.add(controller);
          return Text('${useListenable(controller).value}');
        },
      );
      await t.pumpWidget(animated(ms * 100), size: (10, 1), maxFps: 100);
      expect(t.lines, ['2.0']);
      controllers.last.forward();
      await t.pump(ms * 50);
      expect(t.lines, ['3.0']);
      await t.pump(ms * 60);
      expect(t.lines, ['4.0']);
      expect(controllers.last.status, AnimationStatus.completed);
      await t.pumpWidget(animated(ms * 40));
      expect(controllers.toSet(), hasLength(1));
      controllers.last.reverse();
      await t.pump(ms * 20);
      expect(t.lines, ['3.0']);
    });

    testTwk('is made anew when the keys change and disposed with the '
        'element, a run stopped', (t) async {
      final controllers = <AnimationController>[];
      Widget animated(int key) => HookBuilder(
        builder: (context) {
          controllers.add(
            useAnimationController(duration: ms * 100, keys: [key]),
          );
          return const Text('x');
        },
      );
      await t.pumpWidget(animated(1), size: (10, 1), maxFps: 100);
      await t.pumpWidget(animated(1));
      expect(controllers[1], same(controllers[0]));
      controllers.last.forward();
      await t.pumpWidget(animated(2));
      expect(controllers[1], isDisposed);
      expect(controllers[1].isAnimating, isFalse);
      controllers.last.forward();
      await t.pump(ms * 20);
      expect(controllers.last.isAnimating, isTrue);
      await t.pumpWidget(const Text('gone'));
      expect(controllers.last, isDisposed);
      expect(controllers.last.isAnimating, isFalse);
      await t.pump();
      expect(t.clock.pendingTimers, 0);
    });

    testTwk('takes its ticker from the vsync given', (t) async {
      final provider = Provider();
      await t.pumpWidget(
        HookBuilder(
          builder: (context) {
            useAnimationController(vsync: provider);
            return const Text('x');
          },
        ),
        size: (10, 1),
      );
      expect(provider.tickers, 1);
    });
  });

  testTwk('useTicker ticks in the frames of the app once started, calling '
      'the callback of the latest build, and is disposed with the element', (
    t,
  ) async {
    final ticks = <(String, Duration)>[];
    late Ticker ticker;
    Widget ticking(String name) => HookBuilder(
      builder: (context) {
        ticker = useTicker((elapsed) => ticks.add((name, elapsed)));
        return const Text('x');
      },
    );
    await t.pumpWidget(ticking('a'), size: (10, 1), maxFps: 100);
    await t.pump(ms * 20);
    expect(ticks, isEmpty);
    final first = ticker..start();
    await t.pump(ms * 15);
    await t.pumpWidget(ticking('b'));
    expect(ticker, same(first));
    await t.pump(ms * 10);
    // the frame that builds 'b' ticks before it builds
    expect(ticks, [
      ('a', Duration.zero),
      ('a', ms * 10),
      ('a', ms * 20),
      ('b', ms * 30),
    ]);
    await t.pumpWidget(const Text('gone'));
    expect(ticker.isActive, isFalse);
    expect(ticker.start, throwsA(isA<AssertionError>()));
    await t.pump();
    expect(t.clock.pendingTimers, 0);
  });
}
