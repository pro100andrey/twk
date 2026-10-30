// HitRow: the targets of a row of spans where they are drawn, and the
// hidden cursor on the active one while the row has the focus.
import 'package:test/test.dart';
import 'package:twk/src/text/hit_row.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('the hidden cursor rests on the first cell of the active target '
      'of the focused row, and on the row with none', (t) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final active = ValueNotifier(1);
    addTearDown(active.dispose);
    final hits = HitRow();
    await t.pumpWidget(
      Padding(
        padding: const EdgeInsets.only(left: 2, top: 1),
        child: Focus(
          focusNode: node,
          child: ValueListenableBuilder(
            valueListenable: active,
            builder: (context, a, _) => hits.row(
              [
                for (final (i, label) in ['one', 'two', 'three'].indexed) ...[
                  if (i > 0) (span: const Span(' │ '), target: -1),
                  (span: Span(label), target: i),
                ],
              ],
              segmenterOf(context),
              active: a,
            ),
          ),
        ),
      ),
      size: (30, 3),
    );
    node.requestFocus();
    await t.pump();
    expect(t.lines[1], '  one │ two │ three');
    expect(t.cursorVisible, isFalse);
    expect(t.cursor, (2 + 6, 1));
    active.value = 2;
    await t.pump();
    expect(t.cursor, (2 + 12, 1));
    expect(hits.at(12), 2);
    active.value = -1;
    await t.pump();
    expect(t.cursor, (2, 1));
  });
}
