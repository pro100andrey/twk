// A DiffView below a SelectionArea: its lines selected with the mouse and
// copied as they read (the code as shown, numbers and signs left out), the
// selected part drawn, side by side too, and a view that is not selectable.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

const source = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,4 +1,4 @@
 void main() {
-  print('hello');
+  print('hi');
   return;
 }
@@ -10,4 +10,3 @@ void other() {
 a();
-b(1);
-c(2);
+b(3);
 d();
''';

final int selected = const Color.indexed(237).value;

Widget app({
  required DiffLayout layout,
  required void Function(String) onCopy,
  bool selectable = true,
  Diff? diff,
  SelectionAreaController? controller,
}) => Theme.terminal(
  child: SelectionArea(
    onCopy: onCopy,
    controller: controller,
    child: DiffView(
      diff ?? Diff.parse(source),
      layout: layout,
      selectable: selectable,
    ),
  ),
);

/// The columns of row [y] from [from] to [to] with the selection's
/// background, as `x`, and without, as `.`.
String marked(TwkTester t, int y, int from, int to) => [
  for (var x = from; x < to; x++)
    if (t.vt.cell(x, y).bg == selected) 'x' else '.',
].join();

void main() {
  testTwk('unified: a drag copies the code of the lines, numbers and signs '
      'left out, and draws only the code selected', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      app(layout: DiffLayout.unified, onCopy: copies.add),
      size: (42, 12),
    );
    // row 1 is ' 1  1   void main() {'; the code starts at column 8
    await t.mouse(MouseKind.down, 13, 1);
    await t.mouse(MouseKind.drag, 12, 3);
    await t.mouse(MouseKind.up, 12, 3);
    await t.pump();
    expect(copies, ["main() {\n  print('hello');\n  pri"]);
    expect(marked(t, 1, 0, 20), '.............xxxxxxx');
    expect(marked(t, 2, 0, 12), '........xxxx');
    expect(marked(t, 3, 0, 14), '........xxxxx.');
  });

  testTwk('unified: a press on the gutter selects nothing of it, the rows '
      'left out and the file are selected as shown, all of the diff is '
      'selected by selectAll', (t) async {
    final copies = <String>[];
    final controller = SelectionAreaController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      app(
        layout: DiffLayout.unified,
        onCopy: copies.add,
        controller: controller,
      ),
      size: (42, 12),
    );
    controller.selectAll();
    await t.pump();
    expect(
      controller.text,
      [
        'lib/a.dart',
        'void main() {',
        "  print('hello');",
        "  print('hi');",
        '  return;',
        '}',
        '⋯ 5 unchanged lines  void other() {',
        'a();',
        'b(1);',
        'c(2);',
        'b(3);',
        'd();',
      ].join('\n'),
    );
    // the number and the sign are not drawn selected
    expect(marked(t, 1, 0, 9), '........x');
    expect(marked(t, 6, 0, 12), '......xxxxxx');
  });

  testTwk('unified: rows that scroll in by a drag past the bottom are in '
      'the copy', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      app(layout: DiffLayout.unified, onCopy: copies.add),
      size: (42, 5),
    );
    await t.mouse(MouseKind.down, 8, 1);
    await t.mouse(MouseKind.drag, 20, 4);
    await t.pump(const Duration(milliseconds: 600));
    await t.mouse(MouseKind.up, 20, 4);
    await t.pump();
    final lines = copies.single.split('\n');
    expect(lines.first, 'void main() {');
    expect(lines.length, greaterThan(4));
    expect(lines.take(3), [
      'void main() {',
      "  print('hello');",
      "  print('hi');",
    ]);
  });

  testTwk('a tab is copied as the blanks it is drawn as', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      app(
        layout: DiffLayout.unified,
        onCopy: copies.add,
        diff: Diff.between('a\tb\n', 'ab\tc\n'),
      ),
      size: (30, 3),
    );
    await t.mouse(MouseKind.down, 6, 0);
    await t.mouse(MouseKind.drag, 20, 1);
    await t.mouse(MouseKind.up, 20, 1);
    await t.pump();
    expect(copies.single, 'a   b\nab  c');
  });

  testTwk('side by side: each side of a row is a text of its own, the '
      'sides of a row joined by a tab, a side without a line none', (t) async {
    final copies = <String>[];
    final controller = SelectionAreaController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      app(
        layout: DiffLayout.sideBySide,
        onCopy: copies.add,
        controller: controller,
      ),
      size: (49, 11),
    );
    controller.selectAll();
    await t.pump();
    expect(controller.text.split('\n'), [
      'lib/a.dart',
      'void main() {\tvoid main() {',
      "  print('hello');\t  print('hi');",
      '  return;\t  return;',
      '}\t}',
      '⋯ 5 unchanged lines  void other() {',
      'a();\ta();',
      'b(1);\tb(3);',
      'c(2);',
      'd();\td();',
    ]);
    controller.clear();
    await t.pump();
    // from the 'p' of the old print to the 'p' of the new one
    await t.mouse(MouseKind.down, 7, 2);
    await t.mouse(MouseKind.drag, 32, 2);
    await t.mouse(MouseKind.up, 32, 2);
    await t.pump();
    expect(copies.single, "print('hello');\t  p");
    expect(marked(t, 2, 5, 24), '..xxxxxxxxxxxxxxx..');
    expect(marked(t, 2, 25, 38), '.....xxx.....');
  });

  testTwk('not selectable, its rows are left to the area as texts of their '
      'own, the code and the gutter', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      app(layout: DiffLayout.unified, onCopy: copies.add, selectable: false),
      size: (42, 12),
    );
    await t.mouse(MouseKind.down, 0, 1);
    await t.mouse(MouseKind.drag, 12, 1);
    await t.mouse(MouseKind.up, 12, 1);
    await t.pump();
    expect(copies.single, startsWith(' 1  1'));
  });
}
