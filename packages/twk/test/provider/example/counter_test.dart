// The counter of example/counter.dart: Up counts through the notifier,
// which is disposed of when the app quits on q.
import 'package:test/test.dart';
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../../example/provider/counter.dart' show Counter, CounterModel;

void main() {
  testTwk('Up counts, q quits', (t) async {
    final model = _Model();
    await t.pumpWidget(
      ChangeNotifierProvider<CounterModel>(
        create: (_) => model,
        child: const Counter(),
      ),
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
    expect(model.disposed, isTrue);
  });
}

final class _Model extends CounterModel {
  var disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
