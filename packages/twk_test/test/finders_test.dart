// Finders: the widgets of the app a test looks for, what the tester reads
// of them, where they are on the screen, and clicks on them.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show RenderParagraph;
import 'package:twk_test/twk_test.dart';

/// A label and how many times it was pressed, kept with where.
final class Tile extends StatefulWidget {
  const Tile(this.label, {super.key});

  final String label;

  @override
  State<Tile> createState() => TileState();
}

final class TileState extends State<Tile> {
  /// The cells of the screen it was pressed at.
  final pressedAt = <(int, int)>[];

  @override
  Widget build(BuildContext context) => Listener(
    onDown: (e) => setState(() => pressedAt.add((e.screenX, e.screenY))),
    child: Text('${widget.label} ${pressedAt.length}'),
  );
}

/// A title, two tiles, the second keyed and padded, and rich text, from
/// column 2 of row 1 down.
final class Menu extends StatelessWidget {
  const Menu({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(left: 2, top: 1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Menu'),
        Tile('Open'),
        Padding(
          padding: EdgeInsets.only(left: 1),
          child: Tile('Save', key: Key('save')),
        ),
        Text.rich([Span('Qu'), Span('it')]),
      ],
    ),
  );
}

/// The labels of the tiles [finder] finds.
List<String> labels(Finder finder) => [
  for (final e in finder.evaluate()) (e.widget as Tile).label,
];

/// The lines of the message [matcher] fails with on [actual], without the
/// blanks that end them.
List<String> failure(Object? actual, Matcher matcher) {
  try {
    expect(actual, matcher);
  } on TestFailure catch (e) {
    return [for (final line in e.message!.split('\n')) line.trimRight()];
  }
  fail('it matched');
}

void main() {
  testTwk('find.byType finds the widgets of exactly the type in the app, '
      'the widget pumped down, in the order of the tree', (t) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    expect(find.byType(Menu), findsOneWidget);
    expect(find.byType(Menu).evaluate().single.widget, isA<Menu>());
    expect(labels(find.byType(Tile)), ['Open', 'Save']);
    expect(find.byType(Text), findsNWidgets(4));
    expect(find.byType(Padding), findsNWidgets(2));
    expect(find.byType(StatefulWidget), findsNothing, reason: 'exact type');
    expect(
      find.byType(FocusScope),
      findsNothing,
      reason: "the binding's widgets above the app are not the app's",
    );
  });

  testTwk('find.byKey finds the widgets with the key', (t) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    expect(labels(find.byKey(const Key('save'))), ['Save']);
    expect(find.byKey(const Key('open')), findsNothing);
  });

  testTwk('find.text finds the Texts that show the text, a rich one by its '
      'spans joined', (t) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('Open 0'), findsOneWidget);
    expect(find.text('Quit'), findsOneWidget);
    expect(find.text('Qu'), findsNothing);
    expect(find.text('Open'), findsNothing);
    expect(t.widget<Text>(find.text('Quit')).spans, hasLength(2));
  });

  testTwk('find.byWidgetPredicate finds the widgets the predicate takes', (
    t,
  ) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    final saves = find.byWidgetPredicate(
      (w) => w is Tile && w.label.startsWith('S'),
      description: 'tiles of S',
    );
    expect(labels(saves), ['Save']);
    expect(saves.description, 'tiles of S');
  });

  testTwk('find.descendant finds what matches below what is found, not it', (
    t,
  ) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    final save = find.byKey(const Key('save'));
    final texts = find.descendant(of: save, matching: find.byType(Text));
    expect(t.widget<Text>(texts).data, 'Save 0');
    expect(
      find.descendant(of: find.byType(Tile), matching: find.byType(Text)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: save, matching: find.byType(Tile)),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(Padding), matching: find.byType(Tile)),
      findsNWidgets(2),
      reason: 'each once, below both paddings',
    );
  });

  testTwk('find.ancestor finds what matches above what is found, the '
      'nearest first', (t) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    final paddings = find.ancestor(
      of: find.text('Save 0'),
      matching: find.byType(Padding),
    );
    expect(
      [for (final e in paddings.evaluate()) e.widget],
      [
        isA<Padding>().having((p) => p.padding.left, 'left', 1),
        isA<Padding>().having((p) => p.padding.left, 'left', 2),
      ],
    );
    expect(
      find.ancestor(of: find.text('Menu'), matching: find.byType(Tile)),
      findsNothing,
    );
    expect(
      find.ancestor(of: find.byType(Menu), matching: find.byType(FocusScope)),
      findsNothing,
      reason: 'the app is where the search stops',
    );
  });

  testTwk('first, last and at pick one of what a finder finds', (t) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    final tiles = find.byType(Tile);
    expect(labels(tiles.first), ['Open']);
    expect(labels(tiles.last), ['Save']);
    expect(labels(tiles.at(1)), ['Save']);
    expect(tiles.at(2), findsNothing);
    expect(find.text('none').first, findsNothing);
    expect(tiles.first.description, 'the first of type Tile');
    expect(tiles.at(1).description, 'type Tile at 1');
  });

  testTwk('a finder evaluated after the app ended finds nothing', (t) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    await t.quit();
    expect(find.byType(Menu), findsNothing);
  });

  testTwk('the count matchers say what was found, where, and show the '
      "app's widget tree", (t) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    expect(find.byType(Tile), findsWidgets);
    expect(find.byType(Tile), isNot(findsOneWidget));
    expect(find.text('x'), isNot(findsWidgets));
    final found = failure(find.byType(Tile), findsOneWidget);
    expect(found.take(5), [
      'Expected: finds one widget',
      '  Actual: _WidgetFinder:<type Tile>',
      '   Which: finds 2:',
      '            Tile at (2, 2), 6×1',
      "            Tile-[<'save'>] at (3, 3), 6×1",
    ]);
    expect(found[5], '');
    expect(found[6], '          widget tree:');
    expect(found[7], startsWith('          Menu '));
    expect(
      found,
      contains(startsWith('                ├─ Padding ‹padding: 0 0 0 1› ')),
    );
    final none = failure(find.text('x'), findsNWidgets(2));
    expect(none.take(4), [
      'Expected: finds 2 widgets',
      '  Actual: _WidgetFinder:<text "x">',
      '   Which: finds none',
      '',
    ]);
    expect(
      failure(find.text('x'), findsWidgets).first,
      startsWith('Expected: finds a widget or more'),
    );
    expect(
      failure(find.byType(Tile), findsNothing).first,
      startsWith('Expected: finds no widget'),
    );
    expect(
      failure(3, findsNothing),
      contains('   Which: is not a Finder'),
    );
  });

  testTwk('the tester reads the element, widget, state and render object of '
      'the one widget a finder finds', (t) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    final save = find.byKey(const Key('save'));
    expect(t.element(save).widget, isA<Tile>());
    expect(t.widget<Tile>(save).label, 'Save');
    expect(t.state<TileState>(save).pressedAt, isEmpty);
    expect(
      t.renderObject<RenderParagraph>(find.text('Quit')).width,
      4,
    );
    expect(
      t.renderObject(save),
      same(
        t.renderObject(
          find.descendant(of: save, matching: find.byType(Listener)),
        ),
      ),
      reason: 'that of the nearest below with one',
    );
  });

  testTwk('the tester takes exactly one widget, of the type asked for', (
    t,
  ) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    expect(
      () => t.element(find.byType(Tile)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'type Tile finds 2 widgets, not one: '
              "Tile at (2, 2), 6×1; Tile-[<'save'>] at (3, 3), 6×1",
        ),
      ),
    );
    expect(
      () => t.widget<Tile>(find.text('x')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'text "x" finds no widget',
        ),
      ),
    );
    expect(
      () => t.widget<Tile>(find.text('Menu')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'text "Menu" finds a Text, not a Tile',
        ),
      ),
    );
    expect(
      () => t.state<TileState>(find.text('Menu')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'text "Menu" finds a Text, which has no state',
        ),
      ),
    );
    expect(
      () => t.state<State<FocusScope>>(find.byType(Tile).first),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'the first of type Tile finds a Tile, whose state is a TileState',
        ),
      ),
    );
    expect(
      () => t.renderObject<RenderParagraph>(find.byType(Menu)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          startsWith('type Menu finds a Menu, whose render object is a '),
        ),
      ),
    );
  });

  testTwk('rect gives the cells of the widget on the screen, its render '
      "object's or that of the nearest below", (t) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    expect(t.rect(find.byType(Menu)), (x: 0, y: 0, width: 20, height: 6));
    expect(t.rect(find.text('Menu')), (x: 2, y: 1, width: 4, height: 1));
    expect(
      t.rect(find.byKey(const Key('save'))),
      (x: 3, y: 3, width: 6, height: 1),
    );
    expect(t.rect(find.text('Quit')), (x: 2, y: 4, width: 4, height: 1));
  });

  testTwk('clickOn clicks the cell in the middle of the widget', (t) async {
    await t.pumpWidget(const Menu(), size: (20, 6));
    await t.clickOn(find.byKey(const Key('save')));
    await t.clickOn(find.byType(Tile).first, button: 2);
    await t.pump();
    expect(t.state<TileState>(find.byType(Tile).at(1)).pressedAt, [(5, 3)]);
    expect(t.state<TileState>(find.byType(Tile).first).pressedAt, [(4, 2)]);
    expect(t, containsLine('   Save 1'));
  });

  testTwk('clickOn clicks the middle of the cells a widget shows, cut off by '
      'the render objects above it; none is a StateError', (t) async {
    // the first tile sticks out of the stack; the second is past the screen
    await t.pumpWidget(
      const Stack(
        children: [
          Positioned(left: 9, width: 14, child: Tile('a long label')),
          Positioned(top: 5, height: 1, child: Tile('below')),
        ],
      ),
      size: (12, 3),
    );
    final tile = find.byType(Tile).first;
    expect(t.rect(tile), (x: 9, y: 0, width: 14, height: 1));
    await t.clickOn(tile);
    expect(t.state<TileState>(tile).pressedAt, [(10, 0)]);
    final below = find.byType(Tile).last;
    expect(t.rect(below), (x: 0, y: 5, width: 7, height: 1));
    expect(
      () => t.clickOn(below),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'the last of type Tile finds Tile at (0, 5), 7×1, which shows no '
              'cell',
        ),
      ),
    );
  });

  testTwk('rect and clickOn are a StateError on a widget not laid out yet, '
      'though it has a render object', (t) async {
    final items = ValueNotifier<List<int>>([]);
    await t.pumpWidget(
      ListenableBuilder(
        listenable: items,
        builder: (_, _) => Static(
          items: items.value,
          builder: (_, i) => Text('line $i'),
        ),
      ),
      mode: ScreenMode.inline,
    );
    // a frame commits 256 rows: the rest of the items wait for the next,
    // a frame gap later
    items.value = [for (var i = 0; i < 300; i++) i];
    await t.pump(Duration.zero);
    final waiting = find.text('line 299');
    expect(t.renderObject<RenderParagraph>(waiting).constraints, isNull);
    final message = startsWith('text "line 299" finds Text');
    expect(
      () => t.rect(waiting),
      throwsA(
        isA<StateError>()
            .having((e) => e.message, 'message', message)
            .having((e) => e.message, 'message', endsWith('not laid out')),
      ),
    );
    expect(
      () => t.clickOn(waiting),
      throwsA(
        isA<StateError>()
            .having((e) => e.message, 'message', message)
            .having((e) => e.message, 'message', endsWith('not laid out')),
      ),
    );
    await t.pump();
    expect(find.text('line 299'), findsNothing);
    expect(t.vt.lines, contains('line 299'));
  });

  test('a finder is evaluated in testTwk only', () {
    expect(
      () => find.byType(Menu).evaluate(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'a finder finds the widgets of the app of a testTwk',
        ),
      ),
    );
  });

  testTwk('a finder before pumpWidget is a StateError', (t) {
    expect(() => find.byType(Menu).evaluate(), throwsStateError);
  });
}
