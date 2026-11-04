// Text.line and Text.richLine set right, and cut at their start or at the
// edge, by the align and overflow they take.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('Text.line and Text.richLine take align and overflow', (t) async {
    await t.pumpWidget(
      const SizedBox(
        width: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.line('tag', align: TextAlign.right),
            Text.richLine([Span('tag')], align: TextAlign.right),
            Text.line('a long line', overflow: TextOverflow.clip),
            Text.line('a long line', overflow: TextOverflow.ellipsisStart),
          ],
        ),
      ),
      size: (8, 4),
    );
    expect(t.lines.take(4), [
      '     tag',
      '     tag',
      'a long l',
      '…ng line',
    ]);
  });
}
