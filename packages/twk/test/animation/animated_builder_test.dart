// AnimatedBuilder, Flutter's name for a ListenableBuilder over an
// animation: built again each frame the animation moves, with the child
// its parent built once.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

final class Moving extends StatefulWidget {
  const Moving({required this.builds, super.key});

  final List<String> builds;

  @override
  State<Moving> createState() => MovingState();
}

final class MovingState extends State<Moving>
    with TickerProviderStateMixin<Moving> {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.builds.add('parent');
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        widget.builds.add('builder');
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text('${(controller.value * 100).round()}:'), child!],
        );
      },
      child: Builder(
        builder: (context) {
          widget.builds.add('child');
          return const Text('x');
        },
      ),
    );
  }
}

void main() {
  testTwk('an AnimatedBuilder builds again as its animation moves, its '
      'child and its parent not', (t) async {
    final builds = <String>[];
    final key = GlobalKey<MovingState>();
    await t.pumpWidget(
      Moving(builds: builds, key: key),
      size: (10, 1),
    );
    expect(t, matchesScreen('0:x'));
    expect(builds, ['parent', 'builder', 'child']);
    final state = key.currentState!;
    expect(
      t.widget<AnimatedBuilder>(find.byType(AnimatedBuilder)).animation,
      same(state.controller),
    );
    builds.clear();
    state.controller.forward();
    await t.pump(const Duration(milliseconds: 50));
    expect(t, matchesScreen('50:x'));
    await t.pump(const Duration(milliseconds: 60));
    expect(t, matchesScreen('100:x'));
    expect(builds, isNotEmpty);
    expect(builds.toSet(), {'builder'});
  });
}
