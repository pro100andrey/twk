// The binding's service extensions, called directly: the trees as JSON
// with ids that last, a node's properties and layout, the node at a cell,
// the outline over a node and the debug flags, and the cell a click picks
// for the tool; registered once in the isolate, for the app that started
// last, and not at all in product mode.
// One test calls them over a real VM service, in a process of its own.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' show ServiceExtensionHandler, ServiceExtensionResponse;
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// What [method] answers with [parameters] in [t]'s app, as JSON; a
/// [TestFailure] for an error.
Future<Map<String, Object?>> call(
  TwkTester t,
  String method, [
  Map<String, String> parameters = const {},
]) async {
  final response = await t.binding.callServiceExtension(method, parameters);
  if (response.isError()) {
    fail('$method: ${response.errorCode} ${response.errorDetail}');
  }
  return jsonDecode(response.result!) as Map<String, Object?>;
}

/// The error code and message [method] answers with in [t]'s app.
Future<(int, String)> error(
  TwkTester t,
  String method, [
  Map<String, String> parameters = const {},
]) async {
  final response = await t.binding.callServiceExtension(method, parameters);
  expect(response.isError(), isTrue, reason: '$method answered');
  final detail = jsonDecode(response.errorDetail!) as Map<String, Object?>;
  return (response.errorCode!, detail['message']! as String);
}

typedef Json = Map<String, Object?>;

/// The nodes of the tree [node] is the root of, root first.
List<Json> nodesOf(Json node) => [
  node,
  for (final child in node['children']! as List<Object?>)
    ...nodesOf(child! as Json),
];

/// The first node of [tree] named [name].
Json named(Json tree, String name) =>
    nodesOf(tree['root']! as Json).firstWhere((n) => n['name'] == name);

/// The ids of the nodes of [tree].
List<int> idsOf(Json tree) => [
  for (final n in nodesOf(tree['root']! as Json)) n['id']! as int,
];

/// Two rows of text inside a padding, the second its own repaint boundary
/// showing [count].
Widget app({int left = 2, int count = 0, bool second = true}) => Padding(
  padding: EdgeInsets.only(left: left, top: 1),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('header', key: Key('header')),
      if (second) Line('count $count'),
    ],
  ),
);

void main() {
  // inspected_app.dart, compiled once as it is and once in product mode,
  // which is a constant of the compile
  late String inspected;
  late String inspectedInProduct;
  setUpAll(() async {
    final packages = (await Isolate.packageConfig)!.toFilePath();
    const cache = '.dart_tool/twk_test/programs';
    inspected = await compiledProgram(
      'test/binding/inspected_app.dart',
      packages: packages,
      cache: cache,
    );
    inspectedInProduct = await compiledProgram(
      'test/binding/inspected_app.dart',
      packages: packages,
      cache: cache,
      defines: {'dart.vm.product': 'true'},
    );
  });

  group('ext.twk.tree', () {
    testTwk('names the type whose build makes the child of the element of a '
        'stateless or a stateful widget: the widget, or its state', (t) async {
      final count = GlobalKey<_CountState>();
      await t.pumpWidget(_Count(key: count), size: (20, 3));
      count.currentState!.toggle();
      await t.pump();
      final tree = await call(t, 'ext.twk.tree');
      expect(named(tree, '_Count')['build'], '_CountState');
      expect(named(tree, '_Bracketed')['build'], '_Bracketed');
      expect(named(tree, 'Text'), isNot(contains('build')));
      final bracketed = named(tree, '_Bracketed');
      expect(
        (await call(t, 'ext.twk.properties', {
          'id': '${bracketed['id']}',
        }))['build'],
        '_Bracketed',
      );
    });

    testTwk('describes the element tree from its root, the app in it, each '
        'node with an id', (t) async {
      await t.pumpWidget(app(), size: (20, 5));
      final tree = await call(t, 'ext.twk.tree');
      expect(tree['version'], 1);
      expect(tree['tree'], 'element');
      final root = tree['root']! as Json;
      expect(root['name'], 'RootWidget');
      expect(
        nodesOf(root).firstWhere((n) => n['id'] == tree['app'])['name'],
        'Padding',
      );
      final text = named(tree, 'Text');
      expect(text['key'], "[<'header'>]");
      expect(text['size'], {'width': 6, 'height': 1});
      expect(text['properties'], [
        {'value': '"header"'},
      ]);
      expect(text['children'], isEmpty);
      expect(text['render'], isA<int>());
      expect(named(tree, 'Line')['flags'], contains('repaintBoundary'));
      final ids = idsOf(tree);
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.every((id) => id > 0), isTrue);
    });

    testTwk('keeps an element its id through rebuilds while it is mounted, '
        'and never gives one twice', (t) async {
      await t.pumpWidget(app(), size: (20, 5));
      final before = await call(t, 'ext.twk.tree');
      await t.pumpWidget(app(count: 1), size: (20, 5));
      final after = await call(t, 'ext.twk.tree');
      expect(idsOf(after), idsOf(before));
      expect(named(after, 'Line')['id'], named(before, 'Line')['id']);
      await t.pumpWidget(app(second: false), size: (20, 5));
      await t.pumpWidget(app(), size: (20, 5));
      final again = await call(t, 'ext.twk.tree');
      final line = named(again, 'Line')['id']! as int;
      expect(line, isNot(named(before, 'Line')['id']));
      expect(line, greaterThan(idsOf(before).reduce((a, b) => a > b ? a : b)));
      expect(named(again, 'Text')['id'], named(before, 'Text')['id']);
    });

    testTwk('with tree=render describes the render tree, each object with '
        'the id of its element', (t) async {
      await t.pumpWidget(app(), size: (20, 5));
      final elements = await call(t, 'ext.twk.tree');
      final tree = await call(t, 'ext.twk.tree', {'tree': 'render'});
      expect(tree['tree'], 'render');
      expect(tree.containsKey('app'), isFalse);
      final root = tree['root']! as Json;
      expect(root['name'], '_RenderView');
      final text = named(elements, 'Text');
      final paragraph = nodesOf(root).firstWhere(
        (n) => n['id'] == text['render'],
      );
      expect(paragraph['element'], text['id']);
      expect(paragraph['size'], {'width': 6, 'height': 1});
      expect(root.containsKey('element'), isTrue);
      final (code, message) = await error(t, 'ext.twk.tree', {'tree': 'x'});
      expect(code, ServiceExtensionResponse.invalidParams);
      expect(message, 'tree: element or render, not x');
    });

    testTwk('has no root before the first frame', (t) async {
      final binding = AppBinding(HeadlessTerminal());
      final response = await binding.callServiceExtension('ext.twk.tree', {});
      expect(jsonDecode(response.result!), {
        'version': 1,
        'tree': 'element',
        'app': null,
        'root': null,
      });
    });
  });

  group('ext.twk.properties and ext.twk.layout', () {
    testTwk('give a node as the tree has it, without its children', (t) async {
      await t.pumpWidget(app(), size: (20, 5));
      final tree = await call(t, 'ext.twk.tree');
      final column = named(tree, 'Column');
      final id = '${column['id']}';
      final properties = await call(t, 'ext.twk.properties', {'id': id});
      expect(properties, {
        'version': 1,
        ...column..remove('children'),
      });
    });

    testTwk('give a render object as the render tree has it, with the id '
        'of its element, without its children', (t) async {
      await t.pumpWidget(app(), size: (20, 5));
      final tree = await call(t, 'ext.twk.tree', {'tree': 'render'});
      final paragraph = named(tree, 'RenderParagraph');
      final properties = await call(t, 'ext.twk.properties', {
        'id': '${paragraph['id']}',
      });
      expect(properties['element'], isA<int>());
      expect(properties, {
        'version': 1,
        ...paragraph..remove('children'),
      });
    });

    testTwk("give the layout of an element's render object: constraints, "
        'size, offset in its parent and on the screen', (t) async {
      await t.pumpWidget(app(left: 3), size: (20, 5));
      final tree = await call(t, 'ext.twk.tree');
      final text = named(tree, 'Text');
      final layout = await call(t, 'ext.twk.layout', {'id': '${text['id']}'});
      expect(layout, {
        'version': 1,
        'id': text['id'],
        'render': text['render'],
        'name': 'RenderParagraph',
        'constraints': {
          'minWidth': 0,
          'maxWidth': 17,
          'minHeight': 0,
          'maxHeight': 4,
        },
        'size': {'width': 6, 'height': 1},
        'offset': {'x': 0, 'y': 0},
        'global': {'x': 3, 'y': 1},
      });
      final line = named(tree, 'Line');
      final render = await call(t, 'ext.twk.layout', {
        'id': '${line['render']}',
      });
      expect(render['id'], line['render']);
      expect(render['offset'], {'x': 0, 'y': 1});
      expect(render['global'], {'x': 3, 'y': 2});
    });

    testTwk('answer an id missing, malformed or naming no node with an '
        'error', (t) async {
      await t.pumpWidget(app(), size: (20, 5));
      final tree = await call(t, 'ext.twk.tree');
      final line = '${named(tree, 'Line')['id']}';
      await t.pumpWidget(app(second: false), size: (20, 5));
      for (final method in ['ext.twk.properties', 'ext.twk.layout']) {
        expect(await error(t, method), (
          ServiceExtensionResponse.invalidParams,
          'no id',
        ));
        expect(await error(t, method, {'id': 'x'}), (
          ServiceExtensionResponse.invalidParams,
          'id: an int, not x',
        ));
        expect(await error(t, method, {'id': '9999'}), (
          ServiceExtensionResponse.extensionError,
          'no node 9999 in the app',
        ));
        expect(await error(t, method, {'id': line}), (
          ServiceExtensionResponse.extensionError,
          'no node $line in the app',
        ));
      }
    });
  });

  group('ext.twk.select', () {
    testTwk('gives the deepest element at a cell, the path to it and the '
        'render objects hit', (t) async {
      await t.pumpWidget(app(), size: (20, 5));
      final tree = await call(t, 'ext.twk.tree');
      final text = named(tree, 'Text');
      final at = await call(t, 'ext.twk.select', {'x': '4', 'y': '1'});
      expect(at['id'], text['id']);
      final path = at['path']! as List<Object?>;
      expect(path.first, (tree['root']! as Json)['id']);
      expect(path.last, text['id']);
      expect(path, contains(tree['app']));
      final render = at['render']! as List<Object?>;
      expect(render.first, text['render']);
      final view = await call(t, 'ext.twk.tree', {'tree': 'render'});
      expect(render.last, (view['root']! as Json)['id']);
    });

    testTwk('gives no element where nothing is hit', (t) async {
      await t.pumpWidget(app(), size: (20, 5));
      final at = await call(t, 'ext.twk.select', {'x': '15', 'y': '1'});
      expect(at, {
        'version': 1,
        'id': null,
        'path': <Object?>[],
        'render': <Object?>[],
      });
      expect(await error(t, 'ext.twk.select', {'x': '1'}), (
        ServiceExtensionResponse.invalidParams,
        'no y',
      ));
    });

    testTwk("takes a row of the terminal's screen by the cursor's row on it, "
        'where the inline region is on it', (t) async {
      await t.pumpWidget(app(), size: (20, 5), mode: ScreenMode.inline);
      final text = named(await call(t, 'ext.twk.tree'), 'Text')['id'];
      // the region's row 1 shows the header; the cursor is on its row
      // `cursorRow`, which the tool sees on the screen's row 10
      final cursor = t.binding.twkApp.screen.presenter.cursorRow;
      expect(cursor, isNonNegative);
      final at = await call(t, 'ext.twk.select', {
        'x': '4',
        'y': '${10 - cursor + 1}',
        'cursorY': '10',
      });
      expect(at['id'], text);
      expect(
        (await call(t, 'ext.twk.select', {
          'x': '4',
          'y': '1',
          'cursorY': '$cursor',
        }))['id'],
        text,
      );
      expect(
        await error(t, 'ext.twk.select', {
          'x': '4',
          'y': '1',
          'cursorY': 'top',
        }),
        (ServiceExtensionResponse.invalidParams, 'cursorY: an int, not top'),
      );
    });
  });

  group('ext.twk.highlight', () {
    /// The backgrounds of row [y] from column [from] to [to].
    List<int> bgs(TwkTester t, int y, int from, int to) => [
      for (var x = from; x < to; x++) t.cell(x, y).bg,
    ];

    testTwk('outlines a node over the app, its glyphs kept, until another '
        'call', (t) async {
      await t.pumpWidget(
        Padding(
          padding: const EdgeInsets.only(left: 1, top: 1),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 5,
              height: 3,
              child: Column(
                children: [
                  for (final s in ['abcde', 'fghij', 'klmno']) Text(s),
                ],
              ),
            ),
          ),
        ),
        size: (8, 5),
        backgroundRgb: 0x000000,
      );
      final tree = await call(t, 'ext.twk.tree');
      final box = named(tree, 'SizedBox');
      final shown = await call(t, 'ext.twk.highlight', {
        'id': '${box['id']}',
      });
      expect(shown, {'version': 1, 'id': box['id'], 'render': box['render']});
      expect(t.binding.debug.highlight, isNotNull);
      await t.pump();
      expect(t.lines, ['', ' abcde', ' fghij', ' klmno', '']);
      final top = bgs(t, 1, 1, 6);
      final middle = bgs(t, 2, 1, 6);
      final edge = top.first;
      expect(edge, isNot(0));
      expect(top, everyElement(edge));
      expect(bgs(t, 3, 1, 6), everyElement(edge));
      final inside = middle[1];
      expect(inside, isNot(0));
      expect(inside, isNot(edge));
      expect(middle, [edge, inside, inside, inside, edge]);
      // the cells around it are left as they are
      expect(bgs(t, 0, 0, 8), everyElement(0));
      expect(bgs(t, 4, 0, 8), everyElement(0));
      expect([for (var y = 0; y < 5; y++) t.cell(0, y).bg], everyElement(0));
      expect([for (var y = 0; y < 5; y++) t.cell(6, y).bg], everyElement(0));

      final text = nodesOf(box).firstWhere((n) => n['name'] == 'Text');
      await call(t, 'ext.twk.highlight', {'id': '${text['id']}'});
      await t.pump();
      expect(bgs(t, 1, 1, 6), everyElement(edge));
      expect(bgs(t, 2, 1, 6), everyElement(0));
      expect(bgs(t, 3, 1, 6), everyElement(0));

      final cleared = await call(t, 'ext.twk.highlight');
      expect(cleared, {'version': 1, 'id': null});
      expect(t.binding.debug.highlight, isNull);
      await t.pump();
      for (var y = 0; y < 5; y++) {
        expect(bgs(t, y, 0, 8), everyElement(0));
      }
    });

    testTwk('follows its node as it moves, outlines it once over a repaint '
        'under it, and goes when the node leaves the tree', (t) async {
      await t.pumpWidget(app(), size: (20, 5), backgroundRgb: 0x000000);
      final tree = await call(t, 'ext.twk.tree');
      await call(t, 'ext.twk.highlight', {
        'id': '${named(tree, 'Line')['id']}',
      });
      await t.pump();
      // the line is as wide as its text and two more
      final edge = t.cell(2, 2).bg;
      expect(edge, isNot(0));
      expect(bgs(t, 2, 2, 11), everyElement(edge));
      expect(bgs(t, 2, 11, 20), everyElement(0));

      // the line repaints on its own: outlined again, not twice
      await t.pumpWidget(app(count: 1), size: (20, 5));
      expect(t.lines[2], '  count 1');
      expect(bgs(t, 2, 2, 11), everyElement(edge));
      expect(bgs(t, 1, 0, 20), everyElement(0));

      await t.pumpWidget(app(left: 4, count: 1), size: (20, 5));
      expect(t.lines[2], '    count 1');
      expect(bgs(t, 2, 0, 4), everyElement(0));
      expect(bgs(t, 2, 4, 13), everyElement(edge));
      expect(bgs(t, 2, 13, 20), everyElement(0));

      await t.pumpWidget(app(left: 4, second: false), size: (20, 5));
      expect(t.binding.debug.highlight, isNull);
      for (var y = 0; y < 5; y++) {
        expect(bgs(t, y, 0, 20), everyElement(0));
      }
    });

    testTwk('is cut off where an ancestor cuts its node off', (t) async {
      await t.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 4,
            height: 3,
            child: SingleChildScrollView(
              child: Column(
                children: [for (var i = 0; i < 6; i++) Text('row$i')],
              ),
            ),
          ),
        ),
        size: (6, 4),
        backgroundRgb: 0x000000,
      );
      final tree = await call(t, 'ext.twk.tree');
      final column = named(tree, 'Column');
      final layout = await call(t, 'ext.twk.layout', {
        'id': '${column['id']}',
      });
      expect(layout['size'], {'width': 4, 'height': 6});
      // as tall as it likes
      expect(layout['constraints'], {
        'minWidth': 4,
        'maxWidth': 4,
        'minHeight': 0,
        'maxHeight': null,
      });
      await call(t, 'ext.twk.highlight', {'id': '${column['id']}'});
      await t.pump();
      expect(t.lines.take(3), ['row0', 'row1', 'row2']);
      final edge = t.cell(0, 0).bg;
      expect(bgs(t, 0, 0, 4), everyElement(edge));
      // no bottom edge: it is cut off
      final inside = t.cell(1, 2).bg;
      expect(inside, allOf(isNot(0), isNot(edge)));
      expect(bgs(t, 2, 0, 4), [edge, inside, inside, edge]);
      expect(bgs(t, 3, 0, 6), everyElement(0));
      expect([t.cell(4, 1).bg, t.cell(5, 1).bg], [0, 0]);
    });

    testTwk('tints a two-column glyph its edge cuts whole', (t) async {
      await t.pumpWidget(
        const Stack(
          children: [
            Text('漢字漢字'),
            Positioned(
              left: 1,
              top: 0,
              child: SizedBox(width: 2, height: 1),
            ),
          ],
        ),
        size: (8, 2),
        backgroundRgb: 0x000000,
      );
      final tree = await call(t, 'ext.twk.tree');
      final box = nodesOf(
        tree['root']! as Json,
      ).firstWhere((n) => n['name'] == 'SizedBox');
      await call(t, 'ext.twk.highlight', {'id': '${box['id']}'});
      await t.pump();
      expect(t.lines.first, '漢字漢字');
      final edge = t.cell(1, 0).bg;
      expect(edge, isNot(0));
      // the glyphs at columns 0 and 2, which the outline over 1 and 2 cuts
      expect(bgs(t, 0, 0, 4), everyElement(edge));
      expect(bgs(t, 0, 4, 8), everyElement(0));
    });
  });

  group('ext.twk.flags', () {
    testTwk('gives the debug aids, and sets those passed', (t) async {
      await t.pumpWidget(app(), size: (40, 20));
      final off = {
        'version': 1,
        'overlay': false,
        'console': false,
        'rainbow': false,
        'relayout': false,
        'keys': false,
        'select': false,
        'selectMany': false,
        'treeEvents': false,
        'framesInRow': false,
      };
      expect(await call(t, 'ext.twk.flags'), off);
      final on = await call(t, 'ext.twk.flags', {
        'overlay': 'true',
        'console': 'true',
        'rainbow': 'true',
        'relayout': 'true',
        'keys': 'true',
        'treeEvents': 'true',
        'isolateId': 'isolates/1',
      });
      expect(on, {
        'version': 1,
        'overlay': true,
        'console': true,
        'rainbow': true,
        'relayout': true,
        'keys': true,
        'select': false,
        'selectMany': false,
        'treeEvents': true,
        'framesInRow': false,
      });
      final debug = t.binding.debug;
      expect(debug.overlay, isTrue);
      expect(debug.console.isOpen, isTrue);
      expect(t.binding.twkApp.owner.debugRepaintRainbow, isTrue);
      expect(t.binding.twkApp.owner.debugRelayoutHighlight, isTrue);
      expect(debug.keys, isTrue);
      expect(debug.treeEvents, isTrue);
      expect(
        await call(t, 'ext.twk.flags', {
          'overlay': 'false',
          'console': 'false',
          'rainbow': 'false',
          'relayout': 'false',
          'keys': 'false',
          'treeEvents': 'false',
        }),
        off,
      );
    });

    testTwk('sets none when a value is not true or false, and not the '
        'frames in a row', (t) async {
      await t.pumpWidget(app(), size: (20, 5));
      expect(
        await error(t, 'ext.twk.flags', {'rainbow': 'true', 'keys': 'on'}),
        (ServiceExtensionResponse.invalidParams, 'keys: true or false, not on'),
      );
      expect(t.binding.debug.rainbow, isFalse);
      expect(await error(t, 'ext.twk.flags', {'framesInRow': 'true'}), (
        ServiceExtensionResponse.invalidParams,
        'framesInRow: the app is built so',
      ));
      expect(
        t.binding.callServiceExtension('ext.twk.nothing', {}),
        throwsArgumentError,
      );
    });
  });

  group('ext.twk.flags select', () {
    late List<List<Object?>> posted;
    setUp(() {
      posted = [];
      final post = AppBinding.postEvent;
      AppBinding.postEvent = (kind, [data = const {}]) {
        posted.add([kind, data]);
        return true;
      };
      addTearDown(() => AppBinding.postEvent = post);
    });

    /// What the app wrote to the terminal since frame [from].
    String writtenSince(TwkTester t, int from) => [
      for (final f in t.terminal.frames.skip(from)) latin1.decode(f),
    ].join();

    /// The render object of the widget of type [type].
    RenderObject? renderOf(Type type) =>
        find.byType(type).evaluate().single.renderObject;

    testTwk('picks the cell of the next press of the left button for the '
        'tool, outlining the node under the mouse until then; the app gets '
        'neither, and the mouse is reported only while it picks', (t) async {
      await t.pumpWidget(app(), size: (20, 5));
      final line = renderOf(Line);
      final text = renderOf(Text);
      expect(line, isNotNull);
      expect(writtenSince(t, 0), isNot(contains('\x1b[?1003h')));

      var from = t.terminal.frames.length;
      final armed = await call(t, 'ext.twk.flags', {'select': 'true'});
      expect(armed['select'], isTrue);
      expect(t.binding.debug.select, isTrue);
      expect(writtenSince(t, from), '\x1b[?1003h\x1b[?1006h');

      await t.mouse(MouseKind.move, 3, 2);
      expect(t.binding.debug.highlight, same(line));
      await t.mouse(MouseKind.move, 4, 1);
      expect(t.binding.debug.highlight, same(text));
      // another button picks nothing
      await t.click(4, 1, button: 2);
      expect(posted, isEmpty);

      from = t.terminal.frames.length;
      await t.mouse(MouseKind.down, 3, 2);
      expect(posted, [
        [
          'twk.select',
          {'version': 1, 'x': 3, 'y': 2},
        ],
      ]);
      expect(t.binding.debug.select, isFalse);
      expect((await call(t, 'ext.twk.flags'))['select'], isFalse);
      expect(t.binding.debug.highlight, isNull);
      expect(writtenSince(t, from), '\x1b[?1003l\x1b[?1006l');
      await t.mouse(MouseKind.up, 3, 2);
      expect(posted, hasLength(1));
    });

    testTwk('withholds the press it picks with and its release from the '
        "app's listeners, which get the mouse again after", (t) async {
      final got = <String>[];
      await t.pumpWidget(
        Listener(
          onDown: (_) => got.add('down'),
          onUp: (_) => got.add('up'),
          child: app(),
        ),
        size: (20, 5),
      );
      var from = t.terminal.frames.length;
      await call(t, 'ext.twk.flags', {'select': 'true'});
      expect(writtenSince(t, from), '\x1b[?1000l\x1b[?1003h');
      await t.click(4, 2, button: 1);
      from = t.terminal.frames.length;
      await t.mouse(MouseKind.down, 4, 2);
      expect(writtenSince(t, from), '\x1b[?1003l\x1b[?1000h');
      await t.mouse(MouseKind.drag, 5, 2);
      await t.mouse(MouseKind.up, 5, 2);
      expect(got, isEmpty);
      expect(posted, [
        [
          'twk.select',
          {'version': 1, 'x': 4, 'y': 2},
        ],
      ]);

      await t.click(4, 2);
      expect(got, ['down', 'up']);

      // a release the terminal did not report keeps no press from the app
      await call(t, 'ext.twk.flags', {'select': 'true'});
      await t.mouse(MouseKind.down, 4, 2);
      await t.click(4, 2);
      expect(got, ['down', 'up', 'down', 'up']);
      expect(posted, hasLength(2));
    });

    testTwk('Escape cancels it, telling the tool no cell, and the app does '
        'not get it; the outline before comes back', (t) async {
      final keys = <String>[];
      await t.pumpWidget(
        KeyBindings({'escape': () => keys.add('escape')}, child: app()),
        size: (20, 5),
      );
      final tree = await call(t, 'ext.twk.tree');
      await call(t, 'ext.twk.highlight', {
        'id': '${named(tree, 'Text')['id']}',
      });
      final before = t.binding.debug.highlight;
      expect(before, isNotNull);

      await call(t, 'ext.twk.flags', {'select': 'true'});
      await t.mouse(MouseKind.move, 3, 2);
      expect(t.binding.debug.highlight, isNot(same(before)));
      final from = t.terminal.frames.length;
      await t.press('escape');
      expect(posted, [
        [
          'twk.select',
          {'version': 1, 'x': null, 'y': null},
        ],
      ]);
      expect(keys, isEmpty);
      expect(t.binding.debug.select, isFalse);
      expect(t.binding.debug.highlight, same(before));
      // between the frames that move the outline
      expect(writtenSince(t, from), contains('\x1b[?1003l\x1b[?1006l'));

      await t.press('escape');
      expect(keys, ['escape']);
      expect(posted, hasLength(1));
    });

    testTwk('turned off by the tool, it tells the tool nothing', (t) async {
      await t.pumpWidget(app(), size: (20, 5));
      await call(t, 'ext.twk.flags', {'select': 'true'});
      await t.mouse(MouseKind.move, 3, 2);
      final from = t.terminal.frames.length;
      final off = await call(t, 'ext.twk.flags', {'select': 'false'});
      expect(off['select'], isFalse);
      expect(t.binding.debug.highlight, isNull);
      expect(writtenSince(t, from), '\x1b[?1003l\x1b[?1006l');
      await t.mouse(MouseKind.down, 3, 2);
      expect(posted, isEmpty);
      expect(
        await error(t, 'ext.twk.flags', {'select': 'yes'}),
        (
          ServiceExtensionResponse.invalidParams,
          'select: true or false, not yes',
        ),
      );
    });

    testTwk('picking many, goes on after a cell picked: each press posts its '
        'cell, the outline follows the mouse between them, and Escape ends '
        'it', (t) async {
      final got = <String>[];
      await t.pumpWidget(
        Listener(onDown: (_) => got.add('down'), child: app()),
        size: (20, 5),
      );
      final armed = await call(t, 'ext.twk.flags', {
        'select': 'true',
        'selectMany': 'true',
      });
      expect([armed['select'], armed['selectMany']], [true, true]);
      final picking = t.terminal.frames.length;
      await t.click(4, 1);
      await t.mouse(MouseKind.move, 3, 2);
      expect(t.binding.debug.highlight, same(renderOf(Line)));
      await t.click(3, 2);
      expect(posted, [
        [
          'twk.select',
          {'version': 1, 'x': 4, 'y': 1},
        ],
        [
          'twk.select',
          {'version': 1, 'x': 3, 'y': 2},
        ],
      ]);
      expect(t.binding.debug.select, isTrue);
      // the mouse reported all along
      expect(writtenSince(t, picking), isNot(contains('\x1b[?1003l')));
      // a press whose release was not reported picks too
      await t.mouse(MouseKind.down, 4, 1);
      await t.mouse(MouseKind.down, 3, 2);
      expect(posted, hasLength(4));
      // Escape while the press is held
      final from = t.terminal.frames.length;
      await t.press('escape');
      expect(posted.last, [
        'twk.select',
        {'version': 1, 'x': null, 'y': null},
      ]);
      expect(t.binding.debug.select, isFalse);
      expect(writtenSince(t, from), contains('\x1b[?1003l'));
      expect(got, isEmpty);
      // still picking many: the next pick goes on too, until set off
      await call(t, 'ext.twk.flags', {'select': 'true'});
      await t.click(4, 1);
      expect(t.binding.debug.select, isTrue);
      await call(t, 'ext.twk.flags', {'select': 'false'});
      await t.click(4, 1);
      expect(posted, hasLength(6));
      expect(got, ['down']);
    });

    testTwk('stays off in the inline mode, which gets no mouse reports', (
      t,
    ) async {
      await t.pumpWidget(app(), size: (20, 5), mode: ScreenMode.inline);
      final armed = await call(t, 'ext.twk.flags', {'select': 'true'});
      expect(armed['select'], isFalse);
      expect(t.binding.debug.select, isFalse);
    });
  });

  group('ext.twk.flags treeEvents', () {
    late List<List<Object?>> posted;
    setUp(() {
      posted = [];
      final post = AppBinding.postEvent;
      AppBinding.postEvent = (kind, [data = const {}]) {
        posted.add([kind, data]);
        return true;
      };
      addTearDown(() => AppBinding.postEvent = post);
    });

    testTwk('off by default: frames that build post nothing', (t) async {
      final count = GlobalKey<_CountState>();
      await t.pumpWidget(_Count(key: count), size: (20, 3));
      expect(t.binding.debug.treeEvents, isFalse);
      count.currentState!.add();
      await t.pump();
      expect(t.lines.first, startsWith('n 1'));
      expect(posted, isEmpty);
    });

    testTwk('on, posts twk.treeChanged once after each frame that built, '
        'with how many built; none for a frame that only painted, none once '
        'off again', (t) async {
      final count = GlobalKey<_CountState>();
      await t.pumpWidget(_Count(key: count), size: (20, 3));
      await call(t, 'ext.twk.flags', {'treeEvents': 'true'});
      expect(posted, isEmpty);

      // two changes before one frame: one event, the state built once
      count.currentState!
        ..add()
        ..add();
      await t.pump();
      expect(t.lines.first, startsWith('n 2'));
      expect(posted, [
        [
          'twk.treeChanged',
          {'version': 1, 'rebuilds': 1},
        ],
      ]);

      // a new child mounted, the old one gone: one more
      count.currentState!.toggle();
      await t.pump();
      expect(t.lines.first, startsWith('[n 2]'));
      expect(posted, hasLength(2));
      expect(posted.last.first, 'twk.treeChanged');

      // a frame of paint alone: the outline over a node
      final tree = await call(t, 'ext.twk.tree');
      await call(t, 'ext.twk.highlight', {
        'id': '${named(tree, 'Text')['id']}',
      });
      final frames = t.terminal.frames.length;
      await t.pump();
      expect(t.terminal.frames.length, greaterThan(frames));
      expect(posted, hasLength(2));

      await call(t, 'ext.twk.flags', {'treeEvents': 'false'});
      count.currentState!.add();
      await t.pump();
      expect(t.lines.first, startsWith('[n 3]'));
      expect(posted, hasLength(2));
    });
  });

  group('registration', () {
    test('registers nothing in product mode', () {
      final names = <String>[];
      AppBinding.registerServiceExtensions(
        product: true,
        register: (name, _) => names.add(name),
      );
      expect(names, isEmpty);
    });

    testTwk('registers each extension, which answers about the app that '
        'started last of those running', (t) async {
      final handlers = <String, ServiceExtensionHandler>{};
      final zones = <Zone>{};
      // not in product mode, as tests run
      AppBinding.registerServiceExtensions(
        register: (name, handler) {
          handlers[name] = handler;
          zones.add(Zone.current);
        },
      );
      // the zone a handler runs in: not the zone of the app or the test,
      // which may be gone when a tool calls it
      expect(zones, {Zone.root});
      expect(handlers.keys, AppBinding.serviceExtensions);
      expect(handlers.keys, [
        'ext.twk.tree',
        'ext.twk.properties',
        'ext.twk.layout',
        'ext.twk.select',
        'ext.twk.highlight',
        'ext.twk.flags',
        'ext.twk.reassemble',
        'ext.twk.log',
      ]);
      final tree = handlers['ext.twk.tree']!;
      final none = await tree('ext.twk.tree', {});
      expect(none.errorCode, ServiceExtensionResponse.extensionError);
      expect(jsonDecode(none.errorDetail!), {'message': 'no app runs'});

      await t.pumpWidget(app(), size: (20, 5));
      final answer = await tree('ext.twk.tree', {'isolateId': 'isolates/1'});
      final json = jsonDecode(answer.result!) as Json;
      expect(named(json, 'Text')['key'], "[<'header'>]");

      // a second app, started later, is the one answered about until it
      // ends
      final second = t.clock.run(
        () => AppBinding(
          HeadlessTerminal(width: 10, height: 1),
          clock: t.clock.stopwatch,
        ),
      );
      final ran = t.clock.run(() => second.run(const Text('second')));
      await t.pump(const Duration(milliseconds: 50));
      Future<String?> textShown() async {
        final answer = await tree('ext.twk.tree', {});
        final json = jsonDecode(answer.result!) as Json;
        return named(json, 'Text')['key'] as String?;
      }

      expect(await textShown(), isNull);
      second.quit();
      await t.clock.elapseUntil(ran);
      expect(await textShown(), "[<'header'>]");

      await t.quit();
      expect(
        (await tree('ext.twk.tree', {})).errorCode,
        ServiceExtensionResponse.extensionError,
      );
    });
  });

  test('over a VM service, a running app answers ext.twk.tree; in product '
      'mode it registers none', () async {
    final debug = await _extensionsOver(inspected);
    expect(debug.extensions, containsAll(AppBinding.serviceExtensions));
    expect(debug.tree['version'], 1);
    expect(named(debug.tree, 'Text')['properties'], [
      {'value': '"inspected"'},
    ]);
    final product = await _extensionsOver(inspectedInProduct);
    expect(product.extensions.where((e) => e.startsWith('ext.twk.')), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// A count, shown as text, or in brackets as text inside another widget.
final class _Count extends StatefulWidget {
  const _Count({super.key});

  @override
  State<_Count> createState() => _CountState();
}

final class _CountState extends State<_Count> {
  var _n = 0;
  var _bracketed = false;

  /// Counts one more.
  void add() => setState(() => _n++);

  /// Shows the count in brackets, or not.
  void toggle() => setState(() => _bracketed = !_bracketed);

  @override
  Widget build(BuildContext context) =>
      _bracketed ? _Bracketed('n $_n') : Text('n $_n');
}

/// [text] in brackets.
final class _Bracketed extends StatelessWidget {
  const _Bracketed(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text('[$text]');
}

/// A repaint boundary one row tall and as wide as it may be that shows
/// [text]: a new text repaints it alone.
final class Line extends LeafRenderObjectWidget {
  const Line(this.text, {super.key});

  final String text;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderLine(text);

  @override
  void updateRenderObject(BuildContext context, RenderLine renderObject) =>
      renderObject.show(text);
}

/// What a [Line] lays out and paints.
final class RenderLine extends RenderObject {
  RenderLine(this._text);

  String _text;

  /// Shows [t] from the next frame on.
  void show(String t) {
    if (t != _text) {
      _text = t;
      markNeedsPaint();
    }
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_text.length + 2);
    height = c.constrainH(1);
  }

  /// Paints all of its cells, as a repaint boundary does, their
  /// backgrounds opaque.
  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final pen = canvas.styles.pen(
      const Pen(fg: Color.defaultColor, bg: Color.defaultColor),
    );
    canvas
      ..fill(0, 0, width, height, pen)
      ..text(0, 0, _text, pen);
  }
}

/// The extensions the isolate of `inspected_app.dart`, compiled to
/// [kernel], registers, run with a VM service, and what its `ext.twk.tree`
/// answers, if it registers that.
Future<({List<String> extensions, Json tree})> _extensionsOver(
  String kernel,
) async {
  final dir = await Directory.systemTemp.createTemp('twk_service_');
  final info = File('${dir.path}/service.json');
  final process = await startProcess(Platform.resolvedExecutable, [
    '--enable-vm-service=0',
    '--disable-service-auth-codes',
    '--write-service-info=${info.uri}',
    kernel,
  ]);
  final out = StringBuffer();
  final running = Completer<bool>();
  process.stdout.transform(utf8.decoder).listen((s) {
    out.write(s);
    if (!running.isCompleted && '$out'.contains('running')) {
      running.complete(true);
    }
  });
  process.stderr.transform(utf8.decoder).listen(out.write);
  try {
    // the app says when it has drawn its first frame, unless it ends
    // first; after the VM service has started, which on a loaded machine
    // takes long
    final started = await waitFor(
      Future.any([running.future, process.exitCode.then((_) => false)]),
      'inspected_app.dart to say it runs',
      timeout: const Duration(seconds: 50),
    );
    if (!started) {
      fail('the app ended: $out');
    }
    // the VM service may say where it listens after the app ran
    await waitUntil(
      () => info.existsSync() && info.readAsStringSync().endsWith('}'),
      'the VM service to write where it listens',
    );
    final uri = Uri.parse(
      (jsonDecode(info.readAsStringSync()) as Json)['uri']! as String,
    );
    final socket = await WebSocket.connect(
      uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
    );
    final answers = socket.map((m) => jsonDecode(m as String) as Json);
    final pending = StreamIterator(answers);
    var next = 0;
    Future<Json> rpc(String method, [Json params = const {}]) async {
      final id = '${next++}';
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params,
        }),
      );
      while (await pending.moveNext()) {
        if (pending.current['id'] == id) {
          return pending.current;
        }
      }
      throw StateError('no answer to $method');
    }

    final vm = (await rpc('getVM'))['result']! as Json;
    final isolates = [
      for (final i in vm['isolates']! as List<Object?>)
        (i! as Json)['id']! as String,
    ];
    final extensions = <String>[];
    String? main;
    for (final id in isolates) {
      final isolate =
          (await rpc('getIsolate', {'isolateId': id}))['result']! as Json;
      final rpcs = [
        for (final e in isolate['extensionRPCs'] as List<Object?>? ?? [])
          e! as String,
      ];
      extensions.addAll(rpcs);
      if (isolate['name'] == 'main' || rpcs.contains('ext.twk.tree')) {
        main ??= id;
      }
    }
    var tree = <String, Object?>{};
    if (extensions.contains('ext.twk.tree')) {
      final answer = await rpc('ext.twk.tree', {'isolateId': main});
      tree = answer['result']! as Json;
    }
    await socket.close();
    return (extensions: extensions, tree: tree);
  } finally {
    process.kill();
    await process.exitCode;
    await dir.delete(recursive: true);
  }
}
