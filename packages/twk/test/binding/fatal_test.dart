// A fatal error under runApp: one an input listener throws ends the app,
// and once the terminal is restored the error says what it was, where in
// the tree the listener is, the lines of the app's own code it was thrown
// at, and the stack. Those lines are of the first frame neither in the
// SDK, nor in twk, nor in the pub cache, read from its file, and left out
// where that can't be read.
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

import 'harness.dart';

/// The platform's separator, as a pattern: in the paths shown from the
/// working directory.
final String _s = RegExp.escape(Platform.pathSeparator);

/// The number of the line of [file], this one by default, that starts with
/// [start] after its indentation, which only one does.
int lineOf(String start, [String file = 'test/binding/fatal_test.dart']) {
  final lines = File(file).readAsLinesSync();
  final at = [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].trimLeft().startsWith(start)) i + 1,
  ];
  expect(at, hasLength(1), reason: start);
  return at.single;
}

/// The [WidgetError] the app ends with once a key is typed, [onEvent]
/// throwing in its InputListener.
Future<WidgetError> endedBy(bool Function(InputEvent) onEvent) async {
  final run = Run(
    Column(
      children: [
        const Label('x'),
        InputListener(onEvent: onEvent, child: const SizedBox()),
      ],
    ),
  );
  await run.settle();
  run.term.type('a');
  return run.ended().then<WidgetError>(
    (_) => fail('the app ended without an error'),
    onError: (Object e) => e as WidgetError,
  );
}

/// The WidgetError thrown at [stack], a stack trace in the VM's format.
WidgetError thrownAt(String stack) {
  try {
    Error.throwWithStackTrace(
      WidgetError(StateError('boom'), 'Column → InputListener'),
      StackTrace.fromString(stack),
    );
  } on Object catch (e) {
    return e as WidgetError;
  }
}

void main() {
  // the app run in a process of its own, compiled once
  late String app;
  setUpAll(
    () async => app = await compiledProgram(
      'test/binding/fatal_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test('an InputListener that throws ends the app after the terminal is '
      'restored, with a WidgetError naming its path', () async {
    final run = Run(
      Column(
        children: [
          const Label('x'),
          InputListener(
            onEvent: (e) => throw StateError('boom'),
            child: const SizedBox(),
          ),
        ],
      ),
    );
    await run.settle();
    run.term.type('a');
    final error = await run.ended().then<WidgetError?>(
      (_) => null,
      onError: (Object e) => e as WidgetError,
    );
    expect(run.term.closed, isTrue);
    expect(error!.error, isA<StateError>());
    expect(error.path, 'Column → InputListener');
    expect('${error.stackTrace}', contains('fatal_test.dart'));
    final at = lineOf("onEvent: (e) => throw StateError('boom'),");
    expect('$error'.split('\n'), [
      'Bad state: boom',
      'in Column → InputListener',
      matches('^at test${_s}binding${_s}fatal_test\\.dart:$at:\\d+\$'),
      "  ${at - 2} |           const Label('x'),",
      '  ${at - 1} |           InputListener(',
      "> $at |             onEvent: (e) => throw StateError('boom'),",
      '  ${at + 1} |             child: const SizedBox(),',
      '  ${at + 2} |           ),',
    ]);
    expect('$error', endsWith(error.source!));
  });

  test("the lines are those of the app's code that called the SDK or twk "
      'where it threw', () async {
    final sdk = await endedBy((e) => int.parse('x') > 0);
    expect(sdk.error, isFormatException);
    expect('${sdk.stackTrace}', matches(RegExp(r'^#0\s+\S+ \(dart:')));
    final sdkAt = lineOf('final sdk = await endedBy(');
    expect(sdk.source!.split('\n')[3], startsWith('> $sdkAt |'));

    final twk = await endedBy((e) {
      TabController(length: 1).length = 0;
      return true;
    });
    expect(twk.error, isRangeError);
    expect('${twk.stackTrace}', matches(RegExp(r'^#0 .*\(package:twk/')));
    final twkAt = lineOf('TabController(length: 1).length = 0;');
    expect(
      twk.source!.split('\n').take(4),
      [
        matches('^at test${_s}binding${_s}fatal_test\\.dart:$twkAt:\\d+\$'),
        anything,
        anything,
        startsWith('> $twkAt |'),
      ],
    );
  });

  group('the lines shown', () {
    late Directory dir;
    late String app;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('twk_fatal_');
      addTearDown(() => dir.deleteSync(recursive: true));
      app = '${dir.path}${Platform.pathSeparator}app.dart';
      File(app).writeAsStringSync(
        [for (var i = 1; i <= 12; i++) 'line $i'].join('\n'),
      );
    });

    test('are two on each side of the marked one, within the file, the '
        'numbers right-aligned', () {
      final uri = File(app).uri;
      expect(thrownAt('#0      main ($uri:5:3)\n').source, '''
at $app:5:3
  3 | line 3
  4 | line 4
> 5 | line 5
  6 | line 6
  7 | line 7''');
      expect(thrownAt('#0      main ($uri:1:1)\n').source, '''
at $app:1:1
> 1 | line 1
  2 | line 2
  3 | line 3''');
      expect(thrownAt('#0      main ($uri:9)\n').source, '''
at $app:9
   7 | line 7
   8 | line 8
>  9 | line 9
  10 | line 10
  11 | line 11''');
      expect(thrownAt('#0      main ($uri:12:1)\n').source, '''
at $app:12:1
  10 | line 10
  11 | line 11
> 12 | line 12''');
    });

    test('are those of the first frame in neither the SDK, nor twk, nor '
        'the pub cache; of a package by the file it resolves to', () {
      final cached = File('${dir.path}/.pub-cache/hosted/a-1.0.0/lib/a.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('cached');
      final error = thrownAt('''
#0      Object.noSuchMethod (dart:core-patch/object_patch.dart:38:5)
#1      _Sdk.run (org-dartlang-sdk:///sdk/lib/async/zone.dart:1:1)
#2      TabController.length= (package:twk/src/controls/tabs.dart:49:7)
#3      Terminal.write (package:twk_core/src/terminal/terminal.dart:1:1)
#4      a (${cached.uri}:1:1)
<asynchronous suspension>
#5      main (${File(app).uri}:5:3)
#6      later (${File(app).uri}:8:3)
''');
      expect(error.source, startsWith('at $app:5:3\n'));
      expect('$error', '''
Bad state: boom
in Column → InputListener
${error.source}''');

      final vt = [
        Directory.current.parent.path,
        'twk_test',
        'lib',
        'vt.dart',
      ].join(Platform.pathSeparator);
      final first = File(vt).readAsLinesSync().first;
      expect(
        thrownAt('#0      vt (package:twk_test/vt.dart:1:1)\n').source,
        startsWith('at $vt:1:1\n> 1 | $first\n'),
      );
    });

    test('are left out where that file is missing, has fewer lines, or is '
        'of a package the program does not resolve', () {
      for (final frame in [
        '${File('${dir.path}/gone.dart').uri}:2:1',
        '${File(app).uri}:13:1',
        'package:no_such_package/a.dart:2:1',
      ]) {
        final error = thrownAt(
          '#0      main ($frame)\n#1      next (${File(app).uri}:5:3)\n',
        );
        expect(error.source, isNull, reason: frame);
        expect('$error', 'Bad state: boom\nin Column → InputListener');
      }
      expect(thrownAt('main.dart 5:3  main\n').source, isNull);
      expect(WidgetError(StateError('boom'), 'Label').source, isNull);
    });
  });

  test('unhandled, it is printed after the restore: message, path, the '
      'lines it was thrown at and the stack', () async {
    final res = await runProcess(Platform.resolvedExecutable, [app]);
    expect(res.stdout, '');
    final at = lineOf(
      "onEvent: (e) => throw StateError('boom'),",
      'test/binding/fatal_app.dart',
    );
    // a line ends in CR LF on Windows
    final lines = (res.stderr as String).replaceAll('\r\n', '\n').split('\n');
    expect(lines.take(10), [
      'restored',
      'Unhandled exception:',
      'Bad state: boom',
      'in Column → InputListener',
      matches('^at test${_s}binding${_s}fatal_app\\.dart:$at:\\d+\$'),
      '  ${at - 2} |       children: [',
      '  ${at - 1} |         InputListener(',
      "> $at |           onEvent: (e) => throw StateError('boom'),",
      '  ${at + 1} |           child: const SizedBox(),',
      '  ${at + 2} |         ),',
    ]);
    expect(lines[10], matches(r'^#0 .*fatal_app\.dart'));
    expect(res.exitCode, 255);
  });
}
