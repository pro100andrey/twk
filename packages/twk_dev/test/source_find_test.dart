// Where a widget was made, looked for in the source of the build methods
// above it (lib/src/source_find.dart; the cases of the VS Code extension's
// source_find.test.ts): the builds that may have made it, the calls of its
// type's constructor in code (not in comments or strings), and which of
// them made it.
import 'package:test/test.dart';
import 'package:twk_dev/src/source_find.dart';

var _nextId = 1;

/// A node of a tree for a test; [build] for one that builds.
InspectNode n(
  String name, [
  List<InspectNode> children = const [],
  String? build,
]) => InspectNode({
  'id': _nextId++,
  'name': name,
  'build': ?build,
  'children': [for (final c in children) c.json],
});

List<(String, int, int)> owned(List<CreationOwner> owners) => [
  for (final o in owners) (o.build, o.index, o.count),
];

void main() {
  test('the builds above it, the nearest first, each with its place among '
      'those of its type that build made', () {
    // Page builds Column [Text a, Card(child: Text b), Text c]; Card
    // builds Padding(child: its child)
    final a = n('Text');
    final b = n('Text');
    final c = n('Text');
    final card = n('Card', [
      n('Padding', [b]),
    ], 'Card');
    final page = n('Page', [
      n('Column', [a, card, c]),
    ], '_PageState');
    final root = n('RootWidget', [page]);

    expect(owned(creationOwners(root, b.id)), [
      // in Card's build no Text but b (passed through it)
      ('Card', 0, 1),
      // in the page's: a, b (through Card, on the way), c
      ('_PageState', 1, 3),
    ]);
    // c: Card's build is another's, not looked into
    expect(owned(creationOwners(root, c.id)), [('_PageState', 1, 2)]);
    // Card's build makes no Text: what is below it was passed to it, made
    // above
    expect(owned(creationOwners(root, c.id, (build) => build != 'Card')), [
      ('_PageState', 2, 3),
    ]);
    expect(buildsIn(root), {'Card', '_PageState'});
    // a component element is made by the build above it, not by its own
    expect(owned(creationOwners(root, card.id)), [('_PageState', 0, 1)]);
    expect(creationOwners(root, 99999), isEmpty);
    expect(creationOwners(null, 1), isEmpty);
  });

  test("a generic type's class", () {
    expect(className('ValueListenableBuilder<int>'), 'ValueListenableBuilder');
    expect(className('Text'), 'Text');
    final list = n('ListView<int>');
    final page = n('Page', [list], 'Page');
    expect(
      creationOwners(n('R', [page]), list.id).map((o) => o.count),
      [1],
    );
  });

  test('blanks comments, nested ones too, and strings, keeping every '
      'offset', () {
    const source =
        "a // Text(\nb /* x /* Text( */ y */ c 'Text(' \"it's\" r'\\' d '''\n"
        "Text(''' e";
    final code = codeOnly(source);
    expect(code.length, source.length);
    expect(code, isNot(contains('Text')));
    expect(
      RegExp(r'\b[a-e]\b').allMatches(code).map((m) => m[0]),
      ['a', 'b', 'c', 'd', 'e'],
    );
    // lines kept
    expect(code.split('\n').length, source.split('\n').length);
  });

  test('a quote in an interpolation does not end its string', () {
    const source =
        "a '\${m['k']} Text(' b \"x\${xs.map((e) => 'y').join()}Text(\" c "
        // both kinds of quote are in it, and a raw string cannot hold them
        // ignore: use_raw_strings
        "'\${f({'a': 1})}Text(' d '''\${g('''Text(''')}Text(''' e";
    final code = codeOnly(source);
    expect(code.length, source.length);
    expect(code, isNot(contains('Text')));
    expect(
      RegExp(r'\b[a-e]\b').allMatches(code).map((m) => m[0]),
      ['a', 'b', 'c', 'd', 'e'],
    );
  });

  test('finds the calls of a constructor in code, whatever their form, '
      'between two offsets', () {
    final source = [
      'Widget build(BuildContext context) {', // 1
      "  // Text('no')", // 2
      '  return Column(children: [', // 3
      "    const Text('a'),", // 4
      "    Text.rich('b'),", // 5
      "    w.Text ('c'),", // 6
      '    TextField(), MyText(), _Text(), Texts(),', // 7
      '    Foo<int>(),', // 8
      '  ]);', // 9
      '}', // 10
      "Text('after')", // 11
    ].join('\n');
    final end = source.lastIndexOf('}') + 1;
    List<({int line, int column})> places(String type, [int from = 0]) => [
      for (final o in constructorCalls(source, from, end, type))
        lineColumnOf(source, o),
    ];
    expect(places('Text'), [
      (line: 4, column: 11),
      (line: 5, column: 5),
      (line: 6, column: 7),
    ]);
    expect(places('Foo').map((p) => p.line), [8]);
    expect(places('_Text').map((p) => p.line), [7]);
    // only from where it is asked
    expect(places('Text', offsetOf(source, 5, 1)).map((p) => p.line), [5, 6]);
  });

  test('lines and columns of offsets and of token positions', () {
    const source = 'ab\ncd\n\nef';
    expect(lineColumnOf(source, 0), (line: 1, column: 1));
    expect(lineColumnOf(source, 4), (line: 2, column: 2));
    expect(lineColumnOf(source, 7), (line: 4, column: 1));
    expect(offsetOf(source, 2, 2), 4);
    expect(offsetOf(source, 4, 2), 8);
    expect(offsetOf(source, 9, 1), source.length);
    const table = [
      [3, 10, 1, 12, 5],
      [4, 20, 3],
    ];
    expect(tokenLineColumn(table, 12), (line: 3, column: 5));
    expect(tokenLineColumn(table, 20), (line: 4, column: 3));
    expect(tokenLineColumn(table, 11), isNull);
  });

  test('the call that made it: the only one, or the one at its place when '
      'there are as many', () {
    expect(pickCall([10], 2, 3), (offset: 10, exact: true));
    expect(pickCall([10, 20, 30], 1, 3), (offset: 20, exact: true));
    // a loop, an if: not as many calls as elements
    expect(pickCall([10, 20], 3, 4), (offset: 20, exact: false));
    expect(pickCall([], 0, 1), isNull);
  });
}
