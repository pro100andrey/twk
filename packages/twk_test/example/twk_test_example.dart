// A counter and its tests: the app runs on a terminal in memory, the keys
// go in as a terminal sends them, and the screen is read back.
//
//   dart test example/twk_test_example.dart
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

final class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => setState(() => _n++),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Box(
      border: const .all(type: .rounded),
      padding: const .all(1),
      child: Text.rich(['Count: '.dim, '$_n'.bold.fg(.green)]),
    ),
  );
}

void main() {
  testTwk('Up counts', (t) async {
    await t.pumpWidget(const Counter(), size: (20, 5));
    expect(
      t,
      matchesScreen('''
╭──────────────────╮
│                  │
│ Count: 0         │
│                  │
╰──────────────────╯
'''),
    );

    await t.press('up up up');
    await t.pump();
    expect(t, containsLine('│ Count: 3         │'));
    expect(t, styleAt(9, 2, allOf(hasAttr(Attr.bold), hasFg(Color.green))));
  });

  testTwk('q quits', (t) async {
    await t.pumpWidget(const Counter());
    await t.press('q');
    expect(t.isRunning, isFalse);
  });
}
