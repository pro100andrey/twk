// What a TextField and a TextArea do besides editing, through the parser:
// read-only (the caret moving and selecting, nothing editing, the keys that
// would going up), disabled (muted, passed by by Tab, deaf to the mouse and
// the keys, read as disabled), onPaste taking a paste in place of the
// field, textAlign placing a short text and its caret, and
// onEditingComplete on Enter and on the focus leaving after a change.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// The label of the node that has the focus.
String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// The keys a `KeyHintsBar` shows now, with their hints.
List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// [children] one under the other at the top left, the keys none of them
/// takes going to [up].
Widget column(List<Widget> children, {List<String>? up}) => Focus(
  canRequestFocus: false,
  skipTraversal: true,
  onKeyEvent: (node, event) {
    if (event.kind != KeyKind.release) {
      up?.add(event.char.isEmpty ? event.code.name : event.char);
    }
    return KeyEventResult.ignored;
  },
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  ),
);

/// Presses each of [keys], apart by spaces, a frame after each, as an app
/// draws one after each key it reads.
Future<void> keys(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

/// A field that takes the focus by Tab after the others, labelled `next`.
Widget next(FocusNode node) => TextField(focusNode: node);

void main() {
  late FocusNode a;
  late FocusNode b;
  setUp(() {
    a = FocusNode(debugLabel: 'a');
    b = FocusNode(debugLabel: 'next');
  });
  tearDown(() {
    a.dispose();
    b.dispose();
  });

  group('readOnly', () {
    testTwk('a field moves the caret and selects, edits nothing, and leaves '
        'the keys that would edit to the nodes above', (t) async {
      final c = TextEditingController(text: 'hello world');
      addTearDown(c.dispose);
      final changes = <String>[];
      final up = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: column(up: up, [
            TextField(
              controller: c,
              focusNode: a,
              autofocus: true,
              readOnly: true,
              onChanged: changes.add,
            ),
          ]),
        ),
        size: (20, 2),
      );
      await t.press('ctrl+left shift+ctrl+left');
      expect(c.selection, const TextSelection(baseOffset: 6, extentOffset: 0));
      await t.type('x');
      await t.press('backspace delete ctrl+k ctrl+u ctrl+w alt+d ctrl+d');
      await t.paste('pasted');
      await t.pump();
      expect(c.text, 'hello world');
      expect(changes, isEmpty);
      expect(up, ['x', 'backspace', 'delete', 'k', 'u', 'w', 'd', 'd']);
      expect(t.cursorVisible, isTrue);
      expect(t, cursorAt(0, 0));
      expect(t, styleAt(2, 0, hasBg(const Color.indexed(237))));
      // a change the app makes is no edit: undo does not take it back
      c.text = 'set';
      await t.press('ctrl+z');
      expect(c.text, 'set');
      expect(hints(t), isEmpty);
    });

    testTwk('an area moves the caret by rows, and Enter breaks no line', (
      t,
    ) async {
      final c = TextEditingController(text: 'one\ntwo');
      addTearDown(c.dispose);
      final up = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: column(up: up, [
            TextArea(
              controller: c,
              focusNode: a,
              autofocus: true,
              readOnly: true,
            ),
          ]),
        ),
        size: (20, 3),
      );
      await t.press('up');
      expect(c.selection, const TextSelection.collapsed(offset: 3));
      await t.press('enter');
      await t.type('z');
      await t.press('backspace');
      await t.paste('a\nb');
      await t.pump();
      expect(c.text, 'one\ntwo');
      expect(up, ['enter', 'z', 'backspace']);
      expect(t, cursorAt(3, 0));
      expect(hints(t), isEmpty);
    });
  });

  group('enabled: false', () {
    testTwk('a field is muted, passed by by Tab, deaf to the mouse, and read '
        'as disabled', (t) async {
      final c = TextEditingController(text: 'off');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(
            data: ThemeData.dark,
            child: column([
              TextField(
                controller: c,
                focusNode: a,
                enabled: false,
                semanticsLabel: 'Name',
              ),
              next(b),
            ]),
          ),
        ),
        size: (20, 2),
      );
      expect(t.cell(0, 0).fg, ThemeData.dark.muted.fg);
      await t.press('tab');
      await t.pump();
      expect(focused(t), 'next');
      await t.click(1, 0);
      await t.pump();
      expect(focused(t), 'next');
      expect(t.binding.semantics.lines.first, 'textbox Name: off, disabled');
    });

    testTwk('a field disabled while it has the focus loses it and takes no '
        'more keys; enabled again, it takes the focus again', (t) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: ListenableBuilder(
            listenable: enabled,
            builder: (context, _) => column([
              TextField(
                controller: c,
                focusNode: a,
                autofocus: true,
                enabled: enabled.value,
              ),
              next(b),
            ]),
          ),
        ),
        size: (20, 2),
      );
      await t.type('a');
      enabled.value = false;
      await t.pump();
      await t.type('b');
      await t.pump();
      expect(c.text, 'a');
      expect(focused(t), isNot('a'));
      enabled.value = true;
      await t.pump();
      a.requestFocus();
      await t.pump();
      expect(focused(t), 'a');
    });

    testTwk('an area is muted and passed by by Tab', (t) async {
      final c = TextEditingController(text: 'off');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(
            data: ThemeData.dark,
            child: column([
              TextArea(controller: c, focusNode: a, enabled: false),
              next(b),
            ]),
          ),
        ),
        size: (20, 2),
      );
      expect(t.cell(0, 0).fg, ThemeData.dark.muted.fg);
      await t.press('tab');
      await t.pump();
      expect(focused(t), 'next');
      await t.click(1, 0);
      await t.pump();
      expect(focused(t), 'next');
      expect(t.binding.semantics.lines.first, 'textbox off, disabled');
    });
  });

  group('onPaste', () {
    testTwk('a field puts in nothing of a paste onPaste takes, and what it '
        'leaves as ever', (t) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      final pasted = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: column([
            TextField(
              controller: c,
              autofocus: true,
              onPaste: (text) {
                pasted.add(text);
                return text.startsWith('/');
              },
            ),
          ]),
        ),
        size: (20, 2),
      );
      await t.paste('/tmp/a\n');
      await t.paste('b\nc');
      await t.pump();
      expect(pasted, ['/tmp/a\n', 'b\nc']);
      expect(c.text, 'b c');
    });

    testTwk('an area too', (t) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      final pasted = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: column([
            TextArea(
              controller: c,
              autofocus: true,
              onPaste: (text) {
                pasted.add(text);
                return text == 'taken';
              },
            ),
          ]),
        ),
        size: (20, 3),
      );
      await t.paste('taken');
      await t.paste('a\nb');
      expect(pasted, ['taken', 'a\nb']);
      expect(c.text, 'a\nb');
    });
  });

  group('textAlign', () {
    testTwk('center and right place a text shorter than the field, and its '
        'caret, a column after it kept for the caret', (t) async {
      final centered = TextEditingController(text: 'abc');
      final right = TextEditingController(text: 'abc');
      addTearDown(centered.dispose);
      addTearDown(right.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: column([
            TextField(
              controller: centered,
              focusNode: a,
              autofocus: true,
              textAlign: TextAlign.center,
            ),
            TextField(
              controller: right,
              focusNode: b,
              textAlign: TextAlign.right,
            ),
            const TextField(placeholder: 'Name', textAlign: TextAlign.right),
          ]),
        ),
        size: (20, 3),
      );
      expect(t.lines[0], '        abc');
      expect(t.lines[1], '                abc');
      expect(t.lines[2], '               Name');
      expect(t, cursorAt(11, 0));
      await t.press('home');
      await t.pump();
      expect(t, cursorAt(8, 0));
      await t.press('tab');
      await t.pump();
      expect(t, cursorAt(19, 1));
      // a press places the caret at the character drawn in the cell
      await t.click(17, 1);
      await t.pump();
      expect(right.selection, const TextSelection.collapsed(offset: 1));
      expect(t, cursorAt(17, 1));
    });

    testTwk('empty, the caret is where the text will end, the placeholder '
        'before it', (t) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: column([
            TextField(
              controller: c,
              autofocus: true,
              placeholder: 'Name',
              textAlign: TextAlign.right,
            ),
          ]),
        ),
        size: (20, 1),
      );
      expect(t.lines[0], '               Name');
      expect(t, cursorAt(19, 0));
      await t.type('k');
      await t.pump();
      expect(t.lines[0], '                  k');
      expect(t, cursorAt(19, 0));
    });

    testTwk('a text as wide as the field or wider scrolls as at the left', (
      t,
    ) async {
      final c = TextEditingController(text: 'x' * 25);
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: column([
            TextField(
              controller: c,
              autofocus: true,
              textAlign: TextAlign.right,
            ),
          ]),
        ),
        size: (20, 1),
      );
      expect(t.lines[0], 'x' * 19);
      expect(t, cursorAt(19, 0));
      await t.press('home');
      await t.pump();
      expect(t.lines[0], 'x' * 20);
      expect(t, cursorAt(0, 0));
    });
  });

  group('onEditingComplete', () {
    testTwk('a field calls it on Enter, before onSubmitted, and as the focus '
        'leaves it after a change only', (t) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      final calls = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: column([
            TextField(
              controller: c,
              focusNode: a,
              autofocus: true,
              onEditingComplete: () => calls.add('complete ${c.text}'),
              onSubmitted: (text) => calls.add('submitted $text'),
            ),
            next(b),
          ]),
        ),
        size: (20, 2),
      );
      await t.type('ab');
      await t.press('enter');
      expect(calls, ['complete ab', 'submitted ab']);
      calls.clear();
      // nothing changed since Enter, or a move only
      await keys(t, 'tab shift+tab left tab');
      expect(calls, isEmpty);
      await keys(t, 'shift+tab');
      await t.type('c');
      await keys(t, 'tab');
      expect(calls, ['complete acb']);
      expect(focused(t), 'next');
    });

    testTwk('a field with it alone takes Enter, a submit', (t) async {
      final up = <String>[];
      var completed = 0;
      await t.pumpWidget(
        Theme.terminal(
          child: column(up: up, [
            TextField(autofocus: true, onEditingComplete: () => completed++),
          ]),
        ),
        size: (20, 2),
      );
      await t.press('enter');
      expect(completed, 1);
      expect(up, isEmpty);
      expect(hints(t), ['enter submit']);
    });

    testTwk('an area calls it on Enter that submits, not on one that breaks '
        'the line, and as the focus leaves it after a change', (t) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      final calls = <String>[];
      final submits = ValueNotifier(false);
      addTearDown(submits.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: ListenableBuilder(
            listenable: submits,
            builder: (context, _) => column([
              TextArea(
                controller: c,
                focusNode: a,
                autofocus: true,
                onEditingComplete: () => calls.add('complete'),
                onSubmitted: submits.value
                    ? (_) => calls.add('submitted')
                    : null,
              ),
              next(b),
            ]),
          ),
        ),
        size: (20, 4),
      );
      await t.type('a');
      await t.press('enter');
      expect(c.text, 'a\n');
      expect(calls, isEmpty);
      await t.press('tab');
      await t.pump();
      expect(calls, ['complete']);
      calls.clear();
      submits.value = true;
      await t.press('shift+tab');
      await t.pump();
      await t.press('enter');
      expect(calls, ['complete', 'submitted']);
    });
  });
}
