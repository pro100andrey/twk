// The counter of example/counter.dart: Up counts through the cubit, which
// is closed when the app quits on q.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_bloc/twk_bloc.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/counter.dart' show Counter, CounterCubit;

void main() {
  testTwk('Up counts, q quits', (t) async {
    final cubit = CounterCubit();
    await t.pumpWidget(
      BlocProvider(create: (_) => cubit, child: const Counter()),
      size: (24, 6),
    );
    expect(
      t,
      matchesScreen('''
╭──────────────────────╮
│                      │
│ Count: 0             │
│                      │
│                      │
╰── up: count  q: quit ╯
'''),
    );
    await t.press('up up up');
    await t.pump();
    expect(t, containsLine('│ Count: 3             │'));
    expect(t, styleAt(9, 2, allOf(hasAttr(Attr.bold), hasFg(Color.green))));
    await t.press('q');
    expect(t.isRunning, isFalse);
    expect(cubit.isClosed, isTrue);
  });
}
