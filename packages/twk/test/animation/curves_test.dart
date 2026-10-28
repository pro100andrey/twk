// Curves from 0 to 1 and what they do in between, intervals and flipped
// curves; tweens of doubles, whole numbers and colors, chained to curves.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// [curve] at t = 0, 0.1, … 1.
List<double> samples(Curve curve) => [
  for (var i = 0; i <= 10; i++) curve.transform(i / 10),
];

void main() {
  group('Curves', () {
    const all = {
      'linear': Curves.linear,
      'ease': Curves.ease,
      'easeIn': Curves.easeIn,
      'easeOut': Curves.easeOut,
      'easeInOut': Curves.easeInOut,
      'fastOutSlowIn': Curves.fastOutSlowIn,
      'decelerate': Curves.decelerate,
      'bounceOut': Curves.bounceOut,
      'elasticOut': Curves.elasticOut,
    };

    test('each is exactly 0 at 0 and 1 at 1', () {
      for (final MapEntry(:key, value: curve) in all.entries) {
        expect(
          (curve.transform(0), curve.transform(1)),
          (0.0, 1.0),
          reason: key,
        );
      }
    });

    test('the cubic ones rise from 0 to 1 without going back', () {
      for (final curve in [
        Curves.ease,
        Curves.easeIn,
        Curves.easeOut,
        Curves.easeInOut,
        Curves.fastOutSlowIn,
        Curves.decelerate,
      ]) {
        final s = samples(curve);
        for (var i = 1; i < s.length; i++) {
          expect(s[i], greaterThanOrEqualTo(s[i - 1]), reason: '$curve');
        }
      }
    });

    test('easeIn starts slowly, easeOut fast, easeInOut is symmetric', () {
      expect(Curves.linear.transform(0.3), 0.3);
      expect(Curves.easeIn.transform(0.5), closeTo(0.315, 0.002));
      expect(Curves.easeOut.transform(0.5), closeTo(0.685, 0.002));
      expect(Curves.easeInOut.transform(0.5), closeTo(0.5, 0.002));
      expect(
        Curves.easeInOut.transform(0.2),
        closeTo(1 - Curves.easeInOut.transform(0.8), 0.002),
      );
      expect(Curves.decelerate.transform(0.5), 0.75);
    });

    test('bounceOut stays within 0 and 1 and comes back down after '
        'reaching 1; elasticOut overshoots 1', () {
      final bounce = samples(Curves.bounceOut);
      expect(bounce.every((v) => v >= 0 && v <= 1), isTrue);
      expect(Curves.bounceOut.transform(1 / 2.75), closeTo(1, 1e-9));
      expect(Curves.bounceOut.transform(0.5), lessThan(1));
      // the last bounce, the lowest
      expect(
        Curves.bounceOut.transform(2.625 / 2.75),
        closeTo(0.984375, 1e-9),
      );
      expect(
        Curves.bounceOut.transform(0.99),
        allOf(greaterThan(0.99), lessThan(1)),
      );
      expect(samples(Curves.elasticOut).any((v) => v > 1), isTrue);
    });

    test('Interval is 0 before its begin, 1 after its end, and its curve '
        'stretched between them', () {
      const curve = Interval(0.25, 0.75, curve: Curves.easeIn);
      expect(curve.transform(0.2), 0);
      expect(curve.transform(0.5), Curves.easeIn.transform(0.5));
      expect(curve.transform(0.8), 1);
    });

    test('flipped is the curve backwards, upside down', () {
      final flipped = Curves.easeIn.flipped;
      expect(flipped.transform(0.3), 1 - Curves.easeIn.transform(0.7));
      expect(flipped.flipped, same(Curves.easeIn));
    });
  });

  group('Tween', () {
    test('of doubles is as far from begin to end as t says, past them '
        'beyond 0 and 1', () {
      const tween = Tween<double>(begin: 10, end: 20);
      expect(
        [
          for (final t in [0.0, 0.25, 1.0, 1.5, -0.5]) tween.transform(t),
        ],
        [
          10,
          12.5,
          20,
          25,
          5,
        ],
      );
    });

    test('of another type is its begin and end at 0 and 1, and an '
        'UnsupportedError between them', () {
      const tween = Tween<String>(begin: 'a', end: 'b');
      expect((tween.transform(0), tween.transform(1)), ('a', 'b'));
      expect(() => tween.transform(0.5), throwsUnsupportedError);
    });

    test('IntTween rounds to the nearest whole number', () {
      const tween = IntTween(begin: 0, end: 10);
      expect(
        [
          for (final t in [0.0, 0.24, 0.26, 1.0]) tween.transform(t),
        ],
        [
          0,
          2,
          3,
          10,
        ],
      );
    });

    test('ColorTween blends RGB colors channel by channel, and switches '
        'halfway between colors of which one is not RGB', () {
      const blend = ColorTween(
        begin: Color.rgb(0, 100, 200),
        end: Color.rgb(100, 200, 0),
      );
      expect(blend.transform(0.5), const Color.rgb(50, 150, 100));
      const palette = ColorTween(begin: Color.red, end: Color.rgb(0, 0, 255));
      expect(palette.transform(0.49), Color.red);
      expect(palette.transform(0.5), const Color.rgb(0, 0, 255));
    });

    test('chained to a curve, it runs along it; evaluate reads the value '
        'of an animation', () {
      final tween = const Tween<double>(
        begin: 0,
        end: 100,
      ).chain(Curves.easeOut);
      expect(tween.transform(0.5), 100 * Curves.easeOut.transform(0.5));
      expect(tween.evaluate(ValueNotifier(0.5)), tween.transform(0.5));
    });

    test('a curve, a tween and a chain of them say what they are', () {
      expect(
        '${const Interval(0.25, 0.75)}',
        'Interval(0.25, 0.75, Curves.linear)',
      );
      expect('${Curves.easeIn.flipped}', 'Cubic(0.42, 0.0, 1.0, 1.0).flipped');
      expect(
        [Curves.decelerate, Curves.bounceOut, Curves.elasticOut].join(' '),
        'Curves.decelerate Curves.bounceOut Curves.elasticOut',
      );
      const tween = Tween<double>(begin: 0, end: 10);
      expect('$tween', 'Tween(0.0 → 10.0)');
      expect(
        '${tween.chain(Curves.easeOut)}',
        'Tween(0.0 → 10.0).chain(Cubic(0.0, 0.0, 0.58, 1.0))',
      );
    });
  });
}
