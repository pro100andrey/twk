// A SelectionList whose rows shrink in the frame its cursor moves: no row
// asks the app about an index the new data has not, whether or not a
// LayoutBuilder stands above the list.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

final class _Filtered extends StatefulWidget {
  const _Filtered({required this.wrap, super.key});

  final Widget Function(Widget list) wrap;

  @override
  State<_Filtered> createState() => _FilteredState();
}

final class _FilteredState extends State<_Filtered> {
  final selection = SelectionController<String>();
  var rows = ['a', 'b', 'c', 'd'];

  @override
  void dispose() {
    selection.dispose();
    super.dispose();
  }

  void shrink() => setState(() {
    rows = ['a'];
    selection.cursor = 'a';
  });

  void grow() => setState(() {
    rows = ['a', 'b', 'c', 'd'];
    selection.cursor = 'd';
  });

  @override
  Widget build(BuildContext context) {
    final shown = rows;
    return widget.wrap(
      SelectionList<String>(
        itemCount: shown.length,
        keyOf: (i) => rows[i],
        itemEnabled: (i) => rows[i].isNotEmpty,
        controller: selection,
        autofocus: true,
        itemBuilder: (_, i) => Text(rows[i]),
      ),
    );
  }
}

void main() {
  for (final (name, wrap) in <(String, Widget Function(Widget))>[
    ('bare', (list) => list),
    (
      'under a LayoutBuilder',
      (list) => LayoutBuilder(builder: (_, _) => list),
    ),
    (
      'in a Box with a scrollbar',
      (list) => Box(
        border: const Border.all(),
        scrollbar: ScrollbarVisibility.always,
        child: list,
      ),
    ),
  ]) {
    testTwk('$name: rows dropped with the cursor on one of them', (t) async {
      final key = GlobalKey<_FilteredState>();
      await t.pumpWidget(
        _Filtered(key: key, wrap: wrap),
        size: (20, 8),
      );
      await t.press('down');
      await t.press('down');
      await t.press('down');
      await t.pump();
      key.currentState!.shrink();
      await t.pump();
      await t.pump();
      expect(t.logs.records, isEmpty);
    });
  }

  testTwk('a row told of the cursor while it was kept comes back as the cursor '
      'says', (t) async {
    final key = GlobalKey<_FilteredState>();
    await t.pumpWidget(
      _Filtered(key: key, wrap: (l) => l),
      size: (20, 8),
    );
    await t.press('down');
    await t.press('down');
    await t.press('down');
    await t.pump();
    key.currentState!.shrink();
    await t.pump();
    key.currentState!.grow();
    await t.pump();
    await t.pump();
    expect(t.logs.records, isEmpty);
    expect(t.lines.take(4).map((l) => l.trim()), ['a', 'b', 'c', '▎d']);
  });
}
