// The paths of values (jsonPath): keys that are identifiers after a dot,
// odd ones quoted and escaped in brackets, indices in brackets, the root
// named; and jsonLines, a value's look as lines of spans: expanded fully
// or to a depth, its kinds in the theme's styles, keys sorted, strings
// cut, objects through toJson, and cycles.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';

const red = Color.rgb(255, 0, 0);
const green = Color.rgb(0, 255, 0);
const blue = Color.rgb(0, 0, 255);
const cyan = Color.rgb(0, 255, 255);
const magenta = Color.rgb(255, 0, 255);
const yellow = Color.rgb(255, 255, 0);
const grey = Color.rgb(128, 128, 128);

/// A theme with a color of its own for each kind a JSON value shows in.
const colors = SyntaxTheme(
  key: Style(fg: red),
  string: Style(fg: green),
  number: Style(fg: blue),
  constant: Style(fg: cyan),
  punctuation: Style(fg: magenta),
  escape: Style(fg: yellow),
  comment: Style(fg: grey),
);

/// [lines] as text.
List<String> text(List<List<Span>> lines) => [
  for (final line in lines) line.map((s) => s.text).join(),
];

final class Point {
  const Point(this.x, this.y);

  final int x;
  final int y;

  Map<String, Object?> toJson() => {'x': x, 'y': y};
}

final class Opaque {
  @override
  String toString() => 'opaque!';
}

final class Self {
  Map<String, Object?> toJson() => {'self': this};
}

final class Throws {
  Object? toJson() => throw StateError('no');
}

void main() {
  group('jsonPath', () {
    test('a key that is an identifier follows a dot, an index is in '
        'brackets', () {
      expect(jsonPath(['scripts', 0, 'name']), r'$.scripts[0].name');
      expect(jsonPath(['_a1', r'$b']), r'$._a1.$b');
      expect(jsonPath([]), r'$');
    });

    test('any other key is in brackets, quoted and escaped as JSON', () {
      expect(jsonPath(['a key']), r'$["a key"]');
      expect(jsonPath(['1st']), r'$["1st"]');
      expect(jsonPath(['']), r'$[""]');
      expect(jsonPath(['say "hi"']), r'$["say \"hi\""]');
      expect(jsonPath([r'back\slash']), r'$["back\\slash"]');
      expect(jsonPath(['a.b', 'c[0]']), r'$["a.b"]["c[0]"]');
      expect(jsonPath(['ключ']), r'$["ключ"]');
      expect(jsonPath(['line\nbreak']), r'$["line\nbreak"]');
    });

    test('an index and a key of the same digits differ', () {
      expect(jsonPath([0]), r'$[0]');
      expect(jsonPath(['0']), r'$["0"]');
    });

    test('the root is named as given', () {
      expect(jsonPath(['scripts', 0], root: 'data'), 'data.scripts[0]');
      expect(jsonPath(['a key'], root: 'data'), 'data["a key"]');
      expect(jsonPath([], root: ''), '');
    });

    test('a key of another type is named by its toString', () {
      expect(jsonPath([#sym, 1.5]), r'$["Symbol(\"sym\")"]["1.5"]');
    });
  });

  group('jsonLines', () {
    const doc = {
      'name': 'twk',
      'version': 1,
      'tags': ['tui', 'dart'],
      'deps': {'a': true, 'b': null},
      'empty': <Object?>[],
      'none': <String, Object?>{},
    };

    test('every object and array expanded, indented two blanks a level, '
        'with commas and closing brackets', () {
      expect(text(jsonLines(doc)), [
        '{',
        '  "name": "twk",',
        '  "version": 1,',
        '  "tags": [',
        '    "tui",',
        '    "dart"',
        '  ],',
        '  "deps": {',
        '    "a": true,',
        '    "b": null',
        '  },',
        '  "empty": [],',
        '  "none": {}',
        '}',
      ]);
    });

    test('below expandedDepth, an object shows how many keys it has and an '
        'array how many items', () {
      expect(text(jsonLines(doc, expandedDepth: 1)), [
        '{',
        '  "name": "twk",',
        '  "version": 1,',
        '  "tags": [ 2 items ],',
        '  "deps": { 2 keys },',
        '  "empty": [],',
        '  "none": {}',
        '}',
      ]);
      expect(text(jsonLines(doc, expandedDepth: 0)), ['{ 6 keys }']);
      expect(text(jsonLines([1], expandedDepth: 0)), ['[ 1 item ]']);
      expect(text(jsonLines({'a': 1}, expandedDepth: 0)), ['{ 1 key }']);
    });

    test('a value that is no object or array is a line of its own', () {
      expect(text(jsonLines('a')), ['"a"']);
      expect(text(jsonLines(1.5)), ['1.5']);
      expect(text(jsonLines(null)), ['null']);
      expect(text(jsonLines(false)), ['false']);
    });

    test('each kind is in its style of the theme', () {
      final line = jsonLines({
        'k': ['s\n', 2, true, null],
      }, theme: colors);
      expect(line[0], [const Span('{', Style(fg: magenta))]);
      expect(line[1], [
        const Span('  '),
        const Span('"k"', Style(fg: red)),
        const Span(': ', Style(fg: magenta)),
        const Span('[', Style(fg: magenta)),
      ]);
      expect(line[2].skip(1), [
        const Span('"s', Style(fg: green)),
        const Span(r'\n', Style(fg: yellow)),
        const Span('"', Style(fg: green)),
        const Span(',', Style(fg: magenta)),
      ]);
      expect(line[3][1], const Span('2', Style(fg: blue)));
      expect(line[4][1], const Span('true', Style(fg: cyan)));
      expect(line[5][1], const Span('null', Style(fg: cyan)));
      final collapsed = jsonLines([1, 2], theme: colors, expandedDepth: 0);
      expect(collapsed.single, [
        const Span('[ ', Style(fg: magenta)),
        const Span('2 items', Style(fg: grey)),
        const Span(' ]', Style(fg: magenta)),
      ]);
    });

    test('without a theme, the terminal colors of the default one', () {
      final theme = SyntaxTheme.from(
        const ThemeData.terminal(Brightness.dark),
      );
      expect(jsonLines('a').single.single.style, theme.string);
    });

    test('sortKeys orders the keys of each object', () {
      expect(
        text(
          jsonLines({
            'b': 1,
            'a': {'d': 1, 'c': 2},
          }, sortKeys: true),
        ),
        ['{', '  "a": {', '    "c": 2,', '    "d": 1', '  },', '  "b": 1', '}'],
      );
    });

    test('a string longer than maxStringLength is cut with …', () {
      expect(text(jsonLines('abcdef', maxStringLength: 3)), ['"abc…"']);
      expect(text(jsonLines('abc', maxStringLength: 3)), ['"abc"']);
      expect(text(jsonLines('🙂🙂🙂🙂', maxStringLength: 2)), ['"🙂🙂…"']);
    });

    test('an object shows as its toJson, else as its toString in a string, '
        'one whose toJson throws as the error', () {
      expect(
        text(jsonLines([const Point(1, 2), Opaque(), Throws()])),
        [
          '[',
          '  {',
          '    "x": 1,',
          '    "y": 2',
          '  },',
          '  "opaque!",',
          '  <toJson() threw Bad state: no>',
          ']',
        ],
      );
    });

    test('a map key that is no string shows as its text, an int key too', () {
      expect(text(jsonLines({1: 'a', #b: 'c'})), [
        '{',
        '  "1": "a",',
        r'  "Symbol(\"b\")": "c"',
        '}',
      ]);
    });

    test('a set shows as an array', () {
      expect(text(jsonLines({1, 2})), ['[', '  1,', '  2', ']']);
    });

    test('a value inside itself shows as <cycle>, a value met twice apart '
        'in full', () {
      final map = <String, Object?>{'name': 'loop'};
      map['self'] = map;
      final list = <Object?>[1];
      list.add(list);
      final shared = [1];
      expect(text(jsonLines(map)), [
        '{',
        '  "name": "loop",',
        '  "self": <cycle>',
        '}',
      ]);
      expect(text(jsonLines(list)), ['[', '  1,', '  <cycle>', ']']);
      expect(text(jsonLines([Self()])), [
        '[',
        '  {',
        '    "self": <cycle>',
        '  }',
        ']',
      ]);
      expect(text(jsonLines([shared, shared], expandedDepth: 1)), [
        '[',
        '  [ 1 item ],',
        '  [ 1 item ]',
        ']',
      ]);
    });
  });
}
