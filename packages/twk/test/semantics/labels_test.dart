// The semantics label of a control that shows no name of its own: what a
// screen reader calls a Slider, a Checkbox or a Switch without a label, a
// TextField or a TextArea, read once, in the control's own line before its
// value or state. A label a box or a switch shows is read in its place; in
// a field or an area, it is read in place of the placeholder.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [children] one below another at their left edge.
Column column(List<Widget> children) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: children,
);

/// The lines the app reads as now.
List<String> read(TwkTester t) => t.binding.semantics.lines;

/// [slider] in a box ten cells wide.
Widget sized(Slider slider) => SizedBox(width: 10, child: slider);

void main() {
  testTwk('a slider with a label reads as it once, before its value', (
    t,
  ) async {
    await t.pumpWidget(
      column([
        sized(Slider(value: 0.25, onChanged: (_) {}, semanticsLabel: 'Volume')),
        sized(
          const Slider(
            value: 7.2,
            max: 10,
            divisions: 10,
            onChanged: null,
            semanticsLabel: 'Speed',
          ),
        ),
      ]),
    );
    expect(read(t), ['slider Volume: 0.25', 'slider Speed: 7, disabled']);
  });

  testTwk('a slider without a label, or with an empty one, reads as its '
      'value alone', (t) async {
    await t.pumpWidget(
      column([
        sized(Slider(value: 0.25, onChanged: (_) {})),
        sized(Slider(value: 1, onChanged: (_) {}, semanticsLabel: '')),
      ]),
    );
    expect(read(t), ['slider 0.25', 'slider 1']);
  });

  testTwk('a box and a switch that show no label read as their semantics '
      'labels once, before their states', (t) async {
    await t.pumpWidget(
      column([
        Checkbox(value: true, onChanged: (_) {}, semanticsLabel: 'Bold'),
        const Checkbox(value: false, onChanged: null, semanticsLabel: 'Spam'),
        Switch(value: false, onChanged: (_) {}, semanticsLabel: 'Wi-Fi'),
      ]),
    );
    expect(read(t), [
      'checkbox Bold, checked',
      'checkbox Spam, not checked, disabled',
      'switch Wi-Fi, off',
    ]);
  });

  testTwk('a box and a switch read as the label they show, not as their '
      'semantics labels', (t) async {
    await t.pumpWidget(
      column([
        Checkbox(
          value: false,
          onChanged: (_) {},
          label: 'Remember me',
          semanticsLabel: 'Stay signed in',
        ),
        Switch(
          value: true,
          onChanged: (_) {},
          label: 'Dark mode',
          semanticsLabel: 'Night colors',
        ),
      ]),
    );
    expect(read(t), [
      'checkbox Remember me, not checked',
      'switch Dark mode, on',
    ]);
  });

  testTwk('a box and a switch with neither label, or empty ones, read as '
      'their states alone, never as their marks', (t) async {
    await t.pumpWidget(
      column([
        Checkbox(value: true, onChanged: (_) {}),
        Checkbox(value: false, onChanged: (_) {}, semanticsLabel: ''),
        Switch(value: true, onChanged: (_) {}),
        Switch(value: false, onChanged: (_) {}, semanticsLabel: ''),
      ]),
    );
    expect(read(t), [
      'checkbox, checked',
      'checkbox, not checked',
      'switch, on',
      'switch, off',
    ]);
  });

  testTwk('a field and an area with a label read as it once, before their '
      'texts, in place of their placeholders', (t) async {
    final notes = TextEditingController(text: 'first\nsecond');
    addTearDown(notes.dispose);
    await t.pumpWidget(
      column([
        const TextField(semanticsLabel: 'Name', autofocus: true),
        const TextField(semanticsLabel: 'City', placeholder: 'e.g. Kyiv'),
        TextArea(
          controller: notes,
          semanticsLabel: 'Notes',
          placeholder: 'Anything',
        ),
      ]),
      size: (20, 6),
    );
    expect(read(t), [
      'textbox Name',
      'textbox City',
      'textbox Notes: first',
      'second',
    ]);
    await t.type('anna');
    await t.pump();
    expect(read(t).first, 'textbox Name: anna');
  });

  testTwk('a field and an area without a label, or with an empty one, read '
      'as their placeholders, or as their texts alone', (t) async {
    await t.pumpWidget(
      column(const [
        TextField(placeholder: 'Name'),
        TextField(semanticsLabel: '', placeholder: 'City'),
        TextField(),
        TextArea(semanticsLabel: '', placeholder: 'Notes'),
        TextArea(),
      ]),
      size: (20, 6),
    );
    expect(read(t), [
      'textbox Name',
      'textbox City',
      'textbox',
      'textbox Notes',
      'textbox',
    ]);
  });

  testTwk('an obscured field with a label reads as it and protected, typed '
      'in or not, never its characters, nor on the screen in the '
      'screen-reader mode', (t) async {
    final password = TextEditingController(text: 'hunter2');
    addTearDown(password.dispose);
    await t.pumpWidget(
      column([
        TextField(
          controller: password,
          semanticsLabel: 'Password',
          obscureText: true,
          autofocus: true,
        ),
      ]),
      mode: ScreenMode.inline,
      size: (40, 3),
    );
    expect(read(t), ['textbox Password: protected']);
    await t.type('42');
    await t.pump();
    expect(password.text, 'hunter242');
    expect(read(t), ['textbox Password: protected']);
    t.binding.screenReader = true;
    await t.pump();
    expect(t.lines.first, 'textbox Password: protected');
    expect(t.lines.join('\n'), isNot(contains('hunter')));
  });
}
