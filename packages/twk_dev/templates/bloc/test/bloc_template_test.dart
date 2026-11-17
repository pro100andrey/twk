import 'package:bloc_template/bloc_template.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_bloc/twk_bloc.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('Up and Down count, r resets, q quits', (t) async {
    await t.pumpWidget(
      BlocProvider(create: (_) => CounterCubit(), child: const Counter()),
      size: (44, 6),
    );
    expect(t, containsLine(contains('Count: 0')));

    await t.press('up up up');
    await t.pump();
    expect(t, containsLine(contains('Count: 3')));
    expect(t, styleAt(9, 2, allOf(hasAttr(Attr.bold), hasFg(Color.green))));

    await t.press('down');
    await t.pump();
    expect(t, containsLine(contains('Count: 2')));

    await t.press('r');
    await t.pump();
    expect(t, containsLine(contains('Count: 0')));

    await t.press('q');
    expect(t.isRunning, isFalse);
  });

  test('the cubit emits the counts in order', () {
    expect(
      (CounterCubit()
            ..increment()
            ..decrement()
            ..decrement())
          .state,
      -1,
    );
  });
}
