// A negative duration is asserted where it is given; Duration.zero is legal.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const negative = Duration(milliseconds: -5);

final class _Host extends StatefulWidget {
  const _Host({super.key});

  @override
  State<_Host> createState() => _HostState();
}

final class _HostState extends State<_Host> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => const Text('x');
}

Matcher get _negativeAssert => throwsA(
  isA<AssertionError>().having(
    (e) => '${e.message}',
    'message',
    contains('negative'),
  ),
);

void main() {
  testTwk('negative durations assert, zero jumps', (t) async {
    final key = GlobalKey<State<_Host>>();
    await t.pumpWidget(_Host(key: key), size: (4, 1));
    final vsync = key.currentState! as TickerProvider;

    expect(
      () => AnimationController(vsync: vsync, duration: negative),
      _negativeAssert,
    );
    expect(
      () => AnimationController(vsync: vsync, reverseDuration: negative),
      _negativeAssert,
    );

    final c = AnimationController(vsync: vsync, duration: Duration.zero);
    addTearDown(c.dispose);
    c.forward();
    expect(c.value, 1);

    c.duration = negative;
    expect(c.forward, _negativeAssert);
    c
      ..duration = const Duration(milliseconds: 10)
      ..reverseDuration = negative;
    expect(c.reverse, _negativeAssert);
    c.reverseDuration = null;
    expect(() => c.animateTo(0.5, duration: negative), _negativeAssert);
    expect(() => c.repeat(period: negative), _negativeAssert);
    c.animateTo(0, duration: Duration.zero);
    expect(c.value, 0);
  });

  testTwk('a refused animateTo leaves the direction as it was', (t) async {
    final key = GlobalKey<State<_Host>>();
    await t.pumpWidget(_Host(key: key), size: (4, 1));
    final c = AnimationController(
      vsync: key.currentState! as TickerProvider,
      duration: Duration.zero,
      value: 1,
    );
    addTearDown(c.dispose);
    c.reverse();
    expect(c.status, AnimationStatus.dismissed);
    expect(() => c.animateTo(0.5, duration: negative), _negativeAssert);
    c.value = 0.5;
    expect(c.status, AnimationStatus.reverse);
  });
}
