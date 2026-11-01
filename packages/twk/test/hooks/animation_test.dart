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

  _intervalTests();

  group('TickerMode', () {
    testTwk('useAnimationController stands still below a TickerMode that is '
        'off and goes on where it would have been when it is on', (t) async {
      late AnimationController controller;
      Widget app({required bool enabled}) => TickerMode(
        enabled: enabled,
        child: HookBuilder(
          builder: (context) {
            controller = useAnimationController(duration: ms * 100);
            return const Text('x');
          },
        ),
      );
      await t.pumpWidget(app(enabled: true), size: (10, 1), maxFps: 100);
      controller.forward();
      await t.pump(ms * 30);
      await t.pumpWidget(app(enabled: false));
      final held = controller.value;
      await t.pump(ms * 30);
      expect(controller.value, held);
      expect(controller.isAnimating, isTrue);
      expect(t.clock.pendingTimers, 0);
      await t.pumpWidget(app(enabled: true));
      await t.pump(ms * 20);
      expect(controller.value, greaterThan(0.7), reason: 'its time went on');
      await t.pump(ms * 60);
      expect(controller.status, AnimationStatus.completed);
    });

    testTwk('useTicker is muted below a TickerMode that is off and ticks on '
        'when it is on again', (t) async {
      final ticks = <Duration>[];
      late Ticker ticker;
      Widget app({required bool enabled}) => TickerMode(
        enabled: enabled,
        child: HookBuilder(
          builder: (context) {
            ticker = useTicker(ticks.add);
            return const Text('x');
          },
        ),
      );
      await t.pumpWidget(app(enabled: true), size: (10, 1), maxFps: 100);
      ticker.start();
      await t.pump(ms * 15);
      await t.pumpWidget(app(enabled: false));
      final seen = ticks.length;
      await t.pump(ms * 50);
      expect(ticks, hasLength(seen));
      expect(ticker.muted, isTrue);
      expect(t.clock.pendingTimers, 0);
      await t.pumpWidget(app(enabled: true));
      await t.pump(ms * 20);
      expect(ticks.length, greaterThan(seen));
    });
  });
}

/// Pumps until the clock reads [at].
Future<void> _until(TwkTester t, Duration at) => t.pump(at - t.clock.elapsed);

void _intervalTests() {
  group('useInterval', () {
    testTwk('ticks once a period on the app clock, the callback of the '
        'latest build, and stops with the element', (t) async {
      final ticks = <String>[];
      Widget app(String name) => HookBuilder(
        builder: (context) {
          useInterval(ms * 100, () => ticks.add(name));
          return const Text('x');
        },
      );
      await t.pumpWidget(app('a'), size: (10, 1));
      await _until(t, ms * 250);
      expect(ticks, ['a', 'a']);
      await t.pumpWidget(app('b'));
      await _until(t, ms * 450);
      expect(ticks, ['a', 'a', 'b', 'b']);
      await t.pumpWidget(const Text('gone'));
      await _until(t, ms * 900);
      expect(ticks, hasLength(4));
      expect(t.clock.pendingTimers, 0);
    });

    testTwk('a tick can set state: the widget is redrawn', (t) async {
      await t.pumpWidget(
        HookBuilder(
          builder: (context) {
            final n = useState(0);
            useInterval(ms * 100, () => n.value++);
            return Text('${n.value}');
          },
        ),
        size: (10, 1),
      );
      await _until(t, ms * 350);
      expect(t.lines, ['3']);
    });

      'a changed period restarts it at the next multiple of the new one',
      'a changed period restarts it at the next multiple of the new one, the same one does not',
      (t) async {
        var ticks = 0;
        Widget app(Duration period) => HookBuilder(
          builder: (context) {
            useInterval(period, () => ticks++);
            return const Text('x');
          },
        );
        await t.pumpWidget(app(ms * 100), size: (10, 1));
        await _until(t, ms * 250);
        expect(ticks, 2);
        await t.pumpWidget(app(ms * 100));
        await _until(t, ms * 350);
        expect(ticks, 3);
        await t.pumpWidget(app(ms * 50));
        await _until(t, ms * 600);
        expect(ticks, 3 + 5);
      },
    );

    testTwk('is muted below a TickerMode that is off, asks for no frame, '
        'and ticks on, none made up for, when it is on again', (t) async {
      var ticks = 0;
      Widget app({required bool enabled}) => TickerMode(
        enabled: enabled,
        child: HookBuilder(
          builder: (context) {
            useInterval(ms * 100, () => ticks++);
            return const Text('x');
          },
        ),
      );
      await t.pumpWidget(app(enabled: true), size: (10, 1));
      await _until(t, ms * 250);
      expect(ticks, 2);
      await t.pumpWidget(app(enabled: false));
      await _until(t, ms * 1250);
      expect(ticks, 2);
      expect(t.clock.pendingTimers, 0);
      await t.pumpWidget(app(enabled: true));
      await _until(t, ms * 1450);
      expect(ticks, 4);
    });
  });
}
