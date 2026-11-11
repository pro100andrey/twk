// Where a widget was made, found through the VM service of the app
// (lib/src/source_locator.dart), and opened from the inspector with g: the
// answers of the VM are canned, the editor's command recorded.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart' show EditorCommand;
import 'package:twk_dev/src/app_client.dart';
import 'package:twk_dev/src/inspector_view.dart';
import 'package:twk_dev/src/source_find.dart';
import 'package:twk_dev/src/source_locator.dart';
import 'package:twk_test/twk_test.dart';

const _source = '''
class _PageState extends State<Page> {
  @override
  Widget build(BuildContext context) {
    // Text('not this')
    return Column(children: [
      Text('a'),
      Text('b'),
    ]);
  }
}
''';

Json _node(int id, String name, [List<Json> children = const [], String? b]) =>
    {
      'id': id,
      'name': name,
      'properties': <Object?>[],
      'flags': <Object?>[],
      'build': ?b,
      'children': children,
    };

/// RootWidget (1) > Page (2, built by _PageState) > Column (3) > two Texts
/// (4, 5).
Json get _tree => {
  'version': 1,
  'tree': 'element',
  'app': 2,
  'root': _node(1, 'RootWidget', [
    _node(2, 'Page', [
      _node(3, 'Column', [_node(4, 'Text'), _node(5, 'Text')]),
    ], '_PageState'),
  ]),
};

/// An app whose VM has the source above as a package script.
final class VmApp implements AppClient, VmQueries {
  final asked = <String>[];
  final _done = Completer<void>();

  @override
  String get name => 'vm';

  @override
  Future<Json> vm(String method, [Map<String, Object?> args = const {}]) async {
    asked.add('$method ${args['objectId'] ?? ''}'.trim());
    switch ((method, args['objectId'])) {
      case ('getClassList', _):
        return {
          'classes': [
            {
              'id': 'c0',
              'name': '_PageState',
              'library': {'uri': 'dart:core'},
            },
            {
              'id': 'c1',
              'name': '_PageState',
              'library': {'uri': 'package:app/page.dart'},
            },
          ],
        };
      case ('getObject', 'c1'):
        return {
          'functions': [
            {'name': 'initState', 'id': 'f0'},
            {'name': 'build', 'id': 'f1'},
          ],
        };
      case ('getObject', 'f1'):
        return {
          'location': {
            'script': {'id': 's1'},
            'line': 2,
            'column': 3,
          },
        };
      case ('getObject', 's1'):
        return {'uri': 'package:app/page.dart', 'source': _source};
      case ('lookupResolvedPackageUris', _):
        return {
          'uris': ['file:///work/app/lib/page.dart'],
        };
    }
    throw AppError('no $method');
  }

  @override
  Future<Json> call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    asked.add(method);
    return switch (method) {
      'tree' => _tree,
      'properties' || 'layout' => {'version': 1, 'id': 1, 'name': 'x'},
      'highlight' => {'version': 1, 'id': null},
      _ => throw AppError('no $method'),
    };
  }

  @override
  Stream<(int, int)?> get picks => const Stream.empty();

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {}
}

/// [VmApp] whose `getClassList` can be made to fail, or to wait.
final class FlakyApp extends VmApp {
  var failing = false;

  /// Answers the next `getClassList` when it completes, with its error.
  Completer<void>? gate;

  @override
  Future<Json> vm(String method, [Map<String, Object?> args = const {}]) async {
    if (method == 'getClassList') {
      final wait = gate;
      gate = null;
      if (wait != null) {
        asked.add(method);
        await wait.future;
        throw const AppError('reloading');
      }
      if (failing) {
        asked.add(method);
        throw const AppError('reloading');
      }
    }
    return super.vm(method, args);
  }
}

void main() {
  test('a failed question is asked again, not kept as no build', () async {
    final app = FlakyApp()..failing = true;
    final locator = SourceLocator(app);
    expect(await locator.buildMethod('_PageState'), isNull);
    app.failing = false;
    final build = await locator.buildMethod('_PageState');
    expect((build!.line, build.column), (3, 10));
  });

  test('a failure that comes after forget does not undo the new class '
      'list', () async {
    final app = FlakyApp();
    final locator = SourceLocator(app);
    final gate = app.gate = Completer<void>();
    final old = locator.buildMethod('_PageState');
    await pumpEventQueue();
    locator.forget();
    expect(await locator.buildMethod('_PageState'), isNotNull);
    gate.complete();
    expect(await old, isNull);
    final asked = app.asked.where((m) => m == 'getClassList').length;
    expect(await locator.buildMethod('Other'), isNull);
    expect(app.asked.where((m) => m == 'getClassList').length, asked);
  });

  test('finds the call that made a widget, by its place among its '
      "build's, in the file the package resolves to", () async {
    final app = VmApp();
    final locator = SourceLocator(app);
    final root = InspectNode(_tree['root']! as Json);
    final first = await locator.creation(root, 4, 'Text');
    expect(first!.path, '/work/app/lib/page.dart');
    expect((first.line, first.column, first.exact), (6, 7, true));
    expect(first.method, '_PageState.build');
    final second = await locator.creation(root, 5, 'Text');
    expect((second!.line, second.column), (7, 7));
    // Column is the one call to it
    final column = await locator.creation(root, 3, 'Column');
    expect((column!.line, column.column), (5, 12));
    // nothing calls a Card
    expect(await locator.creation(root, 4, 'Card'), isNull);
    // the build method itself, at its name
    final build = await locator.buildMethod('_PageState');
    expect((build!.line, build.column), (3, 10));
    // what was read is kept, until forgotten
    final before = app.asked.length;
    await locator.creation(root, 5, 'Text');
    expect(app.asked.length, before);
    locator.forget();
    await locator.creation(root, 5, 'Text');
    expect(app.asked.length, greaterThan(before));
  });

  testTwk('g opens the place the selected widget was made in the editor '
      'TWK_EDITOR names', (t) async {
    final app = VmApp();
    final opened = <EditorCommand>[];
    await t.pumpWidget(
      InspectorView(
        apps: Stream.value(app),
        waiting: 'waiting',
        environment: const {'TWK_EDITOR': 'code -g {file}:{line}:{column}'},
        openEditor: (c) async {
          opened.add(c);
          return null;
        },
      ),
      size: (80, 20),
    );
    await t.pumpUntilIdle();
    // Page, Column, Text a, Text b
    for (var i = 0; i < 3; i++) {
      await t.press('down');
    }
    await t.pumpUntilIdle();
    await t.press('g');
    await t.pumpUntilIdle();
    expect(opened.single.executable, 'code');
    expect(opened.single.arguments, ['-g', '/work/app/lib/page.dart:7:7']);
    expect(opened.single.inTerminal, isFalse);
    expect(t, containsLine(contains('_PageState.build')));
  });

  testTwk('g says why nothing was opened: no editor set', (t) async {
    final app = VmApp();
    final opened = <EditorCommand>[];
    await t.pumpWidget(
      InspectorView(
        apps: Stream.value(app),
        waiting: 'waiting',
        environment: const {},
        openEditor: (c) async {
          opened.add(c);
          return 0;
        },
      ),
      size: (100, 20),
    );
    await t.pumpUntilIdle();
    await t.press('down');
    await t.press('g');
    await t.pumpUntilIdle();
    expect(opened, isEmpty);
    expect(t, containsLine(contains('set TWK_EDITOR')));
  });
}
