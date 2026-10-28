// A field drawn in an InputDecoration: each border's rows (an outline with
// its label on the top edge, a line under the row with the label above
// it, none), the icon on the row of the text, the prefix and the suffix
// around the field, the fill, the helper, the error in its place and the
// counter; the colors of the focus, the error and a disabled field; a
// TextField's own counter of its maxLength and its label read by a screen
// reader; a press on the field placing the caret through the decoration;
// a TextFormField's error in its decoration.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ThemeData _dark = ThemeData.dark;

/// [children] in the dark theme, a column [width] wide at the top left.
Widget _column(List<Widget> children, {int width = 24}) => Theme(
  data: _dark,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  ),
);

void main() {
  testTwk('an outline: the label on the top edge, the icon on the row of '
      'the text a cell before the box, the helper under it', (t) async {
    await t.pumpWidget(
      _column([
        const TextField(
          placeholder: 'you@x.org',
          decoration: InputDecoration(
            icon: Text('@'),
            labelText: 'Email',
            helperText: 'never shared',
            border: OutlineInputBorder(),
          ),
        ),
      ]),
      size: (24, 4),
    );
    expect(t.lines, [
      '  ╭ Email ─────────────╮',
      '@ │ you@x.org          │',
      '  ╰────────────────────╯',
      '  never shared',
    ]);
  });

  testTwk('a line under the row, the label above it; the prefix and the '
      'suffix around the field, its room what they leave', (t) async {
    final c = TextEditingController(text: 'twk');
    addTearDown(c.dispose);
    await t.pumpWidget(
      _column([
        TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: 'Site',
            prefixText: 'https://',
            suffixText: '.dev',
          ),
        ),
      ], width: 20),
      size: (20, 3),
    );
    expect(t.lines, [
      'Site',
      'https://twk     .dev',
      '────────────────────',
    ]);
  });

  testTwk('no border: the icons inside, a cell apart, the row filled a '
      'cell before and after them', (t) async {
    await t.pumpWidget(
      _column([
        const TextField(
          placeholder: 'search',
          decoration: InputDecoration(
            prefixIcon: Text('>'),
            suffixIcon: Text('x'),
            border: InputBorder.none,
            filled: true,
          ),
        ),
      ], width: 16),
      size: (16, 1),
    );
    expect(t.lines, [' > search     x']);
    for (final x in [0, 1, 3, 14, 15]) {
      expect(t, styleAt(x, 0, hasBg(_dark.well.bg!)));
    }
  });

  testTwk('the error in place of the helper, in the error color, and the '
      'border and label too; the counter at the right', (t) async {
    await t.pumpWidget(
      _column([
        const TextField(
          decoration: InputDecoration(
            labelText: 'Name',
            helperText: 'as on the card',
            errorText: 'too short',
            counterText: '2/9',
            border: OutlineInputBorder(type: BorderType.single),
          ),
        ),
      ], width: 16),
      size: (16, 4),
    );
    expect(t.lines, [
      '┌ Name ────────┐',
      '│              │',
      '└──────────────┘',
      'too short    2/9',
    ]);
    final error = _dark.error.fg!;
    expect(t, styleAt(0, 0, hasFg(error)));
    expect(t, styleAt(2, 0, hasFg(error)));
    expect(t, styleAt(0, 3, hasFg(error)));
    expect(t, styleAt(13, 3, hasFg(_dark.muted.fg!)));
  });

  testTwk('the border, the label and the icons in the primary color while '
      'the focus is in the field, else the border and muted', (t) async {
    await t.pumpWidget(
      _column([
        const TextField(
          decoration: InputDecoration(
            labelText: 'A',
            prefixIcon: Text('>'),
            border: OutlineInputBorder(),
          ),
        ),
        const TextField(
          decoration: InputDecoration(
            labelText: 'B',
            border: OutlineInputBorder(),
          ),
        ),
      ], width: 12),
      size: (12, 6),
    );
    expect(t, styleAt(0, 0, hasFg(_dark.border.fg!)));
    expect(t, styleAt(2, 0, hasFg(_dark.muted.fg!)));
    expect(t, styleAt(2, 1, hasFg(_dark.muted.fg!)));
    await t.press('tab');
    await t.pump();
    final primary = _dark.primary.fg!;
    expect(t, styleAt(0, 0, hasFg(primary)));
    expect(t, styleAt(0, 1, hasFg(primary)));
    expect(t, styleAt(2, 0, hasFg(primary)));
    expect(t, styleAt(2, 1, hasFg(primary)));
    expect(t, styleAt(0, 3, hasFg(_dark.border.fg!)));
    await t.press('tab');
    await t.pump();
    expect(t, styleAt(0, 0, hasFg(_dark.border.fg!)));
    expect(t, styleAt(0, 3, hasFg(primary)));
  });

  testTwk('disabled: the label muted and the border in its color, its '
      'error still shown in the error color', (t) async {
    await t.pumpWidget(
      _column([
        const TextField(
          enabled: false,
          decoration: InputDecoration(
            labelText: 'Off',
            helperText: 'help',
            errorText: 'wrong',
          ),
        ),
      ], width: 10),
      size: (10, 4),
    );
    expect(t.lines, ['Off', '', '──────────', 'wrong']);
    expect(t, styleAt(0, 0, hasFg(_dark.muted.fg!)));
    expect(t, styleAt(0, 2, hasFg(_dark.border.fg!)));
    expect(t, styleAt(0, 3, hasFg(_dark.error.fg!)));
  });

  testTwk("a TextField's counter counts its characters of its maxLength, "
      'unless the decoration has one', (t) async {
    await t.pumpWidget(
      _column([
        const TextField(
          autofocus: true,
          maxLength: 5,
          decoration: InputDecoration(border: InputBorder.none),
        ),
        const TextField(
          maxLength: 5,
          decoration: InputDecoration(
            border: InputBorder.none,
            counterText: 'own',
          ),
        ),
      ], width: 10),
      size: (10, 4),
    );
    expect(t.lines, ['', '       0/5', '', '       own']);
    await t.type('abcdefg');
    await t.pump();
    expect(t.lines, ['abcde', '       5/5', '', '       own']);
  });

  testTwk('a screen reader reads the field by its label, its '
      'semanticsLabel before it', (t) async {
    await t.pumpWidget(
      _column([
        const TextField(
          placeholder: 'e.g. anna',
          decoration: InputDecoration(labelText: 'Name'),
        ),
        const TextField(
          semanticsLabel: 'City',
          decoration: InputDecoration(labelText: 'Town'),
        ),
      ]),
      size: (24, 6),
    );
    expect(t.binding.semantics.lines, contains('textbox Name'));
    expect(t.binding.semantics.lines, contains('textbox City'));
    expect(t.binding.semantics.lines, isNot(contains('textbox Town')));
  });

  testTwk('a press on the text in the box focuses the field and places the '
      'caret there', (t) async {
    final c = TextEditingController(text: 'hello');
    addTearDown(c.dispose);
    await t.pumpWidget(
      _column([
        TextField(
          controller: c,
          decoration: const InputDecoration(
            icon: Text('@'),
            prefixText: '#',
            border: OutlineInputBorder(),
          ),
        ),
      ]),
      size: (24, 3),
    );
    // the icon and a cell, the edge, a cell, the prefix: the text at 5
    expect(t.lines[1], '@ │ #hello             │');
    await t.click(7, 1);
    await t.pump();
    expect(c.selection, const TextSelection.collapsed(offset: 2));
    expect(t, styleAt(2, 0, hasFg(_dark.primary.fg!)));
  });

  testTwk("a TextFormField's error in its decoration, in place of its line "
      'under the field', (t) async {
    final form = GlobalKey<FormState>();
    await t.pumpWidget(
      Theme(
        data: _dark,
        child: Form(
          key: form,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 20,
              child: TextFormField(
                validator: (v) => v!.isEmpty ? 'required' : null,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  helperText: 'your name',
                ),
              ),
            ),
          ),
        ),
      ),
      size: (20, 5),
    );
    expect(t.lines, ['Name', '', '─' * 20, 'your name', '']);
    // no well under the field of a decoration
    expect(t, styleAt(0, 1, isNot(hasBg(_dark.well.bg!))));
    form.currentState!.validate();
    await t.pump();
    expect(t.lines, ['Name', '', '─' * 20, 'required', '']);
    expect(t, styleAt(0, 3, hasFg(_dark.error.fg!)));
    expect(t, styleAt(0, 2, hasFg(_dark.error.fg!)));
  });
}
