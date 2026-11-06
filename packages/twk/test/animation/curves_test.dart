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

  group('the rest of the Curves family', () {
    // at t = 0.1, 0.3, 0.5, 0.7, 0.9, worked out apart from the package
    // (a cubic Bezier solved to 1e-12) from the formulas Flutter's Curves
    // has them by
    const at = [0.1, 0.3, 0.5, 0.7, 0.9];
    const family = <String, (Curve, List<double>)>{
      'fastLinearToSlowEaseIn': (
        Curves.fastLinearToSlowEaseIn,
        [0.5925, 0.9432, 0.9883, 0.9983, 1.0000],
      ),
      'easeInToLinear': (
        Curves.easeInToLinear,
        [0.0051, 0.0238, 0.0799, 0.2805, 0.7385],
      ),
      'linearToEaseOut': (
        Curves.linearToEaseOut,
        [0.2615, 0.7195, 0.9201, 0.9762, 0.9949],
      ),
      'easeInSine': (
        Curves.easeInSine,
        [0.0110, 0.1027, 0.2912, 0.5652, 0.8708],
      ),
      'easeInQuad': (
        Curves.easeInQuad,
        [0.0205, 0.1000, 0.2560, 0.5180, 0.8455],
      ),
      'easeInCubic': (
        Curves.easeInCubic,
        [0.0116, 0.0519, 0.1453, 0.3636, 0.7583],
      ),
      'easeInQuart': (
        Curves.easeInQuart,
        [0.0043, 0.0212, 0.0625, 0.1944, 0.7242],
      ),
      'easeInQuint': (
        Curves.easeInQuint,
        [0.0067, 0.0233, 0.0549, 0.1423, 0.4922],
      ),
      'easeInExpo': (
        Curves.easeInExpo,
        [0.0053, 0.0172, 0.0372, 0.0939, 0.4875],
      ),
      'easeInCirc': (
        Curves.easeInCirc,
        [0.0093, 0.0466, 0.1187, 0.2497, 0.5224],
      ),
      'easeInBack': (
        Curves.easeInBack,
        [-0.0427, -0.0944, -0.0636, 0.1437, 0.6531],
      ),
      'easeOutSine': (
        Curves.easeOutSine,
        [0.1508, 0.4608, 0.7357, 0.9155, 0.9919],
      ),
      'easeOutQuad': (
        Curves.easeOutQuad,
        [0.1872, 0.5311, 0.7713, 0.9127, 0.9837],
      ),
      'easeOutCubic': (
        Curves.easeOutCubic,
        [0.2757, 0.6778, 0.8751, 0.9638, 0.9966],
      ),
      'easeOutQuart': (
        Curves.easeOutQuart,
        [0.3882, 0.7621, 0.9146, 0.9772, 0.9981],
      ),
      'easeOutQuint': (
        Curves.easeOutQuint,
        [0.3981, 0.8430, 0.9660, 0.9950, 0.9999],
      ),
      'easeOutExpo': (
        Curves.easeOutExpo,
        [0.4798, 0.8940, 0.9778, 0.9968, 0.9999],
      ),
      'easeOutCirc': (
        Curves.easeOutCirc,
        [0.6041, 0.8786, 0.9586, 0.9890, 0.9990],
      ),
      'easeOutBack': (
        Curves.easeOutBack,
        [0.4483, 0.9217, 1.0676, 1.0831, 1.0369],
      ),
      'easeInOutSine': (
        Curves.easeInOutSine,
        [0.0272, 0.1935, 0.5032, 0.8102, 0.9733],
      ),
      'easeInOutQuad': (
        Curves.easeInOutQuad,
        [0.0227, 0.1873, 0.5148, 0.8254, 0.9767],
      ),
      'easeInOutCubic': (
        Curves.easeInOutCubic,
        [0.0158, 0.1315, 0.5169, 0.8909, 0.9913],
      ),
      'easeInOutQuart': (
        Curves.easeInOutQuart,
        [0.0064, 0.0860, 0.5960, 0.9304, 0.9945],
      ),
      'easeInOutQuint': (
        Curves.easeInOutQuint,
        [0.0052, 0.0687, 0.6766, 0.9461, 0.9957],
      ),
      'easeInOutExpo': (
        Curves.easeInOutExpo,
        [0.0038, 0.0474, 0.5000, 0.9526, 0.9962],
      ),
      'easeInOutCirc': (
        Curves.easeInOutCirc,
        [0.0224, 0.1210, 0.6024, 0.8965, 0.9792],
      ),
      'easeInOutBack': (
        Curves.easeInOutBack,
        [-0.0663, -0.0493, 0.6067, 1.0693, 1.0624],
      ),
      'slowMiddle': (
        Curves.slowMiddle,
        [0.2869, 0.4511, 0.5000, 0.5489, 0.7131],
      ),
      'bounceIn': (Curves.bounceIn, [0.0119, 0.0694, 0.2344, 0.3194, 0.9244]),
      'bounceInOut': (
        Curves.bounceInOut,
        [0.0300, 0.0450, 0.5000, 0.9550, 0.9700],
      ),
      'elasticIn': (
        Curves.elasticIn,
        [0.0000, -0.0000, 0.0000, -0.0000, 0.0000],
      ),
      'elasticInOut': (
        Curves.elasticInOut,
        [0.0020, 0.0312, 0.5000, 0.9688, 0.9980],
      ),
      'fastEaseInToSlowEaseOut': (
        Curves.fastEaseInToSlowEaseOut,
        [0.2383, 0.7604, 0.9422, 0.9875, 0.9976],
      ),
      'easeInOutCubicEmphasized': (
        Curves.easeInOutCubicEmphasized,
        [0.0935, 0.8405, 0.9506, 0.9868, 0.9988],
      ),
    };

    test('each is exactly 0 at 0 and 1 at 1, and what Flutter has between', () {
      for (final MapEntry(:key, value: (curve, expected)) in family.entries) {
        expect(
          (curve.transform(0), curve.transform(1)),
          (0.0, 1.0),
          reason: key,
        );
        for (var i = 0; i < at.length; i++) {
          expect(
            curve.transform(at[i]),
            closeTo(expected[i], 0.01),
            reason: '$key at ${at[i]}',
          );
        }
      }
    });

    test('the Back curves go out of 0..1, the bounce ones do not', () {
      expect(samples(Curves.easeInBack).any((v) => v < 0), isTrue);
      expect(samples(Curves.easeOutBack).any((v) => v > 1), isTrue);
      expect(samples(Curves.easeInOutBack).any((v) => v < 0), isTrue);
      expect(samples(Curves.easeInOutBack).any((v) => v > 1), isTrue);
      for (final curve in [Curves.bounceIn, Curves.bounceInOut]) {
        expect(samples(curve).every((v) => v >= 0 && v <= 1), isTrue);
      }
    });

    test('bounceIn is bounceOut backwards, bounceInOut is symmetric', () {
      for (final t in [0.1, 0.4, 0.8]) {
        expect(
          Curves.bounceIn.transform(t),
          closeTo(1 - Curves.bounceOut.transform(1 - t), 1e-12),
        );
        expect(
          Curves.bounceInOut.transform(t),
          closeTo(1 - Curves.bounceInOut.transform(1 - t), 1e-12),
        );
      }
    });

    test('the elastic ones swing out of 0..1', () {
      expect(samples(Curves.elasticIn).any((v) => v < 0), isTrue);
      expect(samples(Curves.elasticInOut).any((v) => v < 0), isTrue);
      expect(samples(Curves.elasticInOut).any((v) => v > 1), isTrue);
      expect(Curves.elasticInOut.transform(0.5), closeTo(0.5, 1e-9));
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
