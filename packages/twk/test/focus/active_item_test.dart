// ActiveItem: the item of a focused list its keys act on, which the
// hidden cursor rests on, the list's first cell where none is active or
// it is out of view.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('the hidden cursor rests on the active item of the focused list, '
      'follows it as it moves, and leaves it with none active', (t) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final cursor = ValueNotifier<int?>(1);
    addTearDown(cursor.dispose);
    await t.pumpWidget(
      Padding(
        padding: const EdgeInsets.only(left: 2, top: 1),
        child: Focus(
          focusNode: node,
          child: ValueListenableBuilder(
            valueListenable: cursor,
            builder: (_, c, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++)
                  ActiveItem(
                    active: i == c,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 1),
                      child: Text('item $i'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      size: (20, 6),
    );
    node.requestFocus();
    await t.pump();
    expect(t.cursorVisible, isFalse);
    expect(t.cursor, (2, 1 + 1));
    cursor.value = 3;
    await t.pump();
    expect(t.cursor, (2, 1 + 3));
    cursor.value = null;
    await t.pump();
    expect(t.cursor, (2, 1));
  });

  testTwk('an active item outside the focused widget takes nothing from '
      'it', (t) async {
    final list = FocusNode();
    final field = FocusNode();
    addTearDown(list.dispose);
    addTearDown(field.dispose);
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(focusNode: field, child: const Text('field')),
          Focus(
            focusNode: list,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ActiveItem(active: false, child: Text('a')),
                ActiveItem(active: true, child: Text('b')),
              ],
            ),
          ),
        ],
      ),
      size: (20, 6),
    );
    field.requestFocus();
    await t.pump();
    expect(t.cursor, (0, 0));
    list.requestFocus();
    await t.pump();
    expect(t.cursor, (0, 2));
  });
}
