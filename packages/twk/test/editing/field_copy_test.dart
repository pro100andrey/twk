// A TextField's and a TextArea's selection copied and cut to the system
// clipboard (OSC 52, wrapped inside a multiplexer) by Ctrl+C and Ctrl+X,
// which go up (Ctrl+C to quit) with nothing selected; read-only and
// obscured fields refusing what they must; the keys hinted while a
// selection exists; and the style a disabled field shows in.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show Multiplexer, clipboardSequence;
import 'package:twk_test/twk_test.dart';

/// How many OSC 52 sequences the app wrote.
int copies(TwkTester t) => ']52;'.allMatches(t.written()).length;

/// The keys a `KeyHintsBar` shows now, with their hints.
List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// [child] at the top left, 20 columns wide, the keys it does not take
/// going to [up].
Widget above(Widget child, List<String> up) => Focus(
  canRequestFocus: false,
  skipTraversal: true,
  onKeyEvent: (node, event) {
    if (event.kind != KeyKind.release) {
      up.add(event.char.isEmpty ? event.code.name : event.char);
    }
    return KeyEventResult.ignored;
  },
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: 20, child: child),
  ),
);

void main() {
  group('TextField', () {
    testTwk('Ctrl+C copies the selection, Ctrl+X cuts it; with nothing '
        'selected they go up', (t) async {
      final c = TextEditingController(text: 'hello world');
      addTearDown(c.dispose);
      final up = <String>[];
      final changes = <String>[];
      await t.pumpWidget(
        above(
          TextField(controller: c, autofocus: true, onChanged: changes.add),
          up,
        ),
        size: (20, 2),
        exitOnCtrlC: false,
      );
      await t.press('ctrl+c ctrl+x');
      expect(up, ['c', 'x']);
      expect(copies(t), 0);
      await t.press('shift+ctrl+left');
      await t.pump();
      expect(hints(t), ['ctrl+c copy', 'ctrl+x cut']);
      await t.press('ctrl+c');
      await t.pump();
      expect(t.written(), contains(clipboardSequence('world')));
      expect(c.text, 'hello world');
      expect(c.selection, const TextSelection(baseOffset: 11, extentOffset: 6));
      await t.press('ctrl+x');
      await t.pump();
      expect(copies(t), 2);
      expect(c.text, 'hello ');
      expect(changes, ['hello ']);
      expect(hints(t), ['ctrl+z undo']);
      await t.press('ctrl+z');
      expect(c.text, 'hello world');
      expect(up, ['c', 'x']);
    });

    testTwk('read-only, Ctrl+C copies and Ctrl+X goes up, cutting '
        'nothing', (t) async {
      final c = TextEditingController(text: 'hello');
      addTearDown(c.dispose);
      final up = <String>[];
      await t.pumpWidget(
        above(TextField(controller: c, autofocus: true, readOnly: true), up),
        size: (20, 2),
        exitOnCtrlC: false,
      );
      await t.press('shift+left shift+left');
      await t.pump();
      expect(hints(t), ['ctrl+c copy']);
      await t.press('ctrl+x');
      await t.pump();
      expect(copies(t), 0);
      expect(c.text, 'hello');
      expect(up, ['x']);
      await t.press('ctrl+c');
      await t.pump();
      expect(t.written(), contains(clipboardSequence('lo')));
      expect(up, ['x']);
    });

    testTwk('obscured, it copies nothing: Ctrl+C and Ctrl+X go up', (t) async {
      final c = TextEditingController(text: 'secret');
      addTearDown(c.dispose);
      final up = <String>[];
      await t.pumpWidget(
        above(TextField(controller: c, autofocus: true, obscureText: true), up),
        size: (20, 2),
        exitOnCtrlC: false,
      );
      await t.press('shift+home');
      await t.pump();
      expect(hints(t), isEmpty);
      await t.press('ctrl+c ctrl+x');
      await t.pump();
      expect(copies(t), 0);
      expect(c.text, 'secret');
      expect(up, ['c', 'x']);
    });

    testTwk('with keyHints false the keys copy unhinted', (t) async {
      final c = TextEditingController(text: 'hello');
      addTearDown(c.dispose);
      await t.pumpWidget(
        above(
          TextField(controller: c, autofocus: true, keyHints: false),
          <String>[],
        ),
        size: (20, 2),
        exitOnCtrlC: false,
      );
      await t.press('shift+home');
      await t.pump();
      expect(hints(t), isEmpty);
      await t.press('ctrl+c');
      expect(t.written(), contains(clipboardSequence('hello')));
    });

    testTwk('inside tmux the copy is wrapped for it', (t) async {
      final c = TextEditingController(text: 'hello');
      addTearDown(c.dispose);
      await t.pumpWidget(
        above(TextField(controller: c, autofocus: true), <String>[]),
        size: (20, 2),
        exitOnCtrlC: false,
        multiplexer: Multiplexer.tmux,
      );
      await t.press('shift+home ctrl+c');
      expect(
        t.written(),
        contains(clipboardSequence('hello', multiplexer: Multiplexer.tmux)),
      );
    });

    testTwk('disabled, it shows in disabledStyle', (t) async {
      const grey = Color.rgb(9, 8, 7);
      final c = TextEditingController(text: 'off');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: above(
            TextField(
              controller: c,
              enabled: false,
              disabledStyle: const Style(fg: grey),
            ),
            <String>[],
          ),
        ),
        size: (20, 2),
        exitOnCtrlC: false,
      );
      expect(t.cell(0, 0).fg, grey);
    });
  });

  group('TextArea', () {
    testTwk('Ctrl+C copies the selection across lines, Ctrl+X cuts it', (
      t,
    ) async {
      final c = TextEditingController(text: 'one\ntwo');
      addTearDown(c.dispose);
      final up = <String>[];
      await t.pumpWidget(
        above(TextArea(controller: c, autofocus: true), up),
        size: (20, 3),
        exitOnCtrlC: false,
      );
      await t.press('ctrl+c');
      expect(up, ['c']);
      await t.press('shift+up');
      await t.pump();
      expect(hints(t), ['enter new line', 'ctrl+c copy', 'ctrl+x cut']);
      await t.press('ctrl+c');
      expect(t.written(), contains(clipboardSequence('\ntwo')));
      await t.press('ctrl+x');
      await t.pump();
      expect(copies(t), 2);
      expect(c.text, 'one');
      expect(up, ['c']);
    });

    testTwk('read-only, Ctrl+X goes up, cutting nothing', (t) async {
      final c = TextEditingController(text: 'one\ntwo');
      addTearDown(c.dispose);
      final up = <String>[];
      await t.pumpWidget(
        above(TextArea(controller: c, autofocus: true, readOnly: true), up),
        size: (20, 3),
        exitOnCtrlC: false,
      );
      await t.press('shift+ctrl+home');
      await t.pump();
      expect(hints(t), ['ctrl+c copy']);
      await t.press('ctrl+x');
      await t.pump();
      expect(copies(t), 0);
      expect(c.text, 'one\ntwo');
      expect(up, ['x']);
      await t.press('ctrl+c');
      expect(t.written(), contains(clipboardSequence('one\ntwo')));
    });

    testTwk('disabled, it shows in disabledStyle', (t) async {
      const grey = Color.rgb(9, 8, 7);
      final c = TextEditingController(text: 'off');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: above(
            TextArea(
              controller: c,
              enabled: false,
              disabledStyle: const Style(fg: grey),
            ),
            <String>[],
          ),
        ),
        size: (20, 2),
        exitOnCtrlC: false,
      );
      expect(t.cell(0, 0).fg, grey);
    });
  });
}
