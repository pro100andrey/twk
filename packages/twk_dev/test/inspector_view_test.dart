// The inspector's screen on canned answers of an app's ext.twk.*
// extensions: the widget tree from the app's widget, the selected node's
// properties and layout, the outline following the selection, a pick on
// the app's screen, the render tree, and apps that come and go.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_dev/src/app_client.dart';
import 'package:twk_dev/src/inspector_view.dart';
import 'package:twk_test/twk_test.dart';

/// An element tree as `ext.twk.tree` describes it: the binding's nodes,
/// then the app's Column (4) of a Text (6) and a Counter (8), whose Text
/// (10) shows a count.
Json elementTree({String count = '"count 0"', bool more = false}) => {
  'version': 1,
  'tree': 'element',
  'app': 4,
  'root': {
    'id': 1,
    'name': 'RootWidget',
    'properties': <Object?>[],
    'flags': <Object?>[],
    'render': 2,
    'children': [
      {
        'id': 3,
        'name': '_Scope',
        'properties': <Object?>[],
        'flags': <Object?>[],
        'render': 5,
        'children': [
          {
            'id': 4,
            'name': 'Column',
            'properties': [
              {'name': 'direction', 'value': 'vertical'},
            ],
            'size': {'width': 20, 'height': 2},
            'flags': ['relayoutBoundary'],
            'render': 5,
            'children': [
              {
                'id': 6,
                'name': 'Text',
                'key': "[<'header'>]",
                'properties': [
                  {'value': '"header"'},
                ],
                'flags': <Object?>[],
                'render': 7,
                'children': <Object?>[],
              },
              {
                'id': 8,
                'name': 'Counter',
                'properties': <Object?>[],
                'flags': <Object?>[],
                'render': 9,
                'children': [
                  {
                    'id': 10,
                    'name': 'Text',
                    'properties': [
                      {'value': count},
                    ],
                    'flags': ['overflow'],
                    'render': 9,
                    'children': [
                      if (more)
                        {
                          'id': 11,
                          'name': 'Badge',
                          'properties': <Object?>[],
                          'flags': <Object?>[],
                          'render': 9,
                          'children': [
                            {
                              'id': 12,
                              'name': 'Inner',
                              'properties': <Object?>[],
                              'flags': <Object?>[],
                              'children': <Object?>[],
                            },
                          ],
                        },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  },
};

/// The render tree of [elementTree].
final Json renderTree = {
  'version': 1,
  'tree': 'render',
  'root': {
    'id': 2,
    'name': '_RenderView',
    'properties': <Object?>[],
    'flags': <Object?>[],
    'children': [
      {
        'id': 5,
        'name': 'RenderFlex',
        'element': 4,
        'properties': <Object?>[],
        'flags': <Object?>[],
        'children': [
          {
            'id': 7,
            'name': 'RenderParagraph',
            'element': 6,
            'properties': <Object?>[],
            'flags': <Object?>[],
            'children': <Object?>[],
          },
          {
            'id': 9,
            'name': 'RenderParagraph',
            'element': 10,
            'properties': <Object?>[],
            'flags': <Object?>[],
            'children': <Object?>[],
          },
        ],
      },
    ],
  },
};

/// The nodes of [node] and below, by id.
Map<int, Json> nodesOf(Json node) => {
  node['id']! as int: node,
  for (final child in node['children']! as List<Object?>)
    ...nodesOf(child! as Json),
};

/// An app that answers with canned JSON and records what it is asked:
/// `tree`, `tree render`, `properties 6`, `highlight 6`, `highlight`,
/// `flags select=true`, `select 3,2`.
final class FakeApp implements AppClient {
  FakeApp({this.inline = false, this.tree = elementTree});

  /// Whether it runs inline, where it cannot pick.
  final bool inline;

  /// What `ext.twk.tree` answers.
  Json Function() tree;

  /// Ids `ext.twk.properties` answers with an error for.
  final gone = <int>{};

  /// Answers held until completed: `ext.twk.tree`'s, and
  /// `ext.twk.properties`' by id.
  Completer<void>? holdTree;
  final holdProperties = <int, Completer<void>>{};

  /// Whether `ext.twk.highlight` never answers, as in an app paused.
  var paused = false;

  /// What `ext.twk.select` finds: the Inner below the Text of the count,
  /// or nothing.
  var hit = true;

  final asked = <String>[];
  final _picks = StreamController<(int, int)?>.broadcast();
  final _done = Completer<void>();

  @override
  String get name => 'ws://127.0.0.1:1/fake=/ws';

  /// Picks [cell] on the app's screen; null cancels.
  void pick((int, int)? cell) => _picks.add(cell);

  /// The app goes away.
  void end() => _done.complete();

  @override
  Future<Json> call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    final id = params['id'];
    asked.add(switch (method) {
      'tree' => params['tree'] == 'render' ? 'tree render' : 'tree',
      'flags' => 'flags select=${params['select']}',
      'select' => 'select ${params['x']},${params['y']}',
      _ => id == null ? method : '$method $id',
    });
    switch (method) {
      case 'tree':
        final answer = params['tree'] == 'render' ? renderTree : tree();
        await holdTree?.future;
        return answer;
      case 'properties' || 'layout':
        final n = int.parse(id!);
        final nodes = {
          ...nodesOf(elementTree(more: true)['root']! as Json),
          ...nodesOf(renderTree['root']! as Json),
        };
        if (method == 'properties') {
          await holdProperties[n]?.future;
        }
        if (gone.contains(n) || !nodes.containsKey(n)) {
          throw AppError('no node $n in the app');
        }
        if (method == 'properties') {
          return {...nodes[n]!}..remove('children');
        }
        return {
          'version': 1,
          'id': n,
          'render': nodes[n]!['render'] ?? n,
          'name': 'RenderFlex',
          'constraints': {
            'minWidth': 0,
            'maxWidth': 20,
            'minHeight': 2,
            'maxHeight': 2,
          },
          'size': {'width': 20, 'height': 2},
          'offset': {'x': 0, 'y': 0},
          'global': {'x': 2, 'y': 1},
        };
      case 'highlight':
        if (paused) {
          await Completer<void>().future;
        }
        return {'version': 1, 'id': id == null ? null : int.parse(id)};
      case 'flags':
        return {'version': 1, 'select': params['select'] == 'true' && !inline};
      case 'select':
        return hit
            ? {
                'version': 1,
                'id': 12,
                'path': [1, 3, 4, 8, 10, 11, 12],
                'render': [9, 5, 2],
              }
            : {'version': 1, 'id': null, 'path': <Object?>[], 'render': []};
    }
    throw AppError('no $method');
  }

  @override
  Stream<(int, int)?> get picks => _picks.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {}
}

/// The inspector on [apps], its screen 80 × 20.
Future<void> inspect(TwkTester t, Stream<AppClient> apps) async {
  await t.pumpWidget(
    InspectorView(apps: apps, waiting: 'waiting for an app', gone: 'gone'),
    size: (80, 20),
  );
  await t.pumpUntilIdle();
}

/// The rows of the tree's pane, the left one, trimmed.
List<String> treeRows(TwkTester t) => [
  for (final line in t.lines.skip(1).take(16))
    line.substring(1, line.length.clamp(1, 42)).trim(),
];

void main() {
  testTwk("shows the widget tree from the app's widget, its node selected "
      "with its properties and layout, outlined on the app's screen", (
    t,
  ) async {
    final app = FakeApp();
    await inspect(t, Stream.value(app));

    expect(t.lines.first, contains('widget tree'));
    final rows = treeRows(t);
    expect(rows.take(4), [
      '▾ Column',
      '├── Text [<\'header\'>] "header"',
      '└─▾ Counter',
      '└── Text "count 0" overflow',
    ]);
    expect(t.lines.join('\n'), isNot(contains('RootWidget')));
    expect(t, containsLine(contains('Column  #4')));
    expect(t, containsLine(contains('render      #5')));
    expect(t, containsLine(contains('direction   vertical')));
    expect(t, containsLine(contains('flags       relayoutBoundary')));
    expect(t, containsLine(contains('constraints w 0..20, h 2')));
    expect(t, containsLine(contains('size        20 x 2')));
    expect(t, containsLine(contains('on screen   2, 1')));
    expect(t, containsLine(contains('inspecting ws://127.0.0.1:1/fake=/ws')));
    expect(app.asked, ['tree', 'properties 4', 'highlight 4', 'layout 4']);
  });

  testTwk('the keys move the selection, the details and the outline '
      'following it; h turns the outline off and on', (t) async {
    final app = FakeApp();
    await inspect(t, Stream.value(app));
    app.asked.clear();

    await t.press('down');
    await t.pumpUntilIdle();
    expect(app.asked, ['properties 6', 'highlight 6', 'layout 6']);
    expect(t, containsLine(contains('Text  #6')));
    expect(t, containsLine(contains("key         [<'header'>]")));
    expect(t, containsLine(contains('"header"')));

    app.asked.clear();
    await t.press('h');
    await t.press('down');
    await t.pumpUntilIdle();
    expect(app.asked, ['highlight', 'properties 8', 'layout 8']);
    app.asked.clear();
    await t.press('h');
    await t.pumpUntilIdle();
    expect(app.asked, ['highlight 8']);
  });

  testTwk('s has the app pick a node, which is selected, its ancestors '
      'expanded; Escape in the app picks none', (t) async {
    final app = FakeApp()..tree = (() => elementTree(more: true));
    await inspect(t, Stream.value(app));
    // the node picked is below one collapsed
    await t.press('end');
    await t.press('left');
    await t.press('left');
    await t.pumpUntilIdle();
    expect(treeRows(t), isNot(contains(contains('Inner'))));
    app.asked.clear();

    await t.press('s');
    await t.pumpUntilIdle();
    expect(app.asked, ['flags select=true']);
    expect(t, containsLine(contains('click a node on the app’s screen')));
    expect(t, containsLine(contains('stop picking')));

    app.asked.clear();
    app.pick((3, 2));
    await t.pumpUntilIdle();
    expect(app.asked.take(2), ['select 3,2', 'tree']);
    expect(treeRows(t), contains(contains('Inner')));
    expect(t, containsLine(contains('Inner  #12')));
    expect(t, containsLine(contains('picked Inner at 3, 2')));
    expect(app.asked, contains('highlight 12'));

    await t.press('s');
    await t.pumpUntilIdle();
    app.pick(null);
    await t.pumpUntilIdle();
    expect(t, containsLine(contains('nothing picked')));
    expect(t, containsLine(contains('select on screen')));

    app.hit = false;
    await t.press('s');
    await t.pumpUntilIdle();
    app.pick((30, 9));
    await t.pumpUntilIdle();
    expect(t, containsLine(contains('nothing at 30, 9')));
    expect(t, containsLine(contains('Inner  #12')));

    // picked from the render tree, the node shows in the widget tree
    app.hit = true;
    await t.press('home');
    await t.press('t');
    await t.pumpUntilIdle();
    await t.press('s');
    await t.pumpUntilIdle();
    app.pick((3, 2));
    await t.pumpUntilIdle();
    expect(t.lines.first, contains('widget tree'));
    expect(t, containsLine(contains('Inner  #12')));
  });

  testTwk('s again stops the pick; an app that runs inline cannot pick', (
    t,
  ) async {
    final app = FakeApp();
    await inspect(t, Stream.value(app));
    app.asked.clear();
    await t.press('s');
    await t.pumpUntilIdle();
    await t.press('s');
    await t.pumpUntilIdle();
    expect(app.asked, ['flags select=true', 'flags select=false']);
    expect(t, containsLine(contains('nothing picked')));

    final inline = FakeApp(inline: true);
    await inspect(t, Stream.value(inline));
    await t.press('s');
    await t.pumpUntilIdle();
    expect(
      t,
      containsLine(
        contains('the app runs inline, where its terminal keeps the mouse'),
      ),
    );
  });

  testTwk('t shows the render tree from its root, the render object of the '
      'node selected selected, and back', (t) async {
    final app = FakeApp();
    await inspect(t, Stream.value(app));
    await t.press('down');
    await t.pumpUntilIdle();
    app.asked.clear();

    await t.press('t');
    await t.pumpUntilIdle();
    expect(t.lines.first, contains('render tree'));
    expect(treeRows(t).take(4), [
      '▾ _RenderView',
      '└─▾ RenderFlex',
      '├── RenderParagraph',
      '└── RenderParagraph',
    ]);
    expect(app.asked.take(3), ['tree render', 'properties 7', 'highlight 7']);
    expect(t, containsLine(contains('element     #6')));

    await t.press('down');
    await t.press('t');
    await t.pumpUntilIdle();
    expect(t.lines.first, contains('widget tree'));
    expect(t, containsLine(contains('Text  #10')));
  });

  testTwk('r and the focus coming back load the tree again, a node not seen '
      'before expanded, the selection kept', (t) async {
    final app = FakeApp();
    await inspect(t, Stream.value(app));
    await t.press('down');
    await t.pumpUntilIdle();
    app.asked.clear();

    app.tree = () => elementTree(count: '"count 1"', more: true);
    await t.press('r');
    await t.pumpUntilIdle();
    expect(app.asked, ['tree', 'properties 6', 'highlight 6', 'layout 6']);
    expect(treeRows(t), contains('└─▾ Text "count 1" overflow'));
    expect(treeRows(t), contains(contains('Inner')));

    app.asked.clear();
    // a focus report: this terminal has the focus again
    await t.input('\x1b[I'.codeUnits);
    await t.pumpUntilIdle();
    expect(app.asked.first, 'tree');
  });

  testTwk('loads the tree again while the app has drawn no frame', (t) async {
    var calls = 0;
    final app = FakeApp()
      ..tree = () => ++calls < 3
          ? {'version': 1, 'tree': 'element', 'app': null, 'root': null}
          : elementTree();
    await inspect(t, Stream.value(app));
    expect(calls, 3);
    expect(treeRows(t).first, '▾ Column');
    expect(t, containsLine(contains('Column  #4')));
  });

  testTwk('shows the answers about the node selected last, and the tree '
      'asked for last, whatever comes after', (t) async {
    final app = FakeApp();
    await inspect(t, Stream.value(app));
    final held = app.holdProperties[6] = Completer<void>();
    await t.press('down');
    await t.press('down');
    await t.pumpUntilIdle();
    expect(t, containsLine(contains('Counter  #8')));
    held.complete();
    await t.pumpUntilIdle();
    expect(t, containsLine(contains('Counter  #8')));
    expect(t, isNot(containsLine(contains('Text  #6'))));

    final tree = app.holdTree = Completer<void>();
    await t.press('t');
    await t.pumpUntilIdle();
    app.holdTree = null;
    await t.press('t');
    await t.pumpUntilIdle();
    tree.complete();
    await t.pumpUntilIdle();
    expect(t.lines.first, contains('widget tree'));
    expect(treeRows(t).first, '▾ Column');
  });

  testTwk('q takes the pick and the outline off the app, then quits', (
    t,
  ) async {
    final app = FakeApp();
    await inspect(t, Stream.value(app));
    await t.press('s');
    await t.pumpUntilIdle();
    app.asked.clear();
    await t.press('q');
    await t.pumpUntilIdle();
    expect(app.asked, ['flags select=false', 'highlight']);
    expect(t.isRunning, isFalse);
  });

  testTwk('Ctrl+C quits as q does', (t) async {
    final app = FakeApp();
    await inspect(t, Stream.value(app));
    app.asked.clear();
    await t.press('ctrl+c');
    await t.pumpUntilIdle();
    expect(app.asked, ['highlight']);
    expect(t.isRunning, isFalse);
  });

  testTwk('q waits a second at most for an app that does not answer', (
    t,
  ) async {
    final app = FakeApp();
    await inspect(t, Stream.value(app));
    app.paused = true;
    await t.press('q');
    await t.pump(const Duration(milliseconds: 900));
    expect(t.isRunning, isTrue);
    await t.pump(const Duration(milliseconds: 200));
    await t.pump();
    expect(t.isRunning, isFalse);
  });

  testTwk('q leaves alone what is off', (t) async {
    final app = FakeApp();
    await inspect(t, Stream.value(app));
    await t.press('h');
    await t.pumpUntilIdle();
    app.asked.clear();
    await t.press('q');
    await t.pumpUntilIdle();
    expect(app.asked, isEmpty);
    expect(t.isRunning, isFalse);
  });

  testTwk('says why no app came', (t) async {
    await inspect(t, Stream.error(const AppError('the app went away')));
    expect(t, containsLine(contains('the app went away')));
  });

  testTwk('says what the app answered in place of a node', (t) async {
    final app = FakeApp()..gone.add(6);
    await inspect(t, Stream.value(app));
    await t.press('down');
    await t.pumpUntilIdle();
    expect(t, containsLine(contains('no node 6 in the app')));
  });

  testTwk('waits for an app, says when it has gone, and starts over with the '
      'next', (t) async {
    final apps = StreamController<AppClient>();
    await inspect(t, apps.stream);
    expect(t, containsLine(contains('waiting for an app')));
    expect(t, containsLine(contains('no app yet')));

    final first = FakeApp();
    apps.add(first);
    await t.pumpUntilIdle();
    expect(treeRows(t).first, '▾ Column');
    await t.press('down');
    await t.pumpUntilIdle();

    first.end();
    await t.pumpUntilIdle();
    expect(t, containsLine(contains('gone')));

    final second = FakeApp()..tree = (() => elementTree(count: '"count 7"'));
    apps.add(second);
    await t.pumpUntilIdle();
    expect(treeRows(t), contains('└── Text "count 7" overflow'));
    expect(t, containsLine(contains('Column  #4')));
    expect(second.asked, ['tree', 'properties 4', 'highlight 4', 'layout 4']);
    await apps.close();
  });
}
