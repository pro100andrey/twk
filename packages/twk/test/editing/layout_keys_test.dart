// The built-in keys (Ctrl+C quits, the editing keys of a text field) on a
// Russian layout in a kitty-protocol terminal, where Ctrl and the key that
// types `с` arrives as `CSI 1089 :: 99 ; 5 u` (the typed character, no
// shifted one, the key on a US layout): the key by its place, as shortcuts
// are; and on a Latin layout, where the typed character is what counts.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show clipboardSequence;
import 'package:twk_test/twk_test.dart';

/// Ctrl (or [mods]) and the key typing the Russian [ru] where [us] is.
String ru(String ru, String us, [int mods = 5]) =>
    '\x1b[${ru.runes.first}::${us.codeUnitAt(0)};${mods}u';

Future<TextEditingController> field(
  TwkTester t,
  String text, {
  int? caret,
  bool readOnly = false,
}) async {
  final c = TextEditingController(text: text);
  addTearDown(c.dispose);
  c.selection = TextSelection.collapsed(offset: caret ?? text.length);
  await t.pumpWidget(
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 20,
        child: TextField(controller: c, autofocus: true, readOnly: readOnly),
      ),
    ),
    size: (20, 2),
    exitOnCtrlC: false,
    kittyKeyboard: true,
  );
  return c;
}

void main() {
  testTwk('Ctrl+С on a Russian layout quits the app', (t) async {
    await t.pumpWidget(const Text('x'), kittyKeyboard: true);
    await t.type(ru('с', 'c'));
    await t.pump();
    expect(t.isRunning, isFalse);
  });

  testTwk('a plain с or Ctrl+С with exitOnCtrlC false does not quit', (
    t,
  ) async {
    await t.pumpWidget(const Text('x'), kittyKeyboard: true);
    await t.type('\x1b[1089::99u');
    await t.type(ru('ч', 'x'));
    await t.pump();
    expect(t.isRunning, isTrue);
  });

  group('text editing keys by the key on a US layout', () {
    testTwk('Ctrl+С copies, Ctrl+Ч cuts, Ctrl+Я undoes it', (t) async {
      final c = await field(t, 'hello world');
      await t.press('shift+ctrl+left');
      await t.type(ru('с', 'c'));
      await t.pump();
      expect(t.written(), contains(clipboardSequence('world')));
      expect(c.text, 'hello world');
      await t.type(ru('ч', 'x'));
      expect(c.text, 'hello ');
      await t.type(ru('я', 'z'));
      expect(c.text, 'hello world');
      await t.type(ru('н', 'y'));
      expect(c.text, 'hello ');
    });

    testTwk('Ctrl+Shift+Я redoes', (t) async {
      final c = await field(t, 'hello world');
      await t.press('shift+ctrl+left ctrl+x ctrl+z');
      expect(c.text, 'hello world');
      await t.type(ru('я', 'z', 6));
      expect(c.text, 'hello ');
    });

    testTwk('read-only: Ctrl+С copies, Ctrl+Ч does not cut', (t) async {
      final c = await field(t, 'hello world', readOnly: true);
      await t.press('shift+ctrl+left');
      await t.type(ru('ч', 'x'));
      expect(c.text, 'hello world');
      await t.type(ru('с', 'c'));
      await t.pump();
      expect(t.written(), contains(clipboardSequence('world')));
    });

    testTwk('Ctrl+Ф and Ctrl+У move to the line ends', (t) async {
      final c = await field(t, 'hello world', caret: 5);
      await t.type(ru('ф', 'a'));
      expect(c.selection.extentOffset, 0);
      await t.type(ru('у', 'e'));
      expect(c.selection.extentOffset, 11);
    });

    testTwk('Ctrl+В, Ц, Г, Л delete', (t) async {
      final c = await field(t, 'ab cd ef', caret: 0);
      await t.type(ru('в', 'd'));
      expect(c.text, 'b cd ef');
      await t.type(ru('л', 'k'));
      expect(c.text, '');
      c.value = const TextEditingValue(
        text: 'one two',
        selection: TextSelection.collapsed(offset: 7),
      );
      await t.type(ru('ц', 'w'));
      expect(c.text, 'one ');
      await t.type(ru('г', 'u'));
      expect(c.text, '');
    });

    testTwk('Alt+И, А, В move and delete by words', (t) async {
      final c = await field(t, 'one two', caret: 7);
      await t.type(ru('и', 'b', 3));
      expect(c.selection.extentOffset, 4);
      await t.type(ru('в', 'd', 3));
      expect(c.text, 'one ');
      await t.type(ru('ф', 'a'));
      await t.type(ru('а', 'f', 3));
      expect(c.selection.extentOffset, 3);
    });

    testTwk('a plain с types, Ctrl+С with Latin typed text is its own', (
      t,
    ) async {
      final c = await field(t, '');
      await t.type('\x1b[1089::99u');
      expect(c.text, 'с');
    });
  });

  testTwk('Dvorak: Ctrl+C typed is c though its key is j; ctrl+j is not it', (
    t,
  ) async {
    final seen = <String>[];
    await t.pumpWidget(
      Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          seen.add('up ${event.char}');
          return KeyEventResult.ignored;
        },
        child: KeyBindings({
          'ctrl+j': () => seen.add('ctrl+j'),
        }, child: const Focus(autofocus: true, child: Text('a'))),
      ),
      exitOnCtrlC: false,
      kittyKeyboard: true,
    );
    await t.type('\x1b[99::106;5u');
    expect(seen, ['up c']);
    await t.type('\x1b[106::99;5u');
    expect(seen, ['up c', 'ctrl+j']);
  });
}
