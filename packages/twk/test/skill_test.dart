// SKILL.md, the guide for coding agents that build apps with twk: its
// front matter; its code as the app it describes (the pubspec it gives,
// pointed at this checkout, and each ```dart block in the file its first
// line names), resolved, analyzed under this repository's rules,
// formatted and its tests passing; the names it uses as twk and twk_test
// export them, and the others as twk's cli, hooks and provider libraries
// and twk_test's cli library do; and its pitfalls as twk behaves.
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

final String skill = File('SKILL.md').readAsStringSync();

final _fence = RegExp(r'^```(\w*)\n(.*?)^```$', multiLine: true, dotAll: true);

/// The fenced blocks of [skill] in [language], in order.
List<String> blocks(String language) => [
  for (final m in _fence.allMatches(skill))
    if (m[1] == language) m[2]!,
];

/// [skill] without its fenced blocks.
final String prose = skill.replaceAll(_fence, '');

/// Runs `dart` with [args] in [dir] and expects it to exit with 0.
Future<String> dart(Directory dir, List<String> args) async {
  final got = await runProcess(
    Platform.resolvedExecutable,
    args,
    workingDirectory: dir.path,
    group: true,
  );
  final output = '${got.stdout}${got.stderr}';
  expect(got.exitCode, 0, reason: 'dart ${args.join(' ')}:\n$output');
  return output;
}

/// Writes [text] to [path] in [dir].
void write(Directory dir, String path, String text) => File('${dir.path}/$path')
  ..createSync(recursive: true)
  ..writeAsStringSync(text);

/// The public names [library] exports: its own and those of the libraries
/// it exports, through their show and hide lists.
Set<String> exported(LibraryMirror library) => {
  for (final MapEntry(:key, :value) in library.declarations.entries)
    if (!value.isPrivate) MirrorSystem.getName(key),
  for (final dependency in library.libraryDependencies)
    if (dependency.isExport)
      for (final name in exported(dependency.targetLibrary!))
        if (_passes(dependency.combinators, name)) name,
};

/// The names twk and twk_test export, and the extension types the guide
/// names.
Set<String> twkNames() {
  final libraries = currentMirrorSystem().libraries;
  return {
    ...exported(libraries[Uri.parse('package:twk/twk.dart')]!),
    ...exported(libraries[Uri.parse('package:twk_test/twk_test.dart')]!),
    ..._extensionTypes.keys,
  };
}

/// The names in the code spans of [prose]: each word that starts with a
/// capital and a small letter, but Dart's, the core's and the recipes'
/// own.
Set<String> namedInProse() {
  const others = {
    ...{'DateTime', 'StateError', 'Stopwatch', 'RenderFlex'},
    ...{'App', 'Entry'},
    // a word of the output it shows
    'Target',
  };
  return {
    for (final span in RegExp('`([^`]+)`').allMatches(prose))
      for (final name in RegExp(r'\b[A-Z][a-z]\w*').allMatches(span[1]!))
        name[0]!,
  }..removeAll(others);
}

/// The extension types the guide names, which mirrors do not see: this
/// file compiles only while twk exports them.
const Map<String, Color> _extensionTypes = {'Color': Color.blue};

bool _passes(List<CombinatorMirror> combinators, String name) {
  final symbol = MirrorSystem.getSymbol(name);
  // the VM gives each name of a show or hide list a combinator of its own
  final shows = combinators.where((c) => c.isShow);
  return !combinators.any(
        (c) => c.isHide && c.identifiers.contains(symbol),
      ) &&
      (shows.isEmpty || shows.any((c) => c.identifiers.contains(symbol)));
}

/// A count of Space, bound below a [Focus]; with [gated], bound only
/// while that focus is on.
final class _Toggle extends StatefulWidget {
  const _Toggle({required this.gated});

  final bool gated;

  @override
  State<_Toggle> createState() => _ToggleState();
}

final class _ToggleState extends State<_Toggle> {
  var _count = 0;

  void _increment() => setState(() => _count++);

  @override
  Widget build(BuildContext context) => Focus(
    child: _Binding(gated: widget.gated, count: _count, onSpace: _increment),
  );
}

final class _Binding extends StatelessWidget {
  const _Binding({
    required this.gated,
    required this.count,
    required this.onSpace,
  });

  final bool gated;
  final int count;
  final void Function() onSpace;

  @override
  Widget build(BuildContext context) {
    final text = Text('$count');
    return gated && !Focus.of(context).hasFocus
        ? text
        : KeyBindings({'space': onSpace}, child: text);
  }
}

/// A text that counts the seconds on a periodic timer.
final class _Ticking extends StatefulWidget {
  const _Ticking();

  @override
  State<_Ticking> createState() => _TickingState();
}

final class _TickingState extends State<_Ticking> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('ticking');
}

/// A widget whose build throws.
final class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) => throw StateError('broken');
}

void main() {
  test('the front matter names the skill and says when to use it', () {
    final front = RegExp(
      r'^---\nname: ([a-z0-9-]+)\ndescription: (.+)\n---\n',
    ).firstMatch(skill);
    expect(front, isNotNull, reason: 'name and description between ---');
    expect(front![2]!.length, lessThanOrEqualTo(1024));
  });

  group('the code, as an app', () {
    late Directory app;

    setUpAll(() async {
      app = await Directory.systemTemp.createTemp('twk_skill_test');
      final root = Directory.current.parent.parent.path;
      final pubspec = blocks(
        'yaml',
      ).singleWhere((b) => b.startsWith('# pubspec.yaml'));
      write(app, 'pubspec.yaml', pubspec.replaceAll('<twk>', root));
      final lints = await Isolate.resolvePackageUri(
        Uri.parse('package:pro_lints/recommended.yaml'),
      );
      // a path, which dart format reads too, where it takes no URI
      write(app, 'analysis_options.yaml', 'include: ${lints!.toFilePath()}\n');
      final paths = <String>{};
      for (final block in blocks('dart')) {
        final path = RegExp(
          r'^// ((?:lib|bin|test)/\w+\.dart)\n',
        ).firstMatch(block)?[1];
        expect(path, isNotNull, reason: 'no file named first in:\n$block');
        expect(paths.add(path!), isTrue, reason: '$path twice');
        write(app, path, block);
      }
      await dart(app, ['pub', 'get', '--offline']);
    });

    tearDownAll(() => app.delete(recursive: true));

    test('analyzes with no issue under the rules of this repository', () async {
      await dart(app, ['analyze', '--fatal-infos', 'lib', 'bin', 'test']);
    });

    test('is formatted', () async {
      await dart(app, [
        'format',
        '--output=none',
        '--set-exit-if-changed',
        'lib',
        'bin',
        'test',
      ]);
    });

    test('passes its tests', () async {
      await dart(app, ['test']);
    });

    test('a Table whose columns are written in its call does not analyze '
        'without its type argument', () async {
      write(app, 'untyped/table.dart', '''
import 'package:twk/twk.dart';

final class Entry {
  const Entry(this.name);

  final String name;
}

Widget table(List<Entry> entries) => Table(
  rows: entries,
  columns: [TableColumn(title: 'name', cell: (e) => TableCell(e.name))],
);
''');
      final got = await runProcess(
        Platform.resolvedExecutable,
        [
          'analyze',
          'untyped',
        ],
        workingDirectory: app.path,
        group: true,
      );
      expect(got.exitCode, isNot(0));
      expect('${got.stdout}', contains('unchecked_use_of_nullable_value'));
    });

    test('the names it gives are exported by twk and twk_test, the rest by '
        "twk's cli, hooks or provider library or by twk_test's cli", () async {
      final names = twkNames();
      final named = namedInProse();
      expect(named, isNotEmpty);
      expect(names, containsAll(['showDialog', 'closeDialog', 'showToast']));
      expect(names, containsAll(['showFilePicker', 'debugDumpTree', 'runApp']));
      expect(names, containsAll(['debugDumpRenderTree', 'testTwk', 'Builder']));
      // in the app, a name that none of twk's cli.dart, hooks.dart and
      // provider.dart and twk_test's cli.dart export does not analyze
      final rest = named.difference(names);
      expect(rest, containsAll(['Cli', 'FakeCliTerminal']));
      expect(rest, containsAll(['HookWidget', 'ChangeNotifierProvider']));
      write(app, 'names/rest.dart', '''
import 'package:twk/cli.dart';
import 'package:twk/hooks.dart';
import 'package:twk/provider.dart';
import 'package:twk_test/cli.dart';

/// What the guide names that twk.dart and twk_test do not export.
const List<Object> names = [
${[for (final name in rest) '  $name,\n'].join()}];
''');
      await dart(app, ['analyze', '--fatal-infos', 'names']);
    });
  });

  group('the pitfalls', () {
    for (final gated in [true, false]) {
      testTwk(
        gated
            ? 'a binding built only while its focus is on misses the key '
                  'typed right after Tab'
            : 'a binding always built below its Focus gets the key typed '
                  'right after Tab',
        (t) async {
          await t.pumpWidget(_Toggle(gated: gated));
          await t.type('\t ');
          await t.pump();
          expect(t.lines.first, gated ? '0' : '1');
          await t.press('space');
          await t.pump();
          expect(t.lines.first, gated ? '1' : '2');
        },
      );
    }

    testTwk('dialogs and toasts need an Overlay above their context', (
      t,
    ) async {
      await t.pumpWidget(const Text('x'));
      expect(
        () => showToast(t.element(find.text('x')), 'hi'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('place an Overlay above it'),
          ),
        ),
      );
    });

    testTwk('a focused TextField takes q and Ctrl+A, a binding above it '
        'gets Ctrl+S', (t) async {
      final pressed = <String>[];
      await t.pumpWidget(
        KeyBindings({
          for (final key in ['q', 'ctrl+a', 'ctrl+s'])
            key: () => pressed.add(key),
        }, child: const TextField(autofocus: true)),
      );
      await t.press('q ctrl+a ctrl+s');
      expect(pressed, ['ctrl+s']);
    });

    testTwk('a list in a Column outside Expanded takes the whole height, '
        'the rest overflowing', (t) async {
      await t.pumpWidget(
        Column(
          children: [
            ListView(children: const [Text('a')]),
            const Text('below'),
          ],
        ),
        size: (20, 4),
      );
      expect(t, isNot(containsLine(contains('below'))));
      expect(
        t.logs.records.map((r) => r.message),
        contains(startsWith('A RenderFlex overflowed')),
      );
    });

    testTwk('inline, a list asks for no rows', (t) async {
      await t.pumpWidget(
        Column(
          children: [
            const Text('top'),
            Expanded(child: ListView(children: const [Text('item')])),
          ],
        ),
        size: (20, 4),
        mode: ScreenMode.inline,
      );
      expect(t, isNot(containsLine(contains('item'))));
    });

    testTwk('a Column centres its children across', (t) async {
      await t.pumpWidget(const Column(children: [Text('top')]), size: (9, 1));
      expect(t.lines, ['   top']);
    });

    testTwk('print in the app goes to its log', (t) async {
      await t.pumpWidget(
        KeyBindings(
          // what the guide says of print
          // ignore: avoid_print
          {'p': () => print('printed')},
          child: const Text('x'),
        ),
      );
      await t.press('p');
      expect(t.logs.records.last.message, 'printed');
      expect(t.lines.first, 'x');
    });

    testTwk('a build that throws shows its error and the app goes on; a '
        'binding that throws ends it with a WidgetError', (t) async {
      await t.pumpWidget(
        KeyBindings(
          {'x': () => throw StateError('boom')},
          child: const Column(children: [Text('ok'), _Broken()]),
        ),
        size: (30, 3),
      );
      expect(t, containsLine(contains('Bad state: broken')));
      expect(
        t.logs.records.map((r) => r.message),
        contains(endsWith('Column → _Broken failed to build')),
      );
      await expectLater(
        t.press('x'),
        throwsA(
          isA<WidgetError>().having(
            (e) => '$e',
            'text',
            contains('in KeyBindings → Focus'),
          ),
        ),
      );
    });

    testTwk('pumpUntilIdle fails for an app with a periodic timer', (t) async {
      await t.pumpWidget(const _Ticking());
      await expectLater(
        t.pumpUntilIdle(timeout: const Duration(seconds: 2)),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
