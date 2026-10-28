// A JsonView in an app: a value as rows of a tree, the top expanded,
// objects and arrays folded with their counts, each kind in its style;
// Enter and Space folding, a string cut and shown whole; `c` copying the
// path, `y` the value as JSON; `*`, expandAll, collapseAll and reveal; `/`
// filtering the keys; the keys hinted; toJson objects and cycles; and a
// parse error shown where it is.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

const Map<String, Object?> doc = {
  'name': 'twk',
  'version': '0.1.0',
  'dependencies': {'meta': 1, 'test': 2, 'twk': 3, 'xtask': 4},
  'scripts': ['quick', 'handover'],
};

const red = Color.rgb(255, 0, 0);
const green = Color.rgb(0, 255, 0);
const blue = Color.rgb(0, 0, 255);
const cyan = Color.rgb(0, 255, 255);
const magenta = Color.rgb(255, 0, 255);

/// The texts the app copied to the clipboard (OSC 52), in order.
List<String> copied(TwkTester t) => [
  for (final m in RegExp(r'\x1b\]52;c;([A-Za-z0-9+/=]*)').allMatches(
    utf8.decode([
      for (final f in t.terminal.frames) ...f,
    ], allowMalformed: true),
  ))
    utf8.decode(base64.decode(m[1]!)),
];

/// The keys a `KeyHintsBar` shows now, with their hints.
List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// Presses [keys] and pumps the frame they ask for.
Future<void> press(TwkTester t, String keys) async {
  await t.press(keys);
  await t.pump();
}

/// The rows of the screen that are not blank.
List<String> shown(TwkTester t) => [
  for (final line in t.lines)
    if (line.isNotEmpty) line,
];

final class Point {
  const Point(this.x, this.y);

  final int x;
  final int y;

  Map<String, Object?> toJson() => {'x': x, 'y': y};
}

void main() {
  group('rows', () {
    testTwk('the top object is expanded, the objects and arrays in it '
        'collapsed with their counts, a row closing it', (t) async {
      await t.pumpWidget(const JsonView(value: doc), size: (40, 8));
      expect(shown(t), [
        '▾ {',
        '├── "name": "twk",',
        '├── "version": "0.1.0",',
        '├─▸ "dependencies": { 4 keys },',
        '├─▸ "scripts": [ 2 items ]',
        '└── }',
      ]);
    });

    testTwk('expandedDepth expands as many levels as it says', (t) async {
      await t.pumpWidget(
        JsonView(
          value: doc,
          controller: JsonViewController(expandedDepth: 2),
        ),
        size: (40, 14),
      );
      expect(shown(t), [
        '▾ {',
        '├── "name": "twk",',
        '├── "version": "0.1.0",',
        '├─▾ "dependencies": {',
        '│ ├── "meta": 1,',
        '│ ├── "test": 2,',
        '│ ├── "twk": 3,',
        '│ ├── "xtask": 4',
        '│ └── },',
        '├─▾ "scripts": [',
        '│ ├── "quick",',
        '│ ├── "handover"',
        '│ └── ]',
        '└── }',
      ]);
      await t.pumpWidget(
        JsonView(
          value: doc,
          controller: JsonViewController(expandedDepth: 0),
        ),
        size: (40, 14),
      );
      expect(shown(t), ['▸ { 4 keys }']);
    });

    testTwk('a value that is no object or array is the one row', (t) async {
      await t.pumpWidget(const JsonView(value: 'hi'), size: (10, 2));
      expect(shown(t), ['  "hi"']);
    });

    testTwk('an empty object or array shows its brackets, without an '
        'expander', (t) async {
      await t.pumpWidget(
        const JsonView(value: {'a': <Object?>[], 'b': <String, Object?>{}}),
        size: (20, 4),
      );
      expect(shown(t), ['▾ {', '├── "a": [],', '├── "b": {}', '└── }']);
    });

    testTwk('each kind is in its style of the SyntaxThemeScope', (t) async {
      await t.pumpWidget(
        const SyntaxThemeScope(
          theme: SyntaxTheme(
            key: Style(fg: red),
            string: Style(fg: green),
            number: Style(fg: blue),
            constant: Style(fg: cyan),
            punctuation: Style(fg: magenta),
          ),
          child: JsonView(value: {'k': 's', 'n': 1, 'b': true}),
        ),
        size: (20, 5),
      );
      expect(shown(t)[1], '├── "k": "s",');
      expect(t.cell(2, 0), hasFg(magenta)); // {
      expect(t.cell(4, 1), hasFg(red)); // "k"
      expect(t.cell(7, 1), hasFg(magenta)); // :
      expect(t.cell(9, 1), hasFg(green)); // "s"
      expect(t.cell(12, 1), hasFg(magenta)); // ,
      expect(t.cell(9, 2), hasFg(blue)); // 1
      expect(t.cell(9, 3), hasFg(cyan)); // true
    });

    testTwk("theme, where given, is taken over the scope's", (t) async {
      await t.pumpWidget(
        const SyntaxThemeScope(
          theme: SyntaxTheme(string: Style(fg: green)),
          child: JsonView(
            value: 's',
            theme: SyntaxTheme(string: Style(fg: red)),
          ),
        ),
        size: (10, 1),
      );
      expect(t.cell(2, 0), hasFg(red));
    });

    testTwk('sortKeys orders the keys', (t) async {
      await t.pumpWidget(
        const JsonView(value: {'b': 1, 'a': 2}, sortKeys: true),
        size: (20, 4),
      );
      expect(shown(t), ['▾ {', '├── "a": 2,', '├── "b": 1', '└── }']);
    });

    testTwk('an object shows as its toJson, a value inside itself as '
        '<cycle>', (t) async {
      final map = <String, Object?>{'at': const Point(1, 2)};
      map['self'] = map;
      await t.pumpWidget(
        JsonView(value: map, controller: JsonViewController(expandedDepth: 9)),
        size: (30, 7),
      );
      expect(shown(t), [
        '▾ {',
        '├─▾ "at": {',
        '│ ├── "x": 1,',
        '│ ├── "y": 2',
        '│ └── },',
        '├── "self": <cycle>',
        '└── }',
      ]);
    });
  });

  group('folding', () {
    testTwk('Enter and Space fold the object or array selected', (t) async {
      final c = JsonViewController()..reveal(r'$.scripts');
      await t.pumpWidget(
        JsonView(value: doc, controller: c, autofocus: true),
        size: (40, 9),
      );
      await press(t, 'enter');
      expect(shown(t).sublist(4, 7), [
        '├─▾ "scripts": [',
        '│ ├── "quick",',
        '│ ├── "handover"',
      ]);
      expect(c.isExpanded(r'$.scripts'), isTrue);
      await press(t, 'space');
      expect(shown(t)[4], '├─▸ "scripts": [ 2 items ]');
      await press(t, 'space');
      expect(shown(t)[4], '├─▾ "scripts": [');
    });

    testTwk('Enter on the row that closes an array folds it and selects it', (
      t,
    ) async {
      final c = JsonViewController(expandedDepth: 2)..reveal(r'$.scripts');
      await t.pumpWidget(
        JsonView(value: doc, controller: c, autofocus: true),
        size: (40, 14),
      );
      await press(t, 'down');
      await press(t, 'down');
      await press(t, 'down');
      expect(c.selectedPath, r'$.scripts');
      await press(t, 'enter');
      expect(c.isExpanded(r'$.scripts'), isFalse);
      expect(c.selectedPath, r'$.scripts');
      expect(shown(t).last, '└── }');
    });

    testTwk('a string longer than maxStringLength is cut with … until Enter '
        'shows it whole, and Enter cuts it again', (t) async {
      final c = JsonViewController()..reveal(r'$[0]');
      await t.pumpWidget(
        JsonView(
          value: const ['abcdefgh', 'abc'],
          controller: c,
          maxStringLength: 4,
          autofocus: true,
        ),
        size: (30, 4),
      );
      expect(shown(t).sublist(1, 3), ['├── "abcd…",', '├── "abc"']);
      expect(hints(t), contains('enter show whole'));
      await press(t, 'enter');
      expect(shown(t)[1], '├── "abcdefgh",');
      expect(hints(t), contains('enter cut'));
      await press(t, 'enter');
      expect(shown(t)[1], '├── "abcd…",');
    });

    testTwk('* expands everything below the value selected', (t) async {
      const nested = {
        'a': {
          'b': {'c': 1},
        },
        'd': [1],
      };
      final c = JsonViewController()..reveal(r'$.a');
      await t.pumpWidget(
        JsonView(value: nested, controller: c, autofocus: true),
        size: (30, 10),
      );
      await press(t, '*');
      expect(shown(t), [
        '▾ {',
        '├─▾ "a": {',
        '│ ├─▾ "b": {',
        '│ │ ├── "c": 1',
        '│ │ └── }',
        '│ └── },',
        '├─▸ "d": [ 1 item ]',
        '└── }',
      ]);
    });

    testTwk('expandAll expands every object and array, collapseAll every '
        'one, selecting the top where the selection was below', (t) async {
      final c = JsonViewController()..reveal(r'$.scripts[1]');
      await t.pumpWidget(
        JsonView(value: doc, controller: c),
        size: (40, 16),
      );
      c.expandAll();
      await t.pump();
      expect(shown(t), hasLength(14));
      c.collapseAll();
      await t.pump();
      expect(shown(t), ['▸ { 4 keys }']);
      expect(c.selectedPath, r'$');
    });

    testTwk('what is expanded and selected stays by path as the value '
        'changes', (t) async {
      final c = JsonViewController()..reveal(r'$.scripts[1]');
      await t.pumpWidget(
        JsonView(value: doc, controller: c),
        size: (40, 9),
      );
      await t.pumpWidget(
        JsonView(
          value: const {
            'scripts': ['ci', 'bench', 'quick'],
          },
          controller: c,
        ),
        size: (40, 9),
      );
      expect(shown(t), [
        '▾ {',
        '├─▾ "scripts": [',
        '│ ├── "ci",',
        '│ ├── "bench",',
        '│ ├── "quick"',
        '│ └── ]',
        '└── }',
      ]);
      expect(c.selectedValue, 'bench');
    });

    testTwk('expandAll before a view waits for one', (t) async {
      final c = JsonViewController(expandedDepth: 0)..expandAll();
      await t.pumpWidget(
        JsonView(value: doc, controller: c),
        size: (40, 16),
      );
      expect(shown(t), hasLength(14));
    });

    testTwk('reveal expands what is above a value and selects it, which '
        'selectedPath and selectedValue tell', (t) async {
      const point = Point(3, 4);
      final c = JsonViewController(expandedDepth: 0);
      await t.pumpWidget(
        JsonView(
          value: const {
            'a key': [point],
          },
          controller: c,
          rootName: 'data',
        ),
        size: (30, 9),
      );
      expect(c.selectedPath, 'data');
      c.reveal('data["a key"][0].y');
      await t.pump();
      expect(shown(t), [
        '▾ {',
        '├─▾ "a key": [',
        '│ ├─▾ {',
        '│ │ ├── "x": 3,',
        '│ │ ├── "y": 4',
        '│ │ └── }',
        '│ └── ]',
        '└── }',
      ]);
      expect(c.selectedValue, 4);
      c.reveal('data["a key"][0]');
      expect(c.selectedValue, same(point));
      c.reveal('data["a key"][7]');
      expect(c.selectedValue, isNull);
    });
  });

  group('copying', () {
    testTwk('c copies the path of the value selected and calls onPathCopied '
        'with it', (t) async {
      final paths = <String>[];
      final c = JsonViewController(expandedDepth: 2)..reveal(r'$["a key"][1]');
      await t.pumpWidget(
        JsonView(
          value: const {
            'a key': [1, 2],
          },
          controller: c,
          onPathCopied: paths.add,
          autofocus: true,
        ),
        size: (30, 6),
      );
      await press(t, 'c');
      await press(t, 'home');
      await press(t, 'c');
      expect(paths, [r'$["a key"][1]', r'$']);
      expect(copied(t), paths);
    });

    testTwk('y copies the value selected as JSON, indented', (t) async {
      final c = JsonViewController()..reveal(r'$.scripts');
      await t.pumpWidget(
        JsonView(value: doc, controller: c, autofocus: true),
        size: (40, 8),
      );
      await press(t, 'y');
      await press(t, 'up');
      await press(t, 'y');
      expect(copied(t), [
        '[\n  "quick",\n  "handover"\n]',
        '{\n  "meta": 1,\n  "test": 2,\n  "twk": 3,\n  "xtask": 4\n}',
      ]);
    });

    testTwk('y copies a cycle and an object as their JSON', (t) async {
      final list = <Object?>[const Point(1, 2)];
      list.add(list);
      final c = JsonViewController();
      await t.pumpWidget(
        JsonView(value: list, controller: c, autofocus: true),
        size: (30, 5),
      );
      await press(t, 'y');
      expect(jsonDecode(copied(t).single), [
        {'x': 1, 'y': 2},
        '<cycle>',
      ]);
    });

    testTwk('the keys are hinted while the view has the focus', (t) async {
      final c = JsonViewController();
      await t.pumpWidget(
        JsonView(value: doc, controller: c, autofocus: true),
        size: (40, 8),
      );
      expect(hints(t), [
        'enter collapse',
        'space collapse',
        'c copy path',
        'y copy value',
        '/ filter keys',
      ]);
      await press(t, 'down');
      expect(hints(t), ['c copy path', 'y copy value', '/ filter keys']);
    });
  });

  group('filter', () {
    testTwk('/ filters the keys as typed: the matches show with the '
        'objects above them, expanded, the best selected', (t) async {
      const config = {
        'name': 'twk',
        'server': {'host': 'localhost', 'port': 80},
        'client': {
          'retries': 3,
          'proxy': {'port': 8080},
        },
      };
      final c = JsonViewController();
      await t.pumpWidget(
        JsonView(value: config, controller: c, autofocus: true),
        size: (40, 12),
      );
      await press(t, '/');
      await t.pump();
      await t.type('prt');
      await t.pump();
      expect(shown(t), [
        '▾ {',
        '├─▾ "server": {',
        '│ ├── "port": 80',
        '│ └── },',
        '├─▾ "client": {',
        '│ ├─▾ "proxy": {',
        '│ │ ├── "port": 8080',
        '│ │ └── }',
        '│ └── }',
        '└── }',
        '/ prt',
      ]);
      expect(c.selectedPath, r'$.server.port');
      // the characters found stand out
      expect(t.cell(7, 2), hasAttr(Attr.bold)); // p
      expect(t.cell(8, 2), isNot(hasAttr(Attr.bold))); // o
    });

    testTwk('the entries below a match all show', (t) async {
      const config = {
        'server': {'host': 'localhost', 'port': 80},
        'name': 'twk',
      };
      await t.pumpWidget(
        JsonView(
          value: config,
          controller: JsonViewController(expandedDepth: 2),
          autofocus: true,
        ),
        size: (40, 8),
      );
      await press(t, '/');
      await t.pump();
      await t.type('serv');
      await t.pump();
      expect(shown(t), [
        '▾ {',
        '├─▾ "server": {',
        '│ ├── "host": "localhost",',
        '│ ├── "port": 80',
        '│ └── },',
        '└── }',
        '/ serv',
      ]);
    });

    testTwk('Enter goes back to the tree with the filter kept, Escape clears '
        'it and puts back what was expanded', (t) async {
      final c = JsonViewController();
      await t.pumpWidget(
        JsonView(value: doc, controller: c, autofocus: true),
        size: (40, 9),
      );
      await press(t, '/');
      await t.pump();
      await t.type('twk');
      await t.pump();
      expect(shown(t), [
        '▾ {',
        '├─▾ "dependencies": {',
        '│ ├── "twk": 3,',
        '│ └── },',
        '└── }',
        '/ twk',
      ]);
      await press(t, 'enter');
      await t.pump();
      expect(hints(t), contains('escape clear filter'));
      expect(hints(t), contains('c copy path'));
      await press(t, 'c');
      expect(copied(t), [r'$.dependencies.twk']);
      await press(t, 'escape');
      await t.pump();
      expect(shown(t), [
        '▾ {',
        '├── "name": "twk",',
        '├── "version": "0.1.0",',
        '├─▾ "dependencies": {',
        '│ ├── "meta": 1,',
        '│ ├── "test": 2,',
        '│ ├── "twk": 3,',
        '│ ├── "xtask": 4',
        '│ └── },',
      ]);
      expect(c.selectedPath, r'$.dependencies.twk');
      expect(c.isExpanded(r'$.dependencies'), isTrue);
    });

    testTwk('Escape in the field clears the filter, the tree back as it was', (
      t,
    ) async {
      final c = JsonViewController();
      await t.pumpWidget(
        JsonView(value: doc, controller: c, autofocus: true),
        size: (40, 8),
      );
      await press(t, '/');
      await t.pump();
      await t.type('zzz');
      await t.pump();
      expect(shown(t), ['▾ {', '└── }', '/ zzz']);
      await press(t, 'escape');
      await t.pump();
      expect(shown(t), hasLength(6));
      expect(c.isExpanded(r'$.dependencies'), isFalse);
      expect(c.selectedPath, r'$');
    });
  });

  group('parse', () {
    testTwk('shows the value of JSON text', (t) async {
      await t.pumpWidget(
        const JsonView.parse('{"a": [1, 2.5e3, null]}'),
        size: (20, 4),
      );
      expect(shown(t), ['▾ {', '├─▸ "a": [ 3 items ]', '└── }']);
    });

    testTwk('text that is no JSON shows the error, the line it is in and a '
        'caret under the place', (t) async {
      await t.pumpWidget(
        const JsonView.parse('{\n  "name": twk\n}'),
        size: (50, 4),
      );
      expect(shown(t), [
        'Unexpected character at line 2, column 11',
        '  "name": twk',
        '          ^',
      ]);
      await t.pumpWidget(
        const JsonView.parse('{"a": 1}'),
        size: (50, 4),
      );
      expect(shown(t), ['▾ {', '├── "a": 1', '└── }']);
    });
  });
}
