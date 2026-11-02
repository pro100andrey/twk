// An App binding on a printable key (`q` quit) is not in force while the
// focus is in a TextField, which takes the key as text: the KeyHintsBar must
// not offer it, and a click on a hint must not type into the field. Review
// finding 2 of the architecture review; waits for arch-key-routing.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget app(
  List<String> seen,
  TextEditingController text, {
  bool field = true,
}) => KeyBindings(
  {'q': () => seen.add('quit'), 'ctrl+s': () => seen.add('save')},
  hints: const {'q': 'quit', 'ctrl+s': 'save'},
  child: Column(
    children: [
      if (field)
        SizedBox(width: 20, child: TextField(controller: text, autofocus: true))
      else
        Button('ok', autofocus: true, onPressed: () {}),
      const KeyHintsBar(pressable: true),
    ],
  ),
);

String bar(TwkTester t) => t.lines.firstWhere((l) => l.contains('save'));

void main() {
  testTwk('guard: outside a text field the bar offers q quit and q quits', (
    t,
  ) async {
    final seen = <String>[];
    await t.pumpWidget(
      app(seen, TextEditingController(), field: false),
      size: (40, 4),
    );
    expect(bar(t), contains('q quit'));
    await t.type('q');
    await t.pump();
    expect(seen, ['quit']);
  });

  testTwk('guard: typing q in a text field types it and quits nothing', (
    t,
  ) async {
    final seen = <String>[];
    final text = TextEditingController();
    await t.pumpWidget(app(seen, text), size: (40, 4));
    await t.type('q');
    await t.pump();
    expect(text.text, 'q');
    expect(seen, isEmpty);
  });

  testTwk('in a text field the bar does not offer q quit, and keeps the keys '
      'that work', (t) async {
    await t.pumpWidget(app([], TextEditingController()), size: (40, 4));
    expect(bar(t), isNot(contains('quit')), reason: 'the bar: ${bar(t)}');
    expect(bar(t), contains('ctrl+s save'));
  }, skip: 'probable bug confirmed: arch-key-routing');

  testTwk('a click on the hint q quit does not type q into the field', (
    t,
  ) async {
    final seen = <String>[];
    final text = TextEditingController();
    await t.pumpWidget(app(seen, text), size: (40, 4));
    final row = t.lines.indexWhere((l) => l.contains('save'));
    final x = t.lines[row].indexOf('quit');
    if (x >= 0) {
      await t.click(x, row);
      await t.pump();
    }
    expect(text.text, '', reason: 'the field after the click');
    expect(seen, isEmpty);
  }, skip: 'probable bug confirmed: arch-key-routing');
}
