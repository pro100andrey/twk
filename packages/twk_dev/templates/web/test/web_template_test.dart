import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';
import 'package:web_template/web_template.dart';

void main() {
  testTwk('Up counts, q quits', (t) async {
    await t.pumpWidget(const Counter(), size: (24, 6));
    expect(t, containsLine(contains('Count: 0')));

    await t.press('up up up');
    await t.pump();
    expect(t, containsLine(contains('Count: 3')));

    await t.press('q');
    expect(t.isRunning, isFalse);
  });
}
