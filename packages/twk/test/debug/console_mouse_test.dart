// The open console takes the mouse over it: the app below gets none of it
// there, the wheel scrolls the console, a press selects the row's record;
// outside it the app gets the mouse as ever.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk("over the console the mouse is its own; outside, the app's", (
    t,
  ) async {
    final taps = <(int, int)>[];
    await t.pumpWidget(
      Listener(
        behavior: HitTestBehavior.opaque,
        onDown: (e) => taps.add((e.x, e.y)),
        child: const SizedBox.expand(),
      ),
      size: (40, 20),
    );
    final console = t.binding.debug.console..openOnError = false;
    for (var i = 0; i < 30; i++) {
      t.logs.add(LogRecord(DateTime(2026), LogLevel.info, 'm$i'));
    }
    console.open();
    await t.pump();
    // the console is the bottom 10 rows: its header at row 10
    expect(t.lines[10], startsWith(' console'));
    await t.click(5, 3);
    expect(taps, [(5, 3)]);
    // a press on its last row selects the newest record, the app none
    await t.click(5, 19);
    expect(taps, [(5, 3)]);
    expect(console.selected!.message, 'm29');
    // the wheel scrolls it back, and on again
    await t.mouse(MouseKind.wheelUp, 5, 15);
    expect(console.below, 3);
    await t.mouse(MouseKind.wheelDown, 5, 15);
    expect(console.below, 0);
    // a record shown whole: a press selects its line
    console.showSelected();
    await t.pump();
    await t.click(5, 11);
    expect(console.selectedLine!.text, 'm29');
    expect(taps, [(5, 3)]);
  });
}
