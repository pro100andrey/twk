// Finders as values: each kind evaluated over a live tree in-process, read
// back from its JSON, and refused where it cannot cross the wire; and the
// cells of a render object the screen shows.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'tile_a.dart' as a;
import 'tile_b.dart' as b;

final class Box<T> extends StatelessWidget {
  const Box(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The tree under test: boxes of two type arguments, keyed texts, two
/// widgets of one name from two libraries.
const tree = Column(
  children: [
    Box<String>(Text('one', key: Key('one'))),
    Box<int>(Text('two', key: ValueKey<int>(2))),
    Text.rich([Span('th'), Span('ree')]),
    a.Tile(),
    b.Tile(),
  ],
);

void main() {
  /// The texts of the Texts [finder] finds in [t]'s app.
  List<String> found(TwkTester t, ElementFinder finder) {
    final root = find.byType(Column).evaluate().single;
    return [
      for (final e in finder.evaluate(root))
        if (e.widget case final Text text)
          (text.data ?? [for (final s in text.spans!) s.text].join())
        else
          '${e.widget.runtimeType}',
    ];
  }

  testTwk('each kind finds over a live tree, in the order of the tree', (
    t,
  ) async {
    await t.pumpWidget(tree, size: (20, 8));
    expect(found(t, const ElementFinder.text('one')), ['one']);
    expect(found(t, const ElementFinder.text('three')), ['three']);
    expect(found(t, const ElementFinder.text('thr')), isEmpty);
    expect(found(t, const ElementFinder.textContaining('t')), [
      'two',
      'three',
    ]);
    expect(
      found(t, ElementFinder.textMatches(RegExp('^T', caseSensitive: false))),
      [
        'two',
        'three',
      ],
    );
    expect(found(t, const ElementFinder.key(Key('one'))), ['one']);
    expect(found(t, const ElementFinder.key(ValueKey<int>(2))), ['two']);
    expect(found(t, const ElementFinder.key(ValueKey<num>(2))), isEmpty);
    expect(found(t, const ElementFinder.type(Box<String>)), ['Box<String>']);
    expect(found(t, const ElementFinder.type(Box<int>)), ['Box<int>']);
    expect(
      found(
        t,
        const ElementFinder.descendant(
          of: ElementFinder.type(Box<int>),
          matching: ElementFinder.type(Text),
        ),
      ),
      ['two'],
    );
    expect(
      found(
        t,
        const ElementFinder.ancestor(
          of: ElementFinder.text('one'),
          matching: ElementFinder.type(Box<String>),
        ),
      ),
      ['Box<String>'],
    );
    expect(found(t, const ElementFinder.type(Text).at(1)), ['two']);
    expect(found(t, const ElementFinder.type(Text).last), ['b']);
    expect(found(t, const ElementFinder.type(Text).first), ['one']);
  });

  testTwk('a finder read from JSON finds what the one it was written from '
      'did, and a node is what the resolver names', (t) async {
    await t.pumpWidget(tree, size: (20, 8));
    final root = find.byType(Column).evaluate().single;
    final three = const ElementFinder.text('three').evaluate(root).single;
    for (final finder in [
      const ElementFinder.text('one'),
      const ElementFinder.textContaining('t'),
      ElementFinder.textMatches(RegExp('^t')),
      const ElementFinder.type(Box<int>),
      const ElementFinder.key(Key('one')),
      const ElementFinder.key(ValueKey<int>(2)),
      const ElementFinder.type(Text).at(2),
      const ElementFinder.type(Text).first,
      const ElementFinder.type(Text).last,
      const ElementFinder.descendant(
        of: ElementFinder.type(Box<int>),
        matching: ElementFinder.type(Text),
      ),
      const ElementFinder.ancestor(
        of: ElementFinder.text('one'),
        matching: ElementFinder.type(Box<String>),
      ),
    ]) {
      final back = ElementFinder.fromJson(finder.toJson());
      expect(back.evaluate(root), finder.evaluate(root), reason: '$finder');
    }
    final node = ElementFinder.fromJson({'node': 7}, nodeOf: (id) => three);
    expect(node.evaluate(root), [three]);
    final gone = ElementFinder.fromJson({'node': 8}, nodeOf: (id) => null);
    expect(() => gone.evaluate(root), throwsStateError);
    expect(
      () => ElementFinder.fromJson({'node': 7}),
      throwsFormatException,
      reason: 'with nothing to name it',
    );
  });

  testTwk('over the wire a type is its name, which two libraries share; in '
      'process it stays a Type', (t) async {
    await t.pumpWidget(tree, size: (20, 8));
    final root = find.byType(Column).evaluate().single;
    expect(const ElementFinder.type(a.Tile).evaluate(root), hasLength(1));
    expect(const ElementFinder.type(b.Tile).evaluate(root), hasLength(1));
    final byName = ElementFinder.fromJson({'type': 'Tile'});
    expect(byName.evaluate(root), hasLength(2));
    expect(const ElementFinder.type(a.Tile).toJson(), {'type': 'Tile'});
  });

  test('what cannot cross the wire is an UnsupportedError that says what', () {
    expect(
      () => ElementFinder.key(UniqueKey()).toJson(),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('ValueKey'),
        ),
      ),
    );
    expect(
      () => ElementFinder.textMatches(RegExp('a', dotAll: true)).toJson(),
      throwsUnsupportedError,
    );
    expect(
      () => const ElementFinder.key(ValueKey<List<int>>([1])).toJson(),
      throwsUnsupportedError,
    );
  });

  test('JSON that is none of the kinds is a FormatException', () {
    for (final bad in <Object?>[
      null,
      3,
      [1],
      <String, Object?>{},
      {'wat': 1},
      {'text': 1},
      {'textMatches': 'x'},
      {
        'textMatches': {'caseSensitive': true},
      },
      {
        'key': {'value': 1.5},
      },
      {
        'at': 'x',
        'of': {'text': 'a'},
      },
      {
        'at': 1,
        'of': {'wat': 2},
      },
      {
        'descendant': {'text': 'a'},
      },
      {'text': 'a', 'type': 'b'},
    ]) {
      expect(
        () => ElementFinder.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  group('shown', () {
    testTwk('is the cells of the render object the ancestors do not cut '
        'off, null where none shows', (t) async {
      await t.pumpWidget(
        const Stack(
          children: [
            Positioned(left: 9, width: 14, child: Text('a long label')),
            Positioned(top: 5, height: 1, child: Text('below')),
            Positioned(top: 1, child: Text('inside')),
          ],
        ),
        size: (12, 3),
      );
      RenderObject render(String text) =>
          t.renderObject<RenderObject>(find.text(text));
      expect(shown(render('a long label')), (
        x: 9,
        y: 0,
        width: 3,
        height: 1,
      ));
      expect(shown(render('below')), isNull);
      expect(shown(render('inside')), (x: 0, y: 1, width: 6, height: 1));
    });

    testTwk('is null for a render object that left the tree', (t) async {
      await t.pumpWidget(const Text('x'), size: (5, 1));
      final o = t.renderObject<RenderObject>(find.text('x'));
      expect(shown(o), isNotNull);
      await t.pumpWidget(const SizedBox(), size: (5, 1));
      expect(shown(o), isNull);
    });
  });
}
