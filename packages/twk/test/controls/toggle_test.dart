// Checkbox, Switch and RadioGroup as the design draws them, in the dark
// theme: the brackets muted, the mark primary and bold, a focused row on
// the selection colour; the Switch a pill whose knob runs between its
// ends; and a plain look through their parameters.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ThemeData theme = ThemeData.dark;
final Color muted = theme.muted.fg!;
final Color primary = theme.primary.fg!;
final Color selection = theme.selection.bg!;

/// [child] at the top left, as small as it is, in the dark theme.
Widget dark(Widget child) => Theme(
  data: theme,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [child],
  ),
);

Matcher marked() => allOf(hasFg(primary), hasAttr(Attr.bold));

Matcher bracket() => allOf(hasFg(muted), isNot(hasAttr(Attr.bold)));

void main() {
  test("pillSpans: the pill a Switch draws, for a painter of one's own", () {
    const theme = ThemeData.dark;
    final on = Switch.pillSpans(theme, at: 1);
    expect(on.map((s) => s.text).join(), '▐  ●▌');
    expect(on.first.style.fg, theme.primary.fg);
    expect(on.first.style.bg, isNull, reason: 'over what is under it');
    final off = Switch.pillSpans(theme, at: 0, enabled: false);
    expect(off.map((s) => s.text).join(), '▐●  ▌');
    expect(off[1].style.fg, theme.muted.fg);
  });

  testTwk('a checkbox: the brackets muted, the x primary and bold, the '
      'label text; focused, the row on the selection colour', (t) async {
    final node = FocusNode(debugLabel: 'box');
    addTearDown(node.dispose);
    await t.pumpWidget(
      dark(
        Checkbox(
          value: true,
          onChanged: (_) {},
          label: 'Wrap',
          focusNode: node,
        ),
      ),
      size: (10, 1),
    );
    expect(t.lines, ['[x] Wrap']);
    expect(t, styleAt(0, 0, bracket()));
    expect(t, styleAt(1, 0, marked()));
    expect(t, styleAt(2, 0, bracket()));
    expect(t, styleAt(4, 0, hasFg(theme.text.fg!)));
    expect(t, styleAt(4, 0, isNot(hasBg(selection))));
    node.requestFocus();
    await t.pump();
    for (var x = 0; x < 8; x++) {
      expect(t, styleAt(x, 0, hasBg(selection)));
    }
    expect(t, styleAt(0, 0, bracket()));
    expect(t, styleAt(1, 0, marked()));
  });

  testTwk('a plain look: the brackets as the mark, the row '
      'reversed while focused', (t) async {
    final node = FocusNode(debugLabel: 'box');
    addTearDown(node.dispose);
    await t.pumpWidget(
      dark(
        Checkbox(
          value: true,
          onChanged: (_) {},
          label: 'Wrap',
          focusNode: node,
          bracketStyle: const Style(),
          focusedStyle: theme.primary.merge(
            const Style(attrs: Attr.bold | Attr.reverse),
          ),
        ),
      ),
      size: (10, 1),
    );
    expect(t, styleAt(0, 0, marked()));
    expect(t, styleAt(2, 0, marked()));
    node.requestFocus();
    await t.pump();
    expect(t, styleAt(5, 0, allOf(hasFg(primary), hasAttr(Attr.reverse))));
  });

  testTwk('a switch is a pill: off, its knob at the left on a track of the '
      'border colour; on, at the right on a primary one; its knob runs '
      'between them in 140 ms', (t) async {
    final value = ValueNotifier(false);
    addTearDown(value.dispose);
    await t.pumpWidget(
      dark(
        ValueListenableBuilder<bool>(
          valueListenable: value,
          builder: (context, on, _) => Switch(
            value: on,
            onChanged: (v) => value.value = v,
            label: 'Dark',
            autofocus: true,
          ),
        ),
      ),
      size: (12, 1),
    );
    await t.pump();
    expect(t.lines, ['▐●  ▌ Dark']);
    const off = Color.rgb(0x38, 0x3d, 0x48);
    expect(t, styleAt(0, 0, allOf(hasFg(off), hasBg(selection))));
    expect(t, styleAt(1, 0, allOf(hasFg(theme.text.fg!), hasBg(off))));
    expect(t, styleAt(3, 0, hasBg(off)));
    expect(t, styleAt(4, 0, allOf(hasFg(off), hasBg(selection))));
    expect(t, styleAt(6, 0, hasBg(selection)));
    await t.press('space');
    await t.pump();
    await t.pump(const Duration(milliseconds: 30));
    // on the way: the knob in the middle, the track between the two
    expect(t.lines, ['▐ ● ▌ Dark']);
    expect(t, styleAt(2, 0, allOf(isNot(hasBg(off)), isNot(hasBg(primary)))));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.lines, ['▐  ●▌ Dark']);
    expect(t, styleAt(0, 0, hasFg(primary)));
    expect(
      t,
      styleAt(
        3,
        0,
        allOf(hasFg(const Color.rgb(0xff, 0xff, 0xff)), hasBg(primary)),
      ),
    );
  });

  testTwk("on a dark theme of the terminal's colors, the track is the "
      'border color while off, the primary one while on', (t) async {
    Widget pill(bool on) => Theme(
      data: const ThemeData.terminal(Brightness.dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Switch(value: on, onChanged: (_) {})],
      ),
    );
    await t.pumpWidget(pill(false), size: (8, 1));
    expect(t, styleAt(2, 0, hasBg(const Color.indexed(240))));
    await t.pumpWidget(pill(true));
    await t.pump(const Duration(milliseconds: 200));
    expect(t, styleAt(2, 0, hasBg(Color.blue)));
  });

  testTwk('a disabled switch: the track faint, the knob and the label '
      'muted; pill false shows [on ] and [off]', (t) async {
    await t.pumpWidget(
      dark(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Switch(value: true, onChanged: null, label: 'Off'),
            Switch(value: true, onChanged: _ignore, pill: false, label: 'On'),
          ],
        ),
      ),
      size: (12, 2),
    );
    expect(t.lines, ['▐  ●▌ Off', '[on ] On']);
    expect(t, styleAt(0, 0, hasFg(theme.faint.fg!)));
    expect(t, styleAt(3, 0, allOf(hasFg(muted), hasBg(theme.faint.fg!))));
    expect(t, styleAt(6, 0, hasFg(muted)));
    expect(t, styleAt(0, 1, marked()));
    expect(t, styleAt(4, 1, marked()));
  });

  testTwk('a radio group: the parentheses muted, the mark ● primary and '
      'bold; the choice with the focus on the selection colour; mark and '
      'bracketStyle give a plain look', (t) async {
    await t.pumpWidget(
      dark(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<int>(
              choices: const [Choice(1, 'one'), Choice(2, 'two')],
              value: 2,
              onChanged: (_) {},
              autofocus: true,
            ),
            RadioGroup<int>(
              choices: const [Choice(1, 'one')],
              value: 1,
              onChanged: (_) {},
              mark: '*',
              bracketStyle: const Style(),
            ),
          ],
        ),
      ),
      size: (10, 3),
    );
    await t.pump();
    expect(t.lines, ['( ) one', '(●) two', '(*) one']);
    expect(t, styleAt(0, 0, bracket()));
    expect(t, styleAt(0, 1, bracket()));
    expect(t, styleAt(1, 1, marked()));
    for (var x = 0; x < 7; x++) {
      expect(t, styleAt(x, 1, hasBg(selection)));
      expect(t, styleAt(x, 0, isNot(hasBg(selection))));
    }
    expect(t, styleAt(0, 2, marked()));
    expect(t, styleAt(2, 2, marked()));
  });
}

void _ignore(bool _) {}
