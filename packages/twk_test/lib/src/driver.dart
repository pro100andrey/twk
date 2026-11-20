/// [driverTest]: tests of a twk app as a real process in a pseudo-terminal,
/// with the finders and matchers of [testTwk].
///
/// @docImport 'matchers.dart';
/// @docImport 'tester.dart';
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:meta/meta.dart' show isTest, visibleForTesting;
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart' show KeyEvent, MouseEvent;
import 'package:twk_driver/twk_driver.dart';

import '../vt.dart';
import 'driver_screen.dart';
import 'finders.dart';
import 'screen_text.dart';

// Examples can assume:
// import 'package:test/test.dart';

/// How a terminal presents itself to the app a test starts, by a name: the
/// environment the app reads its colors from (`TERM`, `COLORTERM`,
/// `NO_COLOR`). `start` and `driverTest(profiles:)` take these names.
const terminalProfiles = {
  'truecolor': {
    'TERM': 'xterm-256color',
    'COLORTERM': 'truecolor',
    'NO_COLOR': '',
  },
  '256 colors': {'TERM': 'xterm-256color', 'COLORTERM': '', 'NO_COLOR': ''},
  '16 colors': {'TERM': 'xterm', 'COLORTERM': '', 'NO_COLOR': ''},
  'no color': {'TERM': 'xterm', 'COLORTERM': '', 'NO_COLOR': '1'},
};

/// The environment of the profile [name] of [terminalProfiles]; an
/// [ArgumentError] naming them for an unknown one.
Map<String, String> profileEnvironment(String name) =>
    terminalProfiles[name] ??
    (throw ArgumentError.value(
      name,
      'profile',
      'one of ${terminalProfiles.keys.map((n) => "'$n'").join(', ')}',
    ));

/// Tests an app that runs as a process in a pseudo-terminal: [body] starts
/// it with [DriverTester.start] and drives it as a user does, input as the
/// terminal's bytes, each action returning once the app has drawn the frame
/// that took it in, the screen read through an emulator. Where [testTwk]
/// runs the app in the test's process on a fake clock, this runs the real
/// program, its real terminal setup and exit included, on driven time by
/// default (the app's clock stands until the test moves it).
///
/// ```dart
/// driverTest('saving shows it', (d) async {
///   final app = await d.start('bin/main.dart', size: (60, 12));
///   await app.press('ctrl+n');
///   await app.tap(find.text('Save'));
///   expect(app.screen, containsLine('Saved'));
///   final step = await app.press('q');
///   expect(step.exit!.code, 0);
/// }, tags: 'process');
/// ```
///
/// What a test of the app checks beyond its own expectations, where [body]
/// returns: every app started is ended (a running one is killed), what the
/// emulator of the strict [Vt] could not take of its output fails the test
/// (an unknown sequence, a print that wraps or scrolls, a synchronized
/// update left open), and an app that exited by itself is held to the
/// terminal it was given back: cooked mode, the alternate screen left, the
/// cursor visible.
///
/// A test that fails prints, for each app, its screen, its last
/// [framesOnFailure] frames that changed it, its widget tree and what the
/// strict emulator could not take, and the path of its trace: the app's
/// output as an asciicast with a marker for each step (`.cast`, which
/// `twk play` plays) and a line for each step (`.trace.jsonl`: the action,
/// the covered target of a tap, the frames, the tree), under
/// `.dart_tool/twk_test/traces/`. A test that passes deletes them.
///
/// With [profiles], the test runs once for each name of
/// the keys of [terminalProfiles] given, `description [name]`, `start` taking
/// that profile unless it names another.
@isTest
void driverTest(
  String description,
  FutureOr<void> Function(DriverTester d) body, {
  List<String>? profiles,
  int framesOnFailure = 3,
  Timeout? timeout,
  Object? skip,
  Object? tags,
}) {
  for (final name in profiles ?? const <String?>[null]) {
    if (name != null) {
      profileEnvironment(name);
    }
    test(
      name == null ? description : '$description [$name]',
      () =>
          runDriverTest(body, profile: name, framesOnFailure: framesOnFailure),
      timeout: timeout,
      skip: skip,
      tags: tags,
    );
  }
}

/// What [driverTest] runs for a test: [body] with a tester, then the checks
/// of what it started, or the report of why it failed.
@visibleForTesting
Future<void> runDriverTest(
  FutureOr<void> Function(DriverTester d) body, {
  String? profile,
  int framesOnFailure = 3,
}) async {
  final d = DriverTester._(profile, framesOnFailure);
  try {
    await body(d);
  } on Object {
    await d._report();
    await d._end(check: false);
    rethrow;
  }
  final problems = await d._end(check: true);
  if (problems.isNotEmpty) {
    await d._report();
    fail(problems.join('\n'));
  }
  d._deleteTraces();
}

/// What a [driverTest]'s body starts apps with.
final class DriverTester {
  DriverTester._(this._profile, this._framesOnFailure);

  final String? _profile;

  /// The profile this test runs with ([driverTest]'s `profiles`); null
  /// for none.
  String? get profile => _profile;

  final int _framesOnFailure;
  final _apps = <DriverApp>[];

  /// The apps started so far, in order.
  List<DriverApp> get apps => List.unmodifiable(_apps);

  /// Starts [program], a Dart file (compiled to a kernel once for the runs
  /// after, `.dart_tool/twk_test/programs`) or a kernel, with [arguments]
  /// in a terminal of [size] (columns, rows), and returns once the app has
  /// drawn its first frame.
  ///
  /// [profile] is one of the keys of [terminalProfiles] (the test's own by
  /// default, else none: the terminal the test runs in), [env] more
  /// environment over it. [driven] is on by default: the app's time stands
  /// until the test moves it ([DriverApp.clock], [DriverApp.waitFor]); off,
  /// the app runs on real time and only the waits that take `io` are of
  /// use. An app that draws inline, in the normal screen, says so with
  /// [inline], the emulator that checks its output being one with a
  /// scrollback. [timeout] bounds each wait for the app's answer, in real
  /// time.
  Future<DriverApp> start(
    String program, {
    List<String> arguments = const [],
    (int, int) size = (80, 24),
    String? profile,
    Map<String, String> env = const {},
    bool driven = true,
    bool inline = false,
    String? workingDirectory,
    DateTime? startTime,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final named = profile ?? _profile;
    final spec = ProcessSpec(
      await _kernelOf(program),
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: {if (named != null) ...profileEnvironment(named), ...env},
      width: size.$1,
      height: size.$2,
    );
    final checked = CheckedScreen(size.$1, size.$2, inline: inline);
    final traceName =
        '${File(program).uri.pathSegments.last}-$pid-${_traces++}';
    AppServicePort? service;
    final session = await Session.start(
      spec,
      timeout: timeout,
      driven: driven,
      startTime: startTime,
      trace: TraceOptions(
        '.dart_tool/twk_test/traces/$traceName',
        profile: named,
      ),
      ports: SessionPorts(
        screen: (_, _) => checked,
        connect: (uri) async {
          final vm = await VmAppClient.connect(uri);
          return service = await VmAppClient.attach(vm, '$uri');
        },
      ),
    );
    final app = DriverApp._(session, service!, checked, _framesOnFailure);
    _apps.add(app);
    return app;
  }

  Future<void> _report() async {
    for (final (i, app) in _apps.indexed) {
      printOnFailure(await app.describeState(title: 'app ${i + 1}'));
    }
  }

  void _deleteTraces() {
    for (final app in _apps) {
      app.session.trace?.delete();
    }
  }

  /// Ends every app; the problems of what they left behind when [check].
  Future<List<String>> _end({required bool check}) async {
    final problems = <String>[];
    for (final (i, app) in _apps.indexed) {
      final report = await app.close();
      if (check) {
        for (final problem in report) {
          problems.add('app ${i + 1}: $problem');
        }
      }
    }
    return problems;
  }
}

final _kernels = <String, Future<String>>{};

var _traces = 0;

/// The kernel of [program] where it is a Dart file, compiled once per
/// process; [program] as it is otherwise.
Future<String> _kernelOf(String program) {
  if (!program.endsWith('.dart')) {
    return Future.value(program);
  }
  return _kernels.putIfAbsent(File(program).absolute.path, () async {
    final config = await Isolate.packageConfig;
    if (config == null) {
      throw StateError('no package configuration to compile $program with');
    }
    return compiledProgram(
      program,
      packages: config.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    );
  });
}

/// The frame emulator of a driven app's session with the strict [Vt] beside
/// it, fed the same bytes: what the app wrote that a terminal would not
/// take ([problems]). Internal to [driverTest].
final class CheckedScreen implements ScreenPort {
  /// A screen of [width] by [height] cells; [inline] for an app that draws
  /// in the normal screen (line feeds taken, a scrollback kept).
  CheckedScreen(int width, int height, {this.inline = false})
    : vt = Vt(
        width,
        height,
        strict: false,
        allowLineFeed: inline,
        lineFeedOnNormalScreen: true,
        scrollback: inline,
        relativeOnly: inline,
      ) {
    _inner = EmulatorScreen(
      width: width,
      height: height,
      checker: vt.feed,
    );
  }

  /// Whether the app draws in the normal screen.
  final bool inline;

  /// The strict emulator of the app's frames.
  final Vt vt;

  late final EmulatorScreen _inner;

  /// What the strict emulator could not take, and what the app left open;
  /// [ended] where it exited by itself, which an update left open is only
  /// a failure of.
  List<String> problems({required bool ended}) => [
    ...vt.errors,
    if (ended && vt.syncDepth != 0)
      'the app ended inside a synchronized update (DEC 2026 left open)',
  ];

  @override
  void answerTo(void Function(Uint8List bytes)? sink) => _inner.answerTo(sink);

  @override
  void feedAnswering(List<int> bytes) => _inner.feedAnswering(bytes);

  @override
  void feedFrame(List<int> bytes) => _inner.feedFrame(bytes);

  @override
  ScreenView get frame => _inner.frame;

  @override
  Uint8List encodeKey(KeyEvent key) => _inner.encodeKey(key);

  @override
  Uint8List encodeText(String text) => _inner.encodeText(text);

  @override
  Uint8List encodePaste(String text) => _inner.encodePaste(text);

  @override
  Uint8List encodeMouse(MouseEvent event) => _inner.encodeMouse(event);

  @override
  bool get mouseTracked => _inner.mouseTracked;

  @override
  void resizeAnswering(int width, int height) =>
      _inner.resizeAnswering(width, height);

  @override
  void resizeFrame(int width, int height) {
    _inner.resizeFrame(width, height);
    if (inline) {
      vt.resizeKeeping(width, height);
    } else {
      vt.resize(width, height);
    }
  }
}

/// An app a [DriverTester] started: input in, the screen and the tree out.
final class DriverApp {
  DriverApp._(this.session, this._service, this._checked, this._keep)
    : screen = DriverScreen(_checked.vt) {
    _remember(session.frame, session.screenText);
  }

  /// The driver's session of the app, for what this class does not give.
  final Session session;

  final AppServicePort _service;
  final CheckedScreen _checked;
  final int _keep;
  final _recent = <(int, String)>[];

  /// The screen of the app as the last frame it drew shows it, for the
  /// matchers of the screen (`containsLine`, `hasTextAt`, `styleAt`,
  /// `cursorAt`, `matchesScreen`).
  final DriverScreen screen;

  /// The screen as text, one line to a row.
  String get text => session.screenText;

  /// The app's clock: where it stands and the moves of a driven app's time
  /// ([ClockControl.advance]).
  ClockControl get clock => session.clock;

  /// The exit code, once the app has ended.
  Future<int?> get exitCode => session.exitCode;

  /// Whether the app has ended.
  bool get ended => session.ended;

  void _remember(int frame, String screen) {
    if (_recent.isNotEmpty && _recent.last.$2 == screen) {
      return;
    }
    _recent.add((frame, screen));
    if (_recent.length > _keep + 1) {
      _recent.removeAt(0);
    }
  }

  Future<Step> _noted(Future<Step> step) async {
    final done = await step;
    _remember(done.frame, done.screen);
    return done;
  }

  /// Presses [keys], as key bindings name them, apart by spaces
  /// (`ctrl+s`, `shift+tab`, `g g`), and returns once the app has drawn the
  /// frame of the last. `press('q')` of an app that quits waits for its
  /// exit: the step has it as `exit`.
  Future<Step> press(String keys) => _noted(session.press(keys));

  /// Types [text], as the bytes of its characters.
  Future<Step> type(String text) => _noted(session.type(text));

  /// Pastes [text], bracketed when the app asked for it.
  Future<Step> paste(String text) => _noted(session.paste(text));

  /// Sets the terminal's size ([width] columns, [height] rows) and returns
  /// once the app has drawn a frame at it.
  Future<Step> resize(int width, int height) =>
      _noted(session.resize(width, height));

  /// Clicks the one widget [finder] finds, after checking that a click on
  /// its middle reaches it (it is shown, nothing covers it, something
  /// there takes a click). A [DriverError] naming why when it does not.
  Future<Step> tap(Finder finder) =>
      _noted(session.tap(elementFinderOf(finder)));

  /// The widgets [finder] finds in the app's tree, in its order, asked of
  /// the app (`ext.twk.find`). A [Finder] of [Finders.byWidgetPredicate]
  /// stays in the test's process and cannot be asked.
  Future<List<Found>> find(Finder finder) =>
      session.find(elementFinderOf(finder));

  /// The one widget [finder] finds; a [DriverError] for none or several
  /// (`first`, `last` and `at` of the finder pick on purpose).
  Future<Found> findOne(Finder finder) =>
      session.findOne(elementFinderOf(finder));

  /// The cells the one widget [finder] finds takes, for the matchers'
  /// `withinRect`.
  Future<CellRect> rect(Finder finder) async {
    final found = await findOne(finder);
    final r =
        found.rect ?? (throw DriverError('${found.describe} is not laid out'));
    return (x: r.x, y: r.y, width: r.width, height: r.height);
  }

  /// The app's widget tree as text, to [depth] levels when given.
  Future<String> tree({int? depth}) async =>
      treeText(await _service.call('tree'), depth: depth);

  /// Waits until [test] accepts the screen of a frame (as text), the one
  /// shown now first. On a driven app it moves the app's time itself, from
  /// timer to timer, until it has moved [budget]: it fails with "not
  /// within" and the timers that wait, or at once with "never" when the app
  /// is quiet and nothing will change the screen. Real I/O in flight is
  /// invisible to the app's clock: [io] waits for it, in real time. [near]
  /// is a text the failure names the closest line to. See
  /// [Session.waitFor].
  Future<Step> waitFor(
    bool Function(String screen) test, {
    Duration budget = const Duration(seconds: 10),
    Duration? io,
    String what = 'the screen',
    String? near,
  }) => _noted(
    session.waitFor(test, budget: budget, io: io, what: what, near: near),
  );

  /// Waits until the number of widgets [finder] finds is what [count]
  /// ([findsOneWidget] by default, [findsNothing], [findsWidgets],
  /// [findsNWidgets]) expects, looking at the app's tree at each frame it
  /// draws, and returns what it found. [budget], [io] and the failures
  /// ("not within", "never") are as for [waitFor].
  Future<List<Found>> waitForFinder(
    Finder finder, {
    Matcher count = findsOneWidget,
    Duration budget = const Duration(seconds: 10),
    Duration? io,
  }) async {
    final ask = elementFinderOf(finder);
    final what =
        '${finder.description} to be found, expecting '
        '${findsCountDescribed(count)}';
    final begun = (await session.clock.status()).time;
    while (true) {
      final seen = session.frame;
      final found = await session.find(ask);
      if (findsCountAdmits(count, found.length)) {
        return found;
      }
      final moved = (await session.clock.status()).time - begun;
      final left = budget - Duration(microseconds: moved);
      if (left <= Duration.zero) {
        throw DriverError(
          'no $what within ${budget.inMilliseconds} ms of app time; it found '
          '${found.length}. Screen at frame ${session.frame}:\n$text',
        );
      }
      final step = await session.waitFor(
        (_) => session.frame != seen,
        budget: left,
        io: io,
        what: what,
      );
      _remember(step.frame, step.screen);
      if (session.ended) {
        throw DriverError('the app ended before $what');
      }
    }
  }

  /// What the report of a failed test says of the app: [title], its screen,
  /// the last frames that changed it, its tree and what the strict emulator
  /// could not take.
  @visibleForTesting
  Future<String> describeState({String title = 'app'}) async {
    final out = StringBuffer('$title: ${ended ? 'ended' : 'running'}\n')
      ..writeln('screen ${screen.vt.width}×${screen.vt.height}:')
      ..writeln(describeScreen(screen.vt));
    final earlier = _recent.length > 1
        ? _recent.sublist(0, _recent.length - 1)
        : const <(int, String)>[];
    for (final (frame, text) in earlier) {
      out
        ..writeln('earlier, at frame $frame:')
        ..writeln(text.trimRight());
    }
    out.writeln('widget tree:');
    if (ended) {
      out.writeln('none: the app ended');
    } else {
      try {
        out.writeln(await tree().timeout(const Duration(seconds: 5)));
      } on Object catch (e) {
        out.writeln('not read: $e');
      }
    }
    final log = session.log;
    if (log.isNotEmpty) {
      out
        ..writeln('last log records:')
        ..writeln(log.join('\n'));
    }
    if (session.trace case final trace?) {
      out
        ..writeln('trace, the cast with a marker for each step:')
        ..writeln('  ${trace.castPath}')
        ..writeln('  ${trace.tracePath}');
    }
    final problems = _checked.problems(ended: ended);
    if (problems.isNotEmpty) {
      out
        ..writeln('what the strict emulator could not take:')
        ..writeln(problems.map((p) => '  $p').join('\n'));
    }
    return out.toString();
  }

  /// Ends the app if it still runs and returns what it did wrong: what the
  /// strict emulator could not take of its output, and, where it exited by
  /// itself, what it left of the terminal (see [Session.close]).
  Future<List<String>> close() async {
    final report = await session.close();
    return [
      ..._checked.problems(ended: report.exitedByItself),
      ...report.problems,
    ];
  }
}
