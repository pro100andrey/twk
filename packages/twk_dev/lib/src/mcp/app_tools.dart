/// The tools of `twk mcp`: [appTools], which drive one twk app through
/// twk_driver's `Session` and answer with the screen after each action.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:twk/twk.dart' show ElementFinder;
import 'package:twk_core/twk_core.dart' show LocalAddress;
import 'package:twk_driver/twk_driver.dart';

import '../logs.dart' show formatLine;
import '../project.dart' show projectOf;
import 'jsonrpc.dart';

/// The tools that drive an app, sharing the one app they run: at most one
/// at a time.
List<McpTool> appTools({AppLauncher? launcher}) {
  final host = AppHost(launcher ?? const AppLauncher());
  return [
    _Tool(
      'start_app',
      'Starts a twk app in a pseudo-terminal and returns its first screen. '
          'The app runs on time the server moves: nothing in it fires until '
          'a tool moves the clock (press and type move it to the frame the '
          'input asked for, wait_for and elapse move it further). One app '
          'at a time; stop_app ends it.',
      {
        'program': _str("The app's main Dart file."),
        'arguments': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Arguments for the app.',
        },
        'width': _int('Columns of the terminal (80).'),
        'height': _int('Rows of the terminal (24).'),
      },
      required: ['program'],
      host.start,
    ),
    _Tool(
      'screen',
      'The screen as of the last frame, and where the app stands.',
      {},
      (_) => host.answer(),
    ),
    _Tool(
      'tree',
      "The app's widget tree as indented text: each node's type, id, key, "
          "size and properties. The ids are what a finder's `node` takes.",
      {
        'depth': _int(
          "Levels to show below the app's root; the whole tree when not "
          'given.',
        ),
      },
      host.tree,
    ),
    _Tool(
      'find',
      'The nodes a finder matches: type, id, key, text, and the cells it '
          'occupies on the screen.',
      {'finder': _finder},
      required: ['finder'],
      host.find,
    ),
    _Tool(
      'press',
      'Presses keys, as key bindings name them, apart by spaces '
          '("ctrl+s", "shift+tab", "g g", "enter"). Answers the screen of '
          'the frame that took the last key in. Pressing the key that quits '
          'ends the app: the answer says it exited and with which code.',
      {'keys': _str('The keys, e.g. "down down enter".')},
      required: ['keys'],
      (args) => host.act((s) => s.press(_text(args, 'keys'))),
    ),
    _Tool(
      'type',
      'Types text, as the characters in one write.',
      {'text': _str('The text.')},
      required: ['text'],
      (args) => host.act((s) => s.type(_text(args, 'text'))),
    ),
    _Tool(
      'tap',
      'Clicks the one node a finder matches, after checking that a click '
          'there reaches it: it fails saying what covers it, or that '
          'nothing there takes a click, rather than clicking nothing.',
      {'finder': _finder},
      required: ['finder'],
      (args) => host.act((s) => s.tap(_finderOf(args))),
    ),
    _Tool(
      'wait_for',
      "Moves the app's time on, timer to timer, until the screen has the "
          'text (or, with `absent`, no longer has it). It fails with the '
          'reason: "not within" the budget, with the timers that wait; or '
          '"never", at once, when the app is quiet and nothing will change '
          'the screen by itself (more waiting does not help). Real I/O (a '
          'socket, a file, a process) is invisible to the clock: pass '
          '`io_ms` to wait for it in real time.',
      {
        'text': _str('Text the screen is to have.'),
        'absent': _str('Text the screen is to no longer have.'),
        'budget_ms': _int("How far the app's time may move (10000)."),
        'io_ms': _int('Real milliseconds to wait for I/O in a quiet app.'),
      },
      host.waitFor,
    ),
    _Tool(
      'elapse',
      "Moves the app's time on by a span, firing the timers that fall in "
          'it, and answers the screen then.',
      {'ms': _int("Milliseconds of the app's time.")},
      required: ['ms'],
      host.elapse,
    ),
    _Tool(
      'hot_reload',
      "Reloads the app's sources and has it rebuild every widget, each "
          'State kept, as `twk run` does; answers the screen after. Fails '
          "with the compiler's reasons when the reload does.",
      {},
      (_) => host.hotReload(),
    ),
    _Tool(
      'logs',
      "The app's log records since the last call (or the start), as "
          '`twk logs` writes them.',
      {},
      (_) async => host.logs(),
    ),
    _Tool(
      'stop_app',
      'Ends the app and reports what it left behind (the terminal not '
          'back in cooked mode, the alternate screen not left, the cursor '
          'hidden) when it had exited by itself.',
      {},
      (_) => host.stop(),
    ),
  ];
}

int _intOf(JsonMap args, String name, int fallback) {
  final v = args[name];
  if (v == null) {
    return fallback;
  }
  if (v is int) {
    return v;
  }
  throw DriverError('"$name" is an integer');
}

String _text(JsonMap args, String name) {
  final v = args[name];
  if (v is String) {
    return v;
  }
  throw DriverError('"$name" is a string, and is needed');
}

ElementFinder _finderOf(JsonMap args) {
  try {
    return ElementFinder.fromJson(args['finder']);
  } on FormatException catch (e) {
    throw DriverError('"finder": ${e.message}');
  }
}

JsonMap _str(String description) => {
  'type': 'string',
  'description': description,
};

JsonMap _int(String description) => {
  'type': 'integer',
  'description': description,
};

final JsonMap _finder = {
  'type': 'object',
  'description':
      'A finder, as JSON: {"text": "Save"} (a Text whose whole text is '
      'that), {"textContaining": "ave"}, {"textMatches": {"source": '
      '"Sa.e", "caseSensitive": true}}, {"type": "Button"}, {"key": '
      '{"value": "ok"}}, {"node": 42} (an id from tree or find), '
      '{"descendant": <finder>, "of": <finder>}, {"ancestor": <finder>, '
      '"of": <finder>}, and {"first": <finder>}, {"last": <finder>}, '
      '{"at": 2, "of": <finder>} to pick among several. A finder that '
      'matches none or more than one node fails.',
};

final class _Tool implements McpTool {
  _Tool(
    this.name,
    this.description,
    JsonMap properties,
    this._run, {
    List<String> required = const [],
  }) : inputSchema = {
         'type': 'object',
         'properties': properties,
         if (required.isNotEmpty) 'required': required,
       };

  @override
  final String name;

  @override
  final String description;

  @override
  final JsonMap inputSchema;

  final Future<McpResult> Function(JsonMap args) _run;

  @override
  Future<McpResult> call(JsonMap arguments) async {
    try {
      return await _run(arguments);
    } on QuietApp catch (e) {
      // the driver's words are for a Dart caller: here the option is an
      // argument of the tool
      return McpResult.error(e.messageUsing('io_ms'));
    } on DriverError catch (e) {
      return McpResult.error(e.message);
    }
  }
}

/// How an app is started: a seam for a test's own ports.
class AppLauncher {
  /// The real one.
  const AppLauncher();

  /// The session of [spec], its VM service client given to [attached].
  Future<Session> start(
    ProcessSpec spec,
    void Function(VmAppClient client) attached,
  ) => Session.start(
    spec,
    timeout: const Duration(seconds: 90),
    ports: SessionPorts(
      connect: (uri) async {
        final service = await VmAppClient.connect(uri);
        final client = await VmAppClient.attach(service, '$uri');
        attached(client);
        return client;
      },
    ),
  );
}

/// The app the tools drive.
final class AppHost {
  /// A host that starts apps by [_launcher].
  AppHost(this._launcher);

  final AppLauncher _launcher;
  Session? _session;
  VmAppClient? _client;
  final _log = <String>[];
  Socket? _logSocket;
  var _generation = 0;

  Session _open() =>
      _session ??
      (throw const DriverError('no app is running: start_app starts one'));

  /// Starts the app [args] name and answers its first screen.
  Future<McpResult> start(JsonMap args) async {
    if (_session != null) {
      throw const DriverError(
        'an app is running already: stop_app ends it first',
      );
    }
    final program = p.normalize(p.absolute(_text(args, 'program')));
    if (!File(program).existsSync()) {
      throw DriverError('no such file: $program');
    }
    final arguments = args['arguments'];
    if (arguments != null &&
        !(arguments is List && arguments.every((a) => a is String))) {
      throw const DriverError('"arguments" is a list of strings');
    }
    final project = projectOf(p.dirname(program));
    final spec = ProcessSpec(
      program,
      arguments: [...?(arguments as List?)?.cast<String>()],
      workingDirectory: project,
      // the log is served (for `twk logs`, and for the logs tool)
      environment: {
        'TWK_DEBUG': {
          ...(Platform.environment['TWK_DEBUG'] ?? '').split(','),
          'logs',
        }.where((a) => a.isNotEmpty).join(','),
      },
      width: _intOf(args, 'width', 80),
      height: _intOf(args, 'height', 24),
    );
    final Session session;
    try {
      session = await _launcher.start(spec, (c) => _client = c);
    } on Object {
      _client = null;
      rethrow;
    }
    _session = session;
    _log.clear();
    unawaited(_follow(project, ++_generation));
    return answer();
  }

  /// Reads the app's log as it serves it, into [_log], until the app ends.
  Future<void> _follow(String project, int generation) async {
    final file = LocalAddress.fileOf('logs', project);
    final session = _session;
    for (var i = 0; i < 100 && generation == _generation; i++) {
      if (session == null || session.ended) {
        return;
      }
      final address = LocalAddress.read(file);
      if (address != null) {
        try {
          final socket = await address.connect();
          _logSocket = socket;
          socket.write('${address.token}\n');
          unawaited(socket.done.then<void>((_) {}, onError: (Object _) {}));
          await for (final line
              in utf8.decoder.bind(socket).transform(const LineSplitter())) {
            if (generation != _generation) {
              return;
            }
            _log.add(formatLine(line, color: false));
          }
          return;
        } on Object {
          // not served yet, or left behind by an app that ended
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// The log records since the last call.
  McpResult logs() {
    _open();
    final text = _log.isEmpty ? 'no log records' : _log.join('\n');
    _log.clear();
    return McpResult(text);
  }

  /// Ends the app and reports what it left behind.
  Future<McpResult> stop() async {
    final session = _open();
    final CloseReport report;
    try {
      report = await session.close();
    } finally {
      // a close that threw leaves nothing to stop again
      _forget();
    }
    final problems = report.problems.isEmpty
        ? ''
        : '\nleft behind: ${report.problems.join('; ')}';
    return McpResult(
      report.exitedByItself
          ? 'the app had exited (${report.exitCode})$problems'
          : 'the app was stopped',
    );
  }

  void _forget() {
    _generation++;
    unawaited(_logSocket?.close());
    _logSocket = null;
    _session = null;
    _client = null;
  }

  /// The screen of [step], and the line that says where the app stands.
  Future<McpResult> _after(Step step) =>
      _report(step.frame, step.screen, step.exit);

  Future<McpResult> _report(int frame, String text, ExitResult? exit) async {
    final session = _open();
    final screen = StringBuffer(text.trimRight());
    if (exit != null) {
      return McpResult(
        '$screen\n--\n${exit.message}; the screen is its last. '
        'stop_app reports what it left behind.',
      );
    }
    final status = await session.clock.status();
    return McpResult('$screen\n--\n${_line(frame, status)}');
  }

  static String _line(int frame, ClockStatus status) {
    final quiet = status.quiet;
    final String state;
    if (quiet == null) {
      state = 'not driven';
    } else if (quiet) {
      state =
          'quiet (no timer, no frame asked for; it will not change by '
          'itself)';
    } else {
      final next = status.nextDue;
      state = next == null
          ? 'not quiet (work in flight)'
          : 'not quiet (next timer in '
                '${((next - status.time) / 1e6).toStringAsFixed(3)} s)';
    }
    return 'frame $frame, input read ${status.inputRead} bytes, $state';
  }

  /// The screen now, and where the app stands.
  Future<McpResult> answer() async {
    final session = _open();
    if (session.ended) {
      final exit = await session.exitCode;
      return McpResult(
        '${session.screenText.trimRight()}\n--\nthe app exited ($exit)',
      );
    }
    return _report(session.frame, session.screenText, null);
  }

  /// Runs [action] on the session and answers the screen after it.
  Future<McpResult> act(Future<Step> Function(Session session) action) async {
    final session = _open();
    return _after(await action(session));
  }

  /// Moves the app's time until the screen is as [args] say.
  Future<McpResult> waitFor(JsonMap args) async {
    final session = _open();
    final text = args['text'];
    final absent = args['absent'];
    if ((text is String) == (absent is String)) {
      throw const DriverError('wait_for takes "text" or "absent", one');
    }
    final io = args['io_ms'];
    final step = await session.waitFor(
      text is String
          ? (screen) => screen.contains(text)
          : (screen) => !screen.contains(absent! as String),
      budget: Duration(milliseconds: _intOf(args, 'budget_ms', 10000)),
      io: io == null ? null : Duration(milliseconds: _intOf(args, 'io_ms', 0)),
      what: text is String ? 'screen with "$text"' : 'screen without "$absent"',
      near: text is String ? text : null,
    );
    return _after(step);
  }

  /// Moves the app's time on by [args]'s `ms`.
  Future<McpResult> elapse(JsonMap args) async {
    final session = _open();
    final ms = _intOf(args, 'ms', -1);
    if (ms < 0) {
      throw const DriverError('"ms" is a number of milliseconds, not negative');
    }
    if (!session.driven) {
      throw const DriverError("the app does not run on the server's time");
    }
    final status = await session.clock.advance(Duration(milliseconds: ms));
    return _after(await _caughtUp(session, status.frame));
  }

  /// The step of the app once it has run [frame], as the server has seen it.
  Future<Step> _caughtUp(Session session, int frame) => session.waitFor(
    (_) => session.frame >= frame,
    what: 'frame $frame',
    budget: const Duration(seconds: 1),
  );

  /// Reloads the app's sources and has it reassemble.
  Future<McpResult> hotReload() async {
    final session = _open();
    final client = _client!;
    final before = session.frame;
    final report = await client.vm('reloadSources');
    if (report['success'] != true) {
      final notices = report['notices'];
      final reasons = [
        if (notices is List)
          for (final n in notices)
            if (n is Map && n['message'] is String) n['message'] as String,
      ].join('\n');
      throw DriverError(
        'hot reload failed${reasons.isEmpty ? '' : ':\n$reasons'}',
      );
    }
    final answer = await client.call('reassemble');
    final frame = answer['frame'] as int? ?? before;
    final due = answer['frameDue'] as int?;
    var step = await _caughtUp(session, frame);
    if (due != null && session.driven) {
      final status = await session.clock.advanceTo(due);
      step = await _caughtUp(session, status.frame);
    }
    final details = report['details'];
    final loaded = details is Map ? details['loadedLibraryCount'] : null;
    final result = await _after(step);
    return McpResult(
      'hot reload: ${loaded ?? '?'} libraries loaded\n${result.text}',
    );
  }

  /// The nodes the finder of [args] matches.
  Future<McpResult> find(JsonMap args) async {
    final session = _open();
    final found = await session.find(_finderOf(args));
    if (found.isEmpty) {
      return const McpResult('no node matches');
    }
    return McpResult(
      [
        '${found.length} ${found.length == 1 ? 'node' : 'nodes'}:',
        for (final f in found) _described(f),
      ].join('\n'),
    );
  }

  static String _described(Found f) {
    final cells = f.rect == null ? 'not laid out' : 'cells ${f.rect}';
    return '${f.describe}, $cells${f.shown == null ? ', not shown' : ''}';
  }

  /// The widget tree, to the depth of [args].
  Future<McpResult> tree(JsonMap args) async {
    _open();
    final depth = args['depth'];
    if (depth != null && (depth is! int || depth < 0)) {
      throw const DriverError('"depth" is a number of levels, not negative');
    }
    final answer = await _client!.call('tree');
    final root = answer['root'];
    if (root is! Map<String, Object?>) {
      return const McpResult('the app has drawn no frame: no tree yet');
    }
    final app = answer['app'];
    final start = (app is int ? _byId(root, app) : null) ?? root;
    final out = StringBuffer();
    _write(out, start, 0, depth as int?);
    return McpResult(out.toString().trimRight());
  }

  static Map<String, Object?>? _byId(Map<String, Object?> node, int id) {
    if (node['id'] == id) {
      return node;
    }
    for (final c in node['children'] as List<Object?>? ?? const []) {
      if (c is Map<String, Object?>) {
        final found = _byId(c, id);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }

  static void _write(StringBuffer out, JsonMap node, int level, int? depth) {
    final key = node['key'];
    final size = node['size'];
    final props = [
      for (final prop in node['properties'] as List<Object?>? ?? const [])
        if (prop is Map && prop['name'] != null)
          '${prop['name']}${prop['value'] == null ? '' : '=${prop['value']}'}',
    ];
    out
      ..write('  ' * level)
      ..write('${node['name']} #${node['id']}')
      ..write(key == null ? '' : ' [$key]')
      ..write(size is Map ? ' ${size['width']}x${size['height']}' : '')
      ..writeln(props.isEmpty ? '' : '  ${props.join(', ')}');
    final children = node['children'] as List<Object?>? ?? const [];
    if (depth != null && level >= depth) {
      if (children.isNotEmpty) {
        out
          ..write('  ' * (level + 1))
          ..writeln('... ${children.length} more below');
      }
      return;
    }
    for (final c in children) {
      if (c is Map<String, Object?>) {
        _write(out, c, level + 1, depth);
      }
    }
  }
}
