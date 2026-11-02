// A Button that cannot take the focus, a flat word of the mouse: a click
// presses it with the focus where it was, Tab passes it by, Enter does
// nothing to it; the default still takes the focus.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

Widget app(
  List<String> log,
  FocusNode other, {
  required bool canRequestFocus,
}) => Row(
  children: [
    Button(
      'reset',
      canRequestFocus: canRequestFocus,
      style: const Style(attrs: Attr.underline),
      onPressed: () => log.add('reset'),
    ),
    const SizedBox(width: 1),
    Button('other', focusNode: other, onPressed: () {}),
  ],
);

void main() {
  testTwk('canRequestFocus: false, a click presses it and the focus stays '
      'where it was; Tab passes it by', (t) async {
    final log = <String>[];
    final other = FocusNode(debugLabel: 'field');
    addTearDown(other.dispose);
    await t.pumpWidget(app(log, other, canRequestFocus: false), size: (30, 2));
    await t.press('tab');
    await t.pump();
    expect(focused(t), 'field', reason: 'Tab skipped the button');
    await t.click(2, 0);
    await t.pump();
    expect(log, ['reset']);
    expect(focused(t), 'field');
  });

  testTwk('by default a click focuses it as well as presses it', (t) async {
    final log = <String>[];
    final other = FocusNode(debugLabel: 'field');
    addTearDown(other.dispose);
    await t.pumpWidget(app(log, other, canRequestFocus: true), size: (30, 2));
    await t.press('tab');
    await t.pump();
    expect(focused(t), isNot('field'));
    await t.click(2, 0);
    await t.pump();
    expect(log, ['reset']);
  });
}
