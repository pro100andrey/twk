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

  Ticker _ticker(String name) => createTicker(
    (elapsed) => ticks.add((name, AppBinding.of(context).frameTime, elapsed)),
  );

  @override
  Widget build(BuildContext context) => const Text('ticking');
}

void main() {
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

  testTwk("a state's tickers are disposed with it: one ticking stops", (
    t,
  ) async {
    final key = GlobalKey<TickingState>();
    await t.pumpWidget(Ticking(key: key), size: (10, 1), maxFps: 100);
    final state = key.currentState!..a.start();
    final ticker = state.a;
    await t.pumpWidget(const Text('gone'));
    expect(ticker.isActive, isFalse);
    await t.pump();
    expect(t.clock.pendingTimers, 0);
    final ticks = state.ticks.length;
    await t.pump(const Duration(seconds: 1));
    expect(state.ticks, hasLength(ticks));
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
}
