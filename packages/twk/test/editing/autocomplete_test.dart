// Autocomplete: suggestions under a field as the query changes, after a
// trigger that starts a word or the text before the caret; picked by the
// keys, the shared start put in by Tab, hidden by Escape, by the focus
// leaving and once picked; answers that come later, and those that come
// too late; the query's characters standing out; a TextArea; no Overlay.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const names = ['help', 'history', 'historic', 'clear', 'quit'];

/// The [names] the query matches, as a list of commands gives them.
Iterable<Suggestion> commands(String query) => [
  for (final name in names)
    if (fuzzyMatch(query, name) != null) Suggestion(name),
];

/// A field that edits [c] with an [Autocomplete] around it, over a node
/// that takes the focus; each pick and submit added to [log].
Widget field(
  TextEditingController c, {
  List<String>? log,
  String? trigger = '/',
  FutureOr<Iterable<Suggestion>> Function(String query) suggestions = commands,
  FocusNode? other,
  bool area = false,
}) => Overlay(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Autocomplete(
        controller: c,
        trigger: trigger,
        suggestions: suggestions,
        onSelected: (s) => log?.add('picked ${s.text}'),
        child: area
            ? TextArea(controller: c, autofocus: true)
            : TextField(
                controller: c,
                autofocus: true,
                onSubmitted: (text) => log?.add('submitted $text'),
              ),
      ),
      const SizedBox(height: 6),
      Focus(focusNode: other, child: const Text('other')),
    ],
  ),
);

/// The text of each run of highlighted cells, on the selection's
/// background, under the first row, without its bar: the suggestion
/// highlighted.
List<String> highlighted(TwkTester t) => [
  for (var y = 1; y < t.terminal.height; y++)
    if (t.cell(1, y).bg == const Color.indexed(237).value)
      t.lines[y].replaceFirst('▎', '').trim(),
];

/// The characters drawn in bold on row [y]: blanks, which bold doesn't
/// change and the terminal may be left in it for, not counted.
String bold(TwkTester t, int y) => [
  for (var x = 0; x < t.terminal.width; x++)
    if (t.cell(x, y).attrs & Attr.bold != 0 && t.cell(x, y).text.trim() != '')
      t.cell(x, y).text,
].join();

/// Types [text], pumping until the app is idle: suggestions that fade in
/// have done so.
Future<void> type(TwkTester t, String text) async {
  await t.type(text);
  await t.pumpUntilIdle();
}

Future<void> press(TwkTester t, String keys) async {
  await t.press(keys);
  await t.pumpUntilIdle();
}

void main() {
  testTwk('typing the trigger shows the suggestions under the field, the '
      'first highlighted; Down and Enter put one in place of the query and '
      'hide them', (t) async {
    final c = TextEditingController();
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(child: field(c, log: log)),
      size: (20, 8),
    );
    await t.pump();
    await type(t, '/');
    expect(
      t,
      matchesScreen('''
/
▎help
 history
 historic
 clear
 quit

other'''),
    );
    expect(highlighted(t), ['help']);
    await type(t, 'hi');
    expect(t.lines.take(3), ['/hi', '▎history', ' historic']);
    await press(t, 'down');
    expect(highlighted(t), ['historic']);
    await press(t, 'enter');
    expect(c.text, '/historic');
    expect(c.selection, const TextSelection.collapsed(offset: 9));
    expect(log, ['picked historic']);
    expect(t, matchesScreen('/historic\n\n\n\n\n\n\nother'));
    // a blank ends the word, and with it the query
    await type(t, ' x');
    expect(t, matchesScreen('/historic x\n\n\n\n\n\n\nother'));
  });

  testTwk('the suggestions show on a raised panel: the surface without an '
      'outline, a shadow to its right and below; popupLook bordered gives '
      'a plain look', (t) async {
    const dark = ThemeData.dark;
    final c = TextEditingController();
    // the default look without one
    Widget of([PanelLook? look]) => Theme(
      data: dark,
      child: Overlay(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 20,
            child: look == null
                ? Autocomplete(
                    controller: c,
                    trigger: '/',
                    suggestions: commands,
                    child: TextField(controller: c, autofocus: true),
                  )
                : Autocomplete(
                    controller: c,
                    trigger: '/',
                    suggestions: commands,
                    popupLook: look,
                    child: TextField(controller: c, autofocus: true),
                  ),
          ),
        ),
      ),
    );
    await t.pumpWidget(Theme.terminal(child: of()), size: (30, 10));
    await type(t, '/');
    expect(t.lines[1], '▎help');
    expect(t.cell(1, 1).bg, dark.selection.bg);
    expect(t.cell(0, 2).bg, dark.surface.bg);
    expect(t.cell(9, 2).bg, dark.surface.bg);
    // the shadow: the cells right of the panel darker than the background
    expect(t.cell(10, 2).bg, isNot(dark.background.bg));
    expect(t.cell(10, 2).bg, isNot(dark.surface.bg));
    await t.pumpWidget(Theme.terminal(child: of(PanelLook.bordered)));
    await t.pump();
    expect(t.lines.skip(1).take(2), ['┌──────────┐', '│▎help     │']);
  });

  testTwk('the characters of the query found in a label stand out', (
    t,
  ) async {
    final c = TextEditingController();
    await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 8));
    await t.pump();
    await type(t, '/hc');
    expect(t.lines[1], '▎historic');
    expect(bold(t, 1), 'hc');
  });

  testTwk('a trigger starts a word: at the start of the text or after a '
      'blank', (t) async {
    final c = TextEditingController();
    final asked = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: field(
          c,
          suggestions: (query) {
            asked.add(query);
            return commands(query);
          },
        ),
      ),
      size: (20, 8),
    );
    await t.pump();
    await type(t, 'a/h');
    expect(asked, isEmpty);
    await type(t, ' /q');
    expect(asked, ['', 'q']);
    expect(t.lines[1], '▎quit');
    await press(t, 'enter');
    expect(c.text, 'a/h /quit');
    // what is put in asks for nothing
    expect(asked, ['', 'q']);
  });

  testTwk('without a trigger the text before the caret is the query, and an '
      'empty one asks for nothing', (t) async {
    final c = TextEditingController();
    final asked = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: field(
          c,
          trigger: null,
          suggestions: (query) {
            asked.add(query);
            return commands(query);
          },
        ),
      ),
      size: (20, 8),
    );
    await t.pump();
    await type(t, 'cl');
    expect(asked, ['c', 'cl']);
    expect(t.lines[1], '▎clear');
    await press(t, 'left');
    expect(asked, ['c', 'cl', 'c']);
    await press(t, 'backspace');
    expect(asked, ['c', 'cl', 'c']);
    expect(t, matchesScreen('l\n\n\n\n\n\n\nother'));
    await press(t, 'end');
    expect(asked, ['c', 'cl', 'c', 'l']);
    expect(t.lines.take(3), ['l', '▎help', ' clear']);
  });

  testTwk('suggestions that come in a future show when they come; an answer '
      'that comes after the query changed again does not', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(
      Theme.terminal(
        child: field(
          c,
          suggestions: (query) => Future.delayed(
            Duration(milliseconds: query == 'h' ? 300 : 100),
            () => commands(query),
          ),
        ),
      ),
      size: (20, 8),
    );
    await t.pump();
    await t.type('/h');
    await t.pump();
    expect(t, matchesScreen('/h\n\n\n\n\n\n\nother'));
    await t.type('e');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    // faded in
    await t.pump(const Duration(milliseconds: 120));
    await t.pump();
    expect(t.lines.take(2), ['/he', '▎help']);
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    expect(t.lines.take(3), ['/he', '▎help', '']);
    await press(t, 'enter');
    expect(c.text, '/help');
  });

  testTwk('Tab puts in the start the suggestions share, ignoring case, and '
      'where that is no longer than the query, picks the highlighted one', (
    t,
  ) async {
    final c = TextEditingController();
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(child: field(c, log: log)),
      size: (20, 8),
    );
    await t.pump();
    await type(t, '/HI');
    await press(t, 'tab');
    expect(c.text, '/histor');
    expect(log, isEmpty);
    expect(t.lines.take(4), ['/histor', '▎history', ' historic', '']);
    await press(t, 'tab');
    expect(c.text, '/history');
    expect(log, ['picked history']);
  });

  testTwk('Escape hides the suggestions until the text changes, the caret '
      'moved or not', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 8));
    await t.pump();
    await type(t, '/h');
    await press(t, 'escape');
    expect(t, matchesScreen('/h\n\n\n\n\n\n\nother'));
    await press(t, 'left');
    await press(t, 'right');
    expect(t, matchesScreen('/h\n\n\n\n\n\n\nother'));
    await type(t, 'e');
    expect(t.lines.take(2), ['/he', '▎help']);
  });

  testTwk('while the suggestions show Enter picks one, not submits; hidden, '
      'it submits', (t) async {
    final c = TextEditingController();
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(child: field(c, log: log)),
      size: (20, 8),
    );
    await t.pump();
    await type(t, '/q');
    await press(t, 'enter');
    expect(log, ['picked quit']);
    await press(t, 'enter');
    expect(log, ['picked quit', 'submitted /quit']);
  });

  testTwk('the suggestions hide when the focus leaves the field', (t) async {
    final c = TextEditingController();
    final other = FocusNode();
    addTearDown(other.dispose);
    await t.pumpWidget(
      Theme.terminal(child: field(c, other: other)),
      size: (20, 8),
    );
    await t.pump();
    await type(t, '/');
    expect(t.lines[1], '▎help');
    other.requestFocus();
    await t.pump();
    expect(t, matchesScreen('/\n\n\n\n\n\n\nother'));
  });

  testTwk('in a TextArea Up and Down move among the suggestions while they '
      'show, and the caret while they do not', (t) async {
    final c = TextEditingController(text: 'first\n');
    await t.pumpWidget(
      Theme.terminal(child: field(c, area: true)),
      size: (20, 9),
    );
    await t.pump();
    await type(t, '/');
    await press(t, 'down');
    await press(t, 'down');
    expect(highlighted(t), ['historic']);
    await press(t, 'up');
    await press(t, 'enter');
    expect(c.text, 'first\n/history');
    await press(t, 'up');
    expect(c.selection, const TextSelection.collapsed(offset: 5));
  });

  testTwk('an Autocomplete without an Overlay above fails to build, saying '
      'where to place one', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(
      Autocomplete(
        controller: c,
        suggestions: commands,
        child: TextField(controller: c),
      ),
    );
    const failed =
        'Autocomplete failed to build: Bad state: Autocomplete: no Overlay '
        'above it: place an Overlay above it, as around the whole app: '
        'Overlay(child: …)';
    expect(
      [
        for (final r in t.logs.records)
          if (r.level == LogLevel.error) '${r.message}: ${r.error}',
      ],
      [failed],
    );
  });

  test('a Suggestion is equal to another of the same text, label and '
      'detail, and describes itself by its text', () {
    // not a constant, which is one object when equal
    final text = ['git'].single;
    final a = Suggestion(text, label: 'g', detail: 'vcs');
    expect(a, Suggestion(text, label: 'g', detail: 'vcs'));
    expect(a.hashCode, Suggestion(text, label: 'g', detail: 'vcs').hashCode);
    expect(a, isNot(Suggestion(text, label: 'g')));
    expect(a, isNot(Suggestion(text, detail: 'vcs')));
    expect(a, isNot(const Suggestion('hg', label: 'g', detail: 'vcs')));
    expect('$a', 'Suggestion(git)');
  });
}
