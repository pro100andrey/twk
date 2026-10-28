// Two keyed windows of a WindowLayer closed by their buttons and opened
// again. window_test.dart runs it in the tests, with asserts, and runs
// this file in a VM of its own, without them, as an app runs.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

final class _Layer extends StatefulWidget {
  const _Layer();

  @override
  State<_Layer> createState() => _LayerState();
}

final class _LayerState extends State<_Layer> {
  final _notes = WindowController(left: 2, top: 3, width: 30, height: 6);
  final _counter = WindowController(left: 24, top: 5, width: 26, height: 6);
  final _closed = <String>{};

  @override
  void dispose() {
    _notes.dispose();
    _counter.dispose();
    super.dispose();
  }

  Window _window(String title, WindowController controller) => Window(
    key: ValueKey(title),
    title: title,
    controller: controller,
    onClose: () => setState(() => _closed.add(title)),
    shadow: const BoxShadow(),
    child: Text(title.toLowerCase()),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 50,
    height: 12,
    child: WindowLayer(
      windows: [
        if (!_closed.contains('Notes')) _window('Notes', _notes),
        if (!_closed.contains('Counter')) _window('Counter', _counter),
      ],
      child: Column(
        crossAxisAlignment: .start,
        children: [
          const Text('app'),
          Button(
            'Open',
            onPressed: _closed.isEmpty ? null : () => setState(_closed.clear),
          ),
        ],
      ),
    ),
  );
}

/// Shows the two windows, closes each by its button and opens both again,
/// expecting each frame to show them and no error.
Future<void> closeAndReopen(TwkTester t) async {
  void shows({required bool notes, required bool counter}) {
    expect(find.byType(ErrorWidget).evaluate(), isEmpty);
    expect(
      t,
      notes
          ? hasTextAt(2, 3, '┌ Notes')
          : isNot(containsLine(contains('Notes'))),
    );
    expect(
      t,
      counter
          ? hasTextAt(24, 5, '┌ Counter')
          : isNot(containsLine(contains('Counter'))),
    );
  }

  await t.pumpWidget(const Theme.terminal(child: _Layer()), size: (56, 14));
  shows(notes: true, counter: true);
  // the close buttons, 3 columns in from the right of the title bars
  await t.click(29, 3);
  await t.pump();
  shows(notes: false, counter: true);
  await t.click(47, 5);
  await t.pump();
  shows(notes: false, counter: false);
  await t.click(1, 1);
  await t.pump();
  // Open, disabled as it opens them, passes the focus on to the next stop,
  // the title bar of Notes, which comes to the front
  expect(find.byType(ErrorWidget).evaluate(), isEmpty);
  expect(t, hasTextAt(2, 3, '┌ Notes'));
  expect(t, hasTextAt(43, 5, '_ □ × ┐'));
}

void main() {
  testTwk('keyed windows are closed and opened again', closeAndReopen);
}
