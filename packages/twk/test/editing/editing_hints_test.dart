// The hints of the keys a TextField and a TextArea take that do more
// than edit: Enter while it submits or breaks the line, Alt+Enter, Ctrl+Z
// while there is a change to undo; an Autocomplete's keys first while its
// suggestions show, the field's Enter left out meanwhile; none with
// keyHints false; Ctrl+Z with nothing to undo still going on to the nodes
// above.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

Future<void> type(TwkTester t, String text) async {
  await t.type(text);
  await t.pump();
}

Future<void> press(TwkTester t, String keys) async {
  await t.press(keys);
  await t.pump();
}

Iterable<Suggestion> commands(String query) => [
  for (final name in const ['help', 'history', 'quit'])
    if (fuzzyMatch(query, name) != null) Suggestion(name),
];

/// [field] with an [Autocomplete] that completes [c] after `/` around it,
/// [hinted] or not.
Widget completed(
  TextEditingController c,
  Widget field, {
  bool hinted = true,
}) => Overlay(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Autocomplete(
        controller: c,
        trigger: '/',
        suggestions: commands,
        keyHints: hinted,
        child: field,
      ),
      const SizedBox(height: 6),
    ],
  ),
);

void main() {
  group('a TextField', () {
    testTwk('Ctrl+Z once there is a change to undo, and no more once '
        'undone', (t) async {
      await t.pumpWidget(const TextField(autofocus: true), size: (20, 2));
      expect(hints(t), isEmpty);
      await type(t, 'a');
      expect(hints(t), ['ctrl+z undo']);
      await press(t, 'ctrl+z');
      expect(hints(t), isEmpty);
    });

    testTwk('Enter while it submits, before Ctrl+Z', (t) async {
      await t.pumpWidget(
        TextField(autofocus: true, onSubmitted: (_) {}),
        size: (20, 2),
      );
      expect(hints(t), ['enter submit']);
      await type(t, 'a');
      expect(hints(t), ['enter submit', 'ctrl+z undo']);
    });

    testTwk('a KeyHintsBar follows them in the frame after the key', (
      t,
    ) async {
      await t.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(autofocus: true, onSubmitted: (_) {}),
            KeyHintsBar(separator: ' · ', keyLabel: (c) => '$c'),
          ],
        ),
        size: (40, 2),
      );
      expect(t.lines[1], 'enter submit');
      await type(t, 'a');
      expect(t.lines[1], 'enter submit · ctrl+z undo');
    });

    testTwk('keyHints false: none, the keys doing what they do', (t) async {
      final submitted = <String>[];
      final c = TextEditingController();
      await t.pumpWidget(
        TextField(
          controller: c,
          autofocus: true,
          keyHints: false,
          onSubmitted: submitted.add,
        ),
        size: (20, 2),
      );
      await type(t, 'ab');
      expect(hints(t), isEmpty);
      await press(t, 'enter');
      await press(t, 'ctrl+z');
      expect(submitted, ['ab']);
      expect(c.text, '');
    });

    testTwk('Ctrl+Z with nothing to undo goes on to the nodes above, whose '
        'hint shows in place of its own', (t) async {
      final undone = <String>[];
      final c = TextEditingController();
      await t.pumpWidget(
        KeyBindings(
          {'ctrl+z': () => undone.add('above')},
          hints: const {'ctrl+z': 'undo above'},
          child: TextField(controller: c, autofocus: true),
        ),
        size: (20, 2),
      );
      expect(hints(t), ['ctrl+z undo above']);
      await type(t, 'a');
      expect(hints(t), ['ctrl+z undo']);
      await press(t, 'ctrl+z');
      expect(c.text, '');
      expect(undone, isEmpty);
      await press(t, 'ctrl+z');
      expect(undone, ['above']);
    });
  });

  group('a TextArea', () {
    testTwk('Enter a new line; with onSubmitted, Enter submit and '
        'Alt+Enter a new line; Ctrl+Z once there is a change', (t) async {
      final submits = ValueNotifier(false);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: submits,
          builder: (context, _) => TextArea(
            autofocus: true,
            onSubmitted: submits.value ? (_) {} : null,
          ),
        ),
        size: (20, 3),
      );
      expect(hints(t), ['enter new line']);
      await type(t, 'a');
      expect(hints(t), ['enter new line', 'ctrl+z undo']);
      submits.value = true;
      await t.pump();
      expect(hints(t), [
        'enter submit',
        'alt+enter new line',
        'ctrl+z undo',
      ]);
    });

    testTwk('keyHints false: none', (t) async {
      await t.pumpWidget(
        const TextArea(autofocus: true, keyHints: false),
        size: (20, 3),
      );
      await type(t, 'a');
      expect(hints(t), isEmpty);
    });
  });

  group('an Autocomplete', () {
    testTwk("while its suggestions show, their keys first, the field's "
        "Enter left out, the popover's Escape last", (t) async {
      final c = TextEditingController();
      await t.pumpWidget(
        completed(
          c,
          TextField(controller: c, autofocus: true, onSubmitted: (_) {}),
        ),
        size: (30, 8),
      );
      expect(hints(t), ['enter submit']);
      await type(t, '/h');
      expect(hints(t), [
        'up choose',
        'down choose',
        'enter put in',
        'tab complete',
        'ctrl+z undo',
        'escape close',
      ]);
      await press(t, 'enter');
      expect(c.text, '/help');
      expect(hints(t), ['enter submit', 'ctrl+z undo']);
    });

    testTwk('in a TextArea, the same', (t) async {
      final c = TextEditingController();
      await t.pumpWidget(
        completed(c, TextArea(controller: c, autofocus: true)),
        size: (30, 8),
      );
      await type(t, '/h');
      expect(hints(t), [
        'up choose',
        'down choose',
        'enter put in',
        'tab complete',
        'ctrl+z undo',
        'escape close',
      ]);
      await press(t, 'escape');
      expect(hints(t), ['enter new line', 'ctrl+z undo']);
    });

    testTwk("keyHints false: none of its own, the field's Enter left out "
        'still while Enter puts one in', (t) async {
      final c = TextEditingController();
      await t.pumpWidget(
        completed(
          c,
          TextField(controller: c, autofocus: true, onSubmitted: (_) {}),
          hinted: false,
        ),
        size: (30, 8),
      );
      await type(t, '/h');
      expect(hints(t), ['ctrl+z undo', 'escape close']);
      await press(t, 'enter');
      expect(c.text, '/help');
      expect(hints(t), ['enter submit', 'ctrl+z undo']);
    });
  });
}
