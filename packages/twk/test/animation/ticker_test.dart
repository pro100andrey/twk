// Tickers: a tick a frame with the time since the first, all of an app's
// in the same frames, none and no frame or timer once stopped, disposed
// with their state, and none outside an app.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

/// Two tickers that record the frame times they tick at.
final class Ticking extends StatefulWidget {
  const Ticking({super.key});

  @override
  State<Ticking> createState() => TickingState();
}

final class TickingState extends State<Ticking> with TickerProviderStateMixin {
  final ticks = <(String, Duration, Duration)>[];

  late final Ticker a = _ticker('a');
  late final Ticker b = _ticker('b');

  final _made = <Ticker>[];

  /// Whether dispose() stops the tickers first; off, a ticker still active
  /// is a state disposed with an active ticker.
  var stopsOnDispose = true;

  Ticker _ticker(String name) {
    final ticker = createTicker(
      (elapsed) => ticks.add((name, AppBinding.of(context).frameTime, elapsed)),
    );
    _made.add(ticker);
    return ticker;
  }

  @override
  void dispose() {
    if (stopsOnDispose) {
      for (final ticker in _made) {
        ticker.stop();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('ticking');
}

/// A state with one ticker.
final class Single extends StatefulWidget {
  const Single({super.key});

  @override
  State<Single> createState() => SingleState();
}

final class SingleState extends State<Single>
    with SingleTickerProviderStateMixin {
  var ticks = 0;

  late final Ticker ticker = createTicker((_) => ticks++);

  var stopsOnDispose = true;

  @override
  void dispose() {
    if (stopsOnDispose) {
      ticker.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('single');
}

void main() {
  testTwk('SingleTickerProviderStateMixin gives one ticker that ticks in '
      'the frames of the app and stops with the state', (t) async {
    final key = GlobalKey<SingleState>();
    await t.pumpWidget(Single(key: key), size: (10, 1), maxFps: 100);
    final state = key.currentState!..ticker.start();
    await t.pump(ms * 25);
    expect(state.ticks, 3);
    await t.pumpWidget(const SizedBox());
    final ticked = state.ticks;
    expect(state.ticker.isActive, isFalse);
    await t.pump(ms * 50);
    expect(state.ticks, ticked);
    expect(t.clock.pendingTimers, 0);
  });

  testTwk('SingleTickerProviderStateMixin asserts on a second ticker', (
    t,
  ) async {
    final key = GlobalKey<SingleState>();
    await t.pumpWidget(Single(key: key), size: (10, 1));
    final state = key.currentState!;
    expect(state.ticker, isNotNull);
    expect(() => state.createTicker((_) {}), throwsA(isA<AssertionError>()));
  });

  testTwk('SingleTickerProviderStateMixin gives a new ticker once the first '
      'is disposed, and muting reaches the live one only', (t) async {
    final key = GlobalKey<SingleState>();
    Widget app({required bool enabled}) => TickerMode(
      enabled: enabled,
      child: Single(key: key),
    );
    await t.pumpWidget(app(enabled: true), size: (10, 1), maxFps: 100);
    final state = key.currentState!;
    state.ticker.dispose();
    final again = state.createTicker((_) {});
    expect(again, isNot(same(state.ticker)));
    await t.pumpWidget(app(enabled: false));
    expect(again.muted, isTrue);
    await t.pumpWidget(app(enabled: true));
    expect(again.muted, isFalse);
    expect(state.ticker.muted, isFalse, reason: 'the disposed one is left');
  });

  testTwk('TickerProviderStateMixin drops a disposed ticker: muting reaches '
      'the live ones only', (t) async {
    final key = GlobalKey<TickingState>();
    Widget app({required bool enabled}) => TickerMode(
      enabled: enabled,
      child: Ticking(key: key),
    );
    await t.pumpWidget(app(enabled: true), size: (10, 1), maxFps: 100);
    final state = key.currentState!;
    final a = state.a..dispose();
    final b = state.b;
    await t.pumpWidget(app(enabled: false));
    expect(b.muted, isTrue);
    expect(a.muted, isFalse, reason: 'the disposed one is out of the group');
    await t.pumpWidget(app(enabled: true));
    expect(b.muted, isFalse);
  });

  testTwk('a ticker ticks once a frame from the next one, with the time '
      'since its first tick, and stopped asks for no frame', (t) async {
    final key = GlobalKey<TickingState>();
    await t.pumpWidget(Ticking(key: key), size: (10, 1), maxFps: 100);
    final state = key.currentState!;
    final start = t.clock.elapsed;
    state.a.start();
    expect(state.a.isActive, isTrue);
    await t.pump(ms * 35);
    expect(state.ticks, [
      for (var i = 0; i < 4; i++) ('a', start + ms * 10 * i, ms * 10 * i),
    ]);
    state.a.stop();
    expect(state.a.isActive, isFalse);
    await t.pump(const Duration(seconds: 1));
    expect(state.ticks, hasLength(4));
    expect(t.clock.pendingTimers, 0);
    state.a.start();
    await t.pump(ms * 15);
    expect(state.ticks.sublist(4).map((tick) => tick.$3), [
      Duration.zero,
      ms * 10,
    ]);
  });

  testTwk('the tickers of an app tick in the same frames', (t) async {
    final key = GlobalKey<TickingState>();
    await t.pumpWidget(Ticking(key: key), size: (10, 1), maxFps: 100);
    final state = key.currentState!;
    final start = t.clock.elapsed;
    state.a.start();
    await t.pump(ms * 15);
    state.b.start();
    await t.pump(ms * 10);
    expect(state.ticks, [
      ('a', start, Duration.zero),
      ('a', start + ms * 10, ms * 10),
      ('a', start + ms * 20, ms * 20),
      ('b', start + ms * 20, Duration.zero),
    ]);
  });

  testTwk("a state's tickers are disposed with it", (t) async {
    final key = GlobalKey<TickingState>();
    await t.pumpWidget(Ticking(key: key), size: (10, 1), maxFps: 100);
    final state = key.currentState!..a.start();
    state.a.stop();
    final ticker = state.a;
    await t.pumpWidget(const Text('gone'));
    expect(ticker.isActive, isFalse);
    await t.pump();
    expect(t.clock.pendingTimers, 0);
    final ticks = state.ticks.length;
    await t.pump(const Duration(seconds: 1));
    expect(state.ticks, hasLength(ticks));
  });

  testTwk('a TickerProviderStateMixin disposed with an active ticker is an '
      'assertion failure naming the state and the ticker', (t) async {
    final key = GlobalKey<TickingState>();
    await t.pumpWidget(Ticking(key: key), size: (10, 1), maxFps: 100);
    final state = key.currentState!
      ..stopsOnDispose = false
      ..a.start();
    await expectLater(
      t.pumpWidget(const Text('gone')),
      throwsA(
        isA<AssertionError>().having(
          (e) => '${e.message}',
          'message',
          allOf(
            contains('TickingState was disposed with an active Ticker'),
            contains('Ticker('),
          ),
        ),
      ),
    );
    state.a.stop();
  });

  testTwk('a SingleTickerProviderStateMixin disposed with an active ticker '
      'is an assertion failure', (t) async {
    final key = GlobalKey<SingleState>();
    await t.pumpWidget(Single(key: key), size: (10, 1), maxFps: 100);
    final state = key.currentState!
      ..stopsOnDispose = false
      ..ticker.start();
    await expectLater(
      t.pumpWidget(const Text('gone')),
      throwsA(
        isA<AssertionError>().having(
          (e) => '${e.message}',
          'message',
          contains('SingleState was disposed with an active Ticker'),
        ),
      ),
    );
    state.ticker.stop();
  });

  test('a ticker outside an app never ticks', () async {
    final ticks = <Duration>[];
    final clock = FakeClock();
    final ticker = clock.run(() => Ticker(ticks.add)..start());
    expect(ticker.isActive, isTrue);
    await clock.elapse(const Duration(seconds: 1));
    expect(ticks, isEmpty);
    expect(clock.pendingTimers, 0, reason: 'no timer to tick on');
    ticker.dispose();
    expect(ticker.isActive, isFalse);
  });

  test('starting a ticker that is active is a StateError', () {
    final ticker = Ticker((_) {})..start();
    expect(
      ticker.start,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'the ticker is active already',
        ),
      ),
    );
    ticker
      ..stop()
      ..start();
    expect(ticker.isActive, isTrue);
    ticker.dispose();
  });

  testTwk('a ticker below a TickerMode that is off ticks no more and asks '
      'for no frame; on again, it ticks on', (t) async {
    final key = GlobalKey<TickingState>();
    Widget app({required bool enabled}) => TickerMode(
      enabled: enabled,
      child: Ticking(key: key),
    );
    await t.pumpWidget(app(enabled: true), size: (10, 1), maxFps: 100);
    final state = key.currentState!..a.start();
    await t.pump(ms * 15);
    expect(state.ticks, hasLength(2));
    await t.pumpWidget(app(enabled: false));
    expect(state.a.isActive, isTrue);
    expect(state.a.muted, isTrue);
    final stopped = state.ticks.length;
    await t.pump(const Duration(seconds: 1));
    expect(state.ticks, hasLength(stopped));
    expect(t.clock.pendingTimers, 0);
    state.b.start();
    await t.pump(ms * 50);
    expect(state.ticks, hasLength(stopped), reason: 'b is muted too');
    await t.pumpWidget(app(enabled: true));
    await t.pump(ms * 15);
    expect(state.ticks.length, greaterThan(stopped + 2));
    expect(state.ticks.any((tick) => tick.$1 == 'b'), isTrue);
  });

  testTwk('TickerMode.of is true without a TickerMode, and a state is told '
      'when it changes', (t) async {
    final seen = <bool>[];
    Widget probe() => Builder(
      builder: (context) {
        seen.add(TickerMode.of(context));
        return const Text('x');
      },
    );
    await t.pumpWidget(probe(), size: (10, 1));
    await t.pumpWidget(TickerMode(enabled: false, child: probe()));
    await t.pumpWidget(TickerMode(enabled: true, child: probe()));
    expect(seen, [true, false, true]);
  });
}
