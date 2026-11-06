// A state machine fed event by event: the calls read as a trace, not a
// cascade.
// ignore_for_file: cascade_invocations
// ScrollInput on its own, with no widget and no clock: the times are the
// ones the test passes with each event, which is the whole of its state.
// (Synthetic traces: nothing here was checked on a recorded session.)
import 'package:test/test.dart';
import 'package:twk/twk.dart';

void main() {
  const down = 1;
  const up = -1;

  Duration ms(num n) => Duration(microseconds: (n * 1000).round());

  /// Feeds [count] events [way] along [axis] [gap] ms apart from [from] ms,
  /// and returns the time after the last.
  num feed(
    ScrollInput input,
    int count, {
    required num from,
    required num gap,
    int way = down,
    Axis axis = Axis.vertical,
  }) {
    var at = from;
    for (var i = 0; i < count; i++) {
      input.event(ms(at), axis, way);
      at += gap;
    }
    return at - gap;
  }

  group('sparse input', () {
    test('moves step rows an event, whole, however many come in a frame', () {
      final input = ScrollInput(const ScrollBehavior());
      input.event(ms(0), Axis.vertical, down);
      input.event(ms(20), Axis.vertical, down);
      expect(input.hasPending, isTrue);
      expect(input.take(), const ScrollDelta(6, 0));
      expect(input.take(), isNull);
      expect(input.hasPending, isFalse);
      expect(input.isDense, isFalse);
    });

    test('a notch a frame stays at 3 for a long session, either way', () {
      final input = ScrollInput(const ScrollBehavior());
      final moves = <int?>[];
      for (var i = 0; i < 40; i++) {
        input.event(ms(i * 25), Axis.vertical, i < 30 ? down : up);
        moves.add(input.take()?.rows);
      }
      expect(moves, [...List.filled(30, 3), ...List.filled(10, -3)]);
      expect(input.isDense, isFalse);
    });

    test('one pair of events under 2 ms apart is not yet dense: two '
        'notches read together', () {
      final input = ScrollInput(const ScrollBehavior());
      input
        ..event(ms(0), Axis.vertical, down)
        ..event(ms(1), Axis.vertical, down);
      expect(input.isDense, isFalse);
      expect(input.take(), const ScrollDelta(6, 0));
    });

    test('a pair is of one stream: events 1 ms apart that turn are not', () {
      final input = ScrollInput(const ScrollBehavior());
      for (var i = 0; i < 6; i++) {
        input.event(ms(i), Axis.vertical, i.isEven ? down : up);
      }
      expect(input.isDense, isFalse);
    });

    test("step is the behavior's", () {
      final input = ScrollInput(const ScrollBehavior(step: 5));
      input.event(ms(0), Axis.vertical, up);
      expect(input.take(), const ScrollDelta(-5, 0));
    });
  });

  group('dense input', () {
    test('two pairs in a stream decide it, for the session: the third event '
        'is the first of a row each', () {
      final input = ScrollInput(const ScrollBehavior());
      feed(input, 3, from: 0, gap: 0.1);
      expect(input.isDense, isTrue);
      // 3 + 3 sparse, then 1 + 3 / 30 = 1.1 rows
      expect(input.take(), const ScrollDelta(7, 0));
      // a slow stroke later, an event a refresh, is still dense
      input.event(ms(1000), Axis.vertical, down);
      expect(input.isDense, isTrue);
      expect(input.take()!.rows, 1);
    });

    test('the n-th event of a stream moves 1 + n / 30 rows, up to 3, the '
        'fraction carried', () {
      final input = ScrollInput(const ScrollBehavior());
      feed(input, 80, from: 0, gap: 0.1);
      // 6 sparse; n = 3 to 60: the sum of 1 + n / 30 is 118.9, the 0.9
      // carried on; n = 61 to 80: 3 a row, 20 events
      expect(input.take(), const ScrollDelta(6 + 118 + 60, 0));
    });

    test('the largest factor is accelMax, 3 rows an event at most', () {
      final input = ScrollInput(const ScrollBehavior());
      feed(input, 3, from: 0, gap: 0.1);
      input.take();
      feed(input, 100, from: 1, gap: 8);
      // events 8 ms apart are not a pair, but the session is dense: the
      // stream goes on, n = 4 to 103
      final rows = input.take()!.rows;
      // sum of min(3, 1 + n / 30) for n = 4 to 103, plus the carry of 0.1
      var sum = 0.1;
      for (var n = 4; n <= 103; n++) {
        sum += 1 + (n / 30).clamp(0, 2);
      }
      expect(rows, sum.floor());
    });

    test('a stream ends after 80 ms, the next starts at 1 + 1 / 30 again; '
        'the fraction carries on the same way', () {
      final input = ScrollInput(const ScrollBehavior());
      feed(input, 3, from: 0, gap: 0.1);
      input.take();
      // 90 ms later: a new stream, n = 1: 1.033 rows, plus the 0.1 carried
      input.event(ms(100), Axis.vertical, down);
      expect(input.take()!.rows, 1);
      input.event(ms(300), Axis.vertical, down);
      input.event(ms(400), Axis.vertical, down);
      expect(input.take()!.rows, 2);
    });

    test('a turn moves at once, without what the stroke before had built, '
        'and drops the fraction', () {
      final input = ScrollInput(const ScrollBehavior());
      final end = feed(input, 60, from: 0, gap: 0.1);
      input.take();
      // the 61st would have moved 3; the turn starts again at n = 1
      input.event(ms(end + 0.1), Axis.vertical, up);
      expect(input.take(), const ScrollDelta(-1, 0));
      // the fraction of the stroke down, 0.9 + 0.033, was not carried: ten
      // events of 1.03 .. 1.33 rows give 10 + the sum of n / 30 = 1.83 -> 11
      // with no carry in, 10 + 1.83 = 11.83 rows less the first's 1.033
      feed(input, 9, from: end + 0.2, gap: 0.1, way: up);
      expect(input.take()!.rows, -10);
    });

    test('a pause and then the other way is a turn too; the same way after '
        'a pause carries', () {
      final input = ScrollInput(const ScrollBehavior());
      feed(input, 3, from: 0, gap: 0.1); // carries 0.1
      input.take();
      input.event(ms(500), Axis.vertical, up);
      input.take();
      // the carry of the way down is gone: n = 1, 2 .. under a row each
      // give 1.033 and 2.1 together
      feed(input, 2, from: 600, gap: 0.1, way: up);
      expect(input.take()!.rows, -2);
    });

    test('dense moves are denseStep times the factor', () {
      final input = ScrollInput(const ScrollBehavior(denseStep: 2));
      feed(input, 3, from: 0, gap: 0.1);
      // 3 + 3, then 2 * 1.1 = 2.2
      expect(input.take()!.rows, 8);
    });

    test('ScrollBehavior.fixed moves step an event, dense or not', () {
      final input = ScrollInput(const ScrollBehavior.fixed(2));
      feed(input, 10, from: 0, gap: 0.1);
      expect(input.take(), const ScrollDelta(20, 0));
      expect(input.isDense, isTrue);
    });
  });

  group('the axes', () {
    test('a stroke along one axis drops the sideways noise a trackpad adds '
        'once it leads by two events', () {
      final input = ScrollInput(const ScrollBehavior());
      // h v v v h v : the first events move both axes, nothing held back
      input.event(ms(0), Axis.horizontal, down);
      input.event(ms(10), Axis.vertical, down);
      input.event(ms(20), Axis.vertical, down);
      expect(input.take(), const ScrollDelta(6, 3));
      // the vertical leads by one more: locked; the sideways is held
      input.event(ms(30), Axis.vertical, down);
      input.event(ms(40), Axis.horizontal, down);
      input.event(ms(50), Axis.vertical, down);
      expect(input.take(), const ScrollDelta(6, 0));
      // the gesture ends, and what was held is dropped
      input.event(ms(500), Axis.vertical, down);
      expect(input.take(), const ScrollDelta(3, 0));
    });

    test('the other axis overtaking by two moves the lock and gives what it '
        'held', () {
      final input = ScrollInput(const ScrollBehavior());
      feed(input, 3, from: 0, gap: 10);
      input.take();
      // horizontal: held while it trails, then it leads by two
      for (var i = 0; i < 4; i++) {
        input.event(ms(40 + i * 10), Axis.horizontal, down);
      }
      // 3 vertical, 4 horizontal: leads by one, held: 12 columns
      expect(input.take(), isNull);
      input.event(ms(80), Axis.horizontal, down);
      input.event(ms(90), Axis.horizontal, down);
      // 3 against 6 events: the lock moved, the held given
      expect(input.take(), const ScrollDelta(0, 18));
    });

    test('with no axisLock both axes move', () {
      final input = ScrollInput(const ScrollBehavior(axisLock: false));
      for (var i = 0; i < 5; i++) {
        input.event(ms(i * 10), Axis.vertical, down);
      }
      input.event(ms(60), Axis.horizontal, down);
      expect(input.take(), const ScrollDelta(15, 3));
    });
  });

  group('cancel', () {
    test('drops what waits, the carry and the streams, not the density', () {
      final input = ScrollInput(const ScrollBehavior());
      feed(input, 3, from: 0, gap: 0.1);
      expect(input.hasPending, isTrue);
      input.cancel();
      expect(input.hasPending, isFalse);
      expect(input.take(), isNull);
      expect(input.isDense, isTrue);
      // a stream again from n = 1, no carry
      input.event(ms(1), Axis.vertical, down);
      expect(input.take()!.rows, 1);
    });
  });

  group('ScrollBehavior', () {
    test('is equal by its fields, and copyWith changes one', () {
      expect(const ScrollBehavior(), const ScrollBehavior());
      expect(const ScrollBehavior().hashCode, const ScrollBehavior().hashCode);
      expect(const ScrollBehavior().copyWith(step: 1).step, 1);
      expect(
        const ScrollBehavior().copyWith(step: 1),
        isNot(const ScrollBehavior()),
      );
      expect(
        const ScrollBehavior(),
        const ScrollBehavior().copyWith(axisLock: true),
      );
    });

    test('says its fields in toString', () {
      expect(
        '${const ScrollBehavior()}',
        'ScrollBehavior(step 3, denseStep 1.0, accel 30 events up to 3.0, '
            'dense under 2.0 ms, stream ends after 80 ms, axisLock true)',
      );
    });
  });
}
