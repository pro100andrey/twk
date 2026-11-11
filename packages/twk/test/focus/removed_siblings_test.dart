// The focus moved off a node removed in the same frame as its previous
// sibling.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget _field(String label) => Focus(
  key: ValueKey(label),
  debugLabel: label,
  child: Text(label),
);

final class _Rows extends StatefulWidget {
  const _Rows(this.labels, {super.key});

  final List<String> labels;

  @override
  State<_Rows> createState() => _RowsState();
}

final class _RowsState extends State<_Rows> {
  var labels = <String>[];

  @override
  void initState() {
    super.initState();
    labels = widget.labels;
  }

  void show(List<String> to) => setState(() => labels = to);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [for (final l in labels) _field(l)],
  );
}

void main() {
  testTwk('the focus moves off a node removed in the same frame as its '
      'previous sibling', (t) async {
    final rows = GlobalKey<_RowsState>();
    await t.pumpWidget(
      _Rows(const ['a', 'b', 'c', 'd'], key: rows),
      size: (10, 4),
    );
    for (var i = 0; i < 3; i++) {
      await t.press('tab');
      await t.pump();
    }
    expect(t.binding.focusManager.primaryFocus?.debugLabel, 'c');
    rows.currentState!.show(const ['a', 'd']);
    await t.pump();
    expect(t.binding.focusManager.primaryFocus?.debugLabel, 'd');
  });
}
