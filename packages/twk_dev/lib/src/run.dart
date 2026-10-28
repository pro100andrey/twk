/// `twk run`: [RunCommand], and [HotRunner], which runs an app with hot
/// reload.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:twk_core/twk_core.dart' show LocalAddress;
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';

import 'app_client.dart';
import 'project.dart';

/// `twk run`: runs an app with hot reload ([HotRunner]) in this terminal,
/// which the app has to itself.
final class RunCommand extends Command<int> {
  /// `twk run`; [started] is given the runner of each run of the command
  /// before it starts the app.
  RunCommand({this.started});

  /// What is given the [HotRunner] of a run before it starts the app: what
  /// watches it, as a test waits for [HotRunner.reloadsHeld]. Null, nothing
  /// is.
  final void Function(HotRunner runner)? started;

  // what follows the file is the app's
  @override
  final argParser = ArgParser(allowTrailingOptions: false);

  @override
  String get name => 'run';

  @override
  String get invocation => 'twk run <file> [<arguments>...]';

  @override
  String get description =>
      'Run an app with hot reload, in this terminal.\n\n'
      'Starts the app in <file> with the VM service, the arguments after '
      'it its own, and leaves it this terminal. Watches the lib/ of the '
      'package <file> is in and <file>: when a .dart file changes, reloads '
      'the sources and has the app rebuild every widget, each State kept. '
      'In the app Ctrl+G h reloads and Ctrl+G H restarts it; what a reload '
      "did goes to the app's log, its console opening when it failed. "
      "Ends when the app does, with the app's exit code. While the app "
      'runs, the address of its VM service is in the .dart_tool/twk/run '
      'of the project of the current directory, where `twk inspect` finds '
      'it.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('No file to run.');
    }
    final file = rest.first;
    if (!File(file).existsSync()) {
      stderr.writeln('twk run: no file $file');
      return 1;
    }
    final runner = HotRunner(file, rest.sublist(1));
    started?.call(runner);
    return runner.run();
  }
}

/// Runs the app in [entry] with [arguments] in a process of its own, with
/// the VM service on, and hot reloads it until it ends.
///
/// The app has the terminal: its stdin, stdout and stderr are this
/// process's, which writes nothing to them while the app runs. What it
/// says goes to the app's log instead (`ext.twk.log`): an error opens the
/// app's console. The app's debug keys are on (`TWK_DEBUG=keys`).
///
/// When a `.dart` file in the `lib/` of the package [entry] is in, or
/// [entry] itself, changes ([debounce] after the last change), or the app
/// asks for it (Ctrl+G h, the event `twk.reload`), the sources are
/// reloaded (`reloadSources`) and the app rebuilds and repaints all of
/// itself (`ext.twk.reassemble`), its states kept. Code that a reload can't
/// change — `main`, what ran already — takes a restart: Ctrl+G H (the
/// event `twk.restart`) ends the app (SIGTERM, which has it put the
/// terminal back, then SIGKILL after [patience]) and starts it again.
///
/// The WebSocket address of the VM service of the app running is in
/// [serviceFile], a line, for `twk inspect`; the file goes once the last
/// app has ended, unless another `twk run` wrote it since.
final class HotRunner {
  /// A runner of the app whose `main` is in the file [entry], given
  /// [arguments].
  HotRunner(String entry, this.arguments)
    : entry = p.normalize(p.absolute(entry)),
      package = projectOf(p.dirname(entry)),
      serviceFile = serviceFileOf(projectOf(null));

  /// The file of the app's `main`, absolute.
  final String entry;

  /// The app's command line arguments.
  final List<String> arguments;

  /// The directory of the package [entry] is in.
  final String package;

  /// Where the address of the app's VM service is while it runs:
  /// [serviceFileOf] the project of the current directory.
  final String serviceFile;

  // the address written to the service file, until it is removed
  String? _published;

  /// How long after the last change of a file the sources are reloaded.
  static const debounce = Duration(milliseconds: 100);

  /// How long an app is given to end before it is killed.
  static const patience = Duration(seconds: 5);

  /// How often the VM's service info is looked for while the app starts.
  static const _poll = Duration(milliseconds: 50);

  // the app running, null between two
  _App? _app;

  // the app is to be restarted
  var _restart = Completer<void>();

  // the exit code this process ends with once the app ended: 128 and the
  // signal that stops it
  int? _stopping;

  Timer? _debounced;

  // a reload runs; another one is wanted after it
  var _reloading = false;
  var _again = false;

  // a reload was asked for while no app had a binding to take it: the
  // next one to register the binding's extensions gets it, since what
  // changed may be newer than the sources it was compiled from
  var _pending = false;

  /// An event each time a reload was asked for — a file changed
  /// ([debounce] after the last change), or the app asked — while no app
  /// had a binding to take it: the reload is held for the next app whose
  /// binding registers its extensions, since what changed may be newer
  /// than the sources that app was compiled from. For what has to know
  /// that a change was seen before an app could take it, as a test does;
  /// closed once [run] has ended.
  Stream<void> get reloadsHeld => _held.stream;
  final _held = StreamController<void>.broadcast();

  /// The pid of the app running, or starting: null before the first and
  /// between two. For what has to know which process the app is, as a
  /// test that checks it ended does.
  int? get appPid => _app?.process.pid;

  /// Runs the app, starting it again when asked, until it ends, this
  /// process is stopped or [stop] is called; returns the app's exit code,
  /// or 128 and the number of the signal that stopped this process (143,
  /// SIGTERM's, after [stop]). Called again, returns what the first call
  /// does.
  Future<int> run() => _ran ??= _run();
  Future<int>? _ran;

  /// Ends the app this runs, or is starting, as SIGTERM sent to this
  /// process does — SIGTERM to the app, then SIGKILL after [patience] —
  /// and completes once [run] has ended, the app with it. Before [run],
  /// [run] then starts no app and returns 143.
  ///
  /// It ends the process this runner started for the app, through its
  /// [Process], and nothing else: a test's tear-down calls it to leave no
  /// app running, however the test ended.
  Future<void> stop() async {
    _stop(128 + 15);
    await _ran;
  }

  Future<int> _run() async {
    final temp = await Directory.systemTemp.createTemp('twk_run_');
    final info = File(p.join(temp.path, 'service.json'));
    final watches = _watch();
    final signals = [
      for (final (signal, number) in [
        (ProcessSignal.sigint, 2),
        (ProcessSignal.sighup, 1),
        if (!Platform.isWindows) (ProcessSignal.sigterm, 15),
      ])
        signal.watch().listen((_) => _stop(128 + number)),
    ];
    try {
      while (_stopping == null) {
        final app = _app = await _start(info);
        if (_stopping != null) {
          // stopped while it started, when there was no app to end
          unawaited(_end(app.process));
        }
        final restart = _restart = Completer<void>();
        final code = await Future.any<int?>([
          app.process.exitCode,
          restart.future.then((_) => null),
        ]);
        if (restart.isCompleted) {
          await _end(app.process);
        }
        _app = null;
        await app.close();
        if (code != null && !restart.isCompleted) {
          // a signal that ended the app as a shell gives it
          return _stopping ?? (code < 0 ? 128 - code : code);
        }
      }
      return _stopping!;
    } finally {
      _debounced?.cancel();
      for (final s in [...watches, ...signals]) {
        await s.cancel();
      }
      _unpublish();
      await temp.delete(recursive: true);
      await _held.close();
    }
  }

  /// Starts the app, its VM service's address going to [info], and
  /// connects to the service in the background.
  Future<_App> _start(File info) async {
    if (info.existsSync()) {
      info.deleteSync();
    }
    final debug = {
      ...(Platform.environment['TWK_DEBUG'] ?? '').split(','),
      'keys',
    }..remove('');
    final process = await Process.start(
      _dart,
      [
        'run',
        '--enable-vm-service=0',
        '--no-serve-devtools',
        // no word of the service on the app's terminal
        '-DSILENT_VM_SERVICE=true',
        '--write-service-info=${info.uri}',
        entry,
        ...arguments,
      ],
      mode: ProcessStartMode.inheritStdio,
      environment: {'TWK_DEBUG': debug.join(',')},
    );
    final app = _App(process);
    unawaited(_connect(app, info));
    return app;
  }

  /// The `dart` command this one runs on, or the one on the PATH.
  static String get _dart {
    final vm = Platform.resolvedExecutable;
    return p.basenameWithoutExtension(vm) == 'dart' ? vm : 'dart';
  }

  /// Connects to [app]'s VM service once it says where it listens in
  /// [info], and listens for the service extensions its isolates register
  /// and the events it posts.
  Future<void> _connect(_App app, File info) async {
    Uri? uri;
    while (uri == null && !app.ended) {
      try {
        final json =
            jsonDecode(info.readAsStringSync()) as Map<String, Object?>;
        uri = Uri.parse(json['uri']! as String);
      } on Object {
        // not written yet, or not all of it
        await Future<void>.delayed(_poll);
      }
    }
    if (uri == null) {
      return;
    }
    // the address twk inspect connects to, as VmAppClient.connect makes it
    _publish('${convertToWebSocketUrl(serviceProtocolUrl: uri)}');
    try {
      final service = app.service = await VmAppClient.connect(uri)
        ..onExtensionEvent.listen((event) {
          switch (event.extensionKind) {
            case 'twk.reload':
              unawaited(_reload());
            case 'twk.restart' when !_restart.isCompleted:
              _restart.complete();
          }
        });
      await service.streamListen(EventStreams.kExtension);
      // for as long as the service is there
      await watchExtensions(service, (id, rpc) => _added(app, id, rpc));
    } on Object {
      // the app ended meanwhile
    }
  }

  /// Writes [address] to [serviceFile], whole or not at all.
  void _publish(String address) {
    final file = File(serviceFile)..parent.createSync(recursive: true);
    File('${file.path}.$pid')
      ..writeAsStringSync('$address\n')
      ..renameSync(file.path);
    _published = address;
  }

  /// Removes [serviceFile] if it has the address written last.
  void _unpublish() {
    final address = _published;
    _published = null;
    final file = File(serviceFile);
    try {
      if (address != null && file.readAsStringSync().trim() == address) {
        file.deleteSync();
      }
    } on FileSystemException {
      // gone already
    }
  }

  /// The isolate [id] of [app] registered the service extension [rpc]:
  /// the binding's isolate is the one reloaded, and is told what this
  /// does.
  void _added(_App app, String id, String rpc) {
    switch (rpc) {
      case 'ext.twk.reassemble':
        app.isolate = id;
        if (_pending) {
          _pending = false;
          unawaited(_reload());
        }
      case 'ext.twk.log':
        unawaited(
          app.log(
            'hot reload: watching ${_shown(p.join(package, 'lib'))} and '
            '${_shown(entry)}; Ctrl+G h reloads, Ctrl+G H restarts',
          ),
        );
    }
  }

  /// [path] relative to the current directory when it is in it.
  static String _shown(String path) =>
      p.isWithin(p.current, path) ? p.relative(path) : path;

  /// Watches the `lib/` of [package], and [entry]: a change of a `.dart`
  /// file reloads the sources [debounce] after the last one.
  List<StreamSubscription<FileSystemEvent>> _watch() {
    final lib = Directory(p.join(package, 'lib'));
    bool dart(String path) => path.endsWith('.dart');
    bool isEntry(String path) => p.equals(path, entry);
    return [
      if (lib.existsSync())
        lib.watch(recursive: true).listen((e) {
          if (dart(e.path) || dart(_destination(e))) {
            _changed();
          }
        }),
      if (!lib.existsSync() || !p.isWithin(lib.path, entry))
        Directory(p.dirname(entry)).watch().listen((e) {
          if (isEntry(e.path) || isEntry(_destination(e))) {
            _changed();
          }
        }),
    ];
  }

  static String _destination(FileSystemEvent e) =>
      e is FileSystemMoveEvent ? e.destination ?? '' : '';

  void _changed() {
    _debounced?.cancel();
    _debounced = Timer(debounce, () => unawaited(_reload()));
  }

  /// Reloads the sources of the app, one reload at a time: one asked for
  /// meanwhile runs after it.
  Future<void> _reload() async {
    if (_reloading) {
      _again = true;
      return;
    }
    _reloading = true;
    try {
      do {
        _again = false;
        await _reloadOnce();
      } while (_again);
    } finally {
      _reloading = false;
    }
  }

  Future<void> _reloadOnce() async {
    final app = _app;
    final service = app?.service;
    final isolate = app?.isolate;
    if (app == null || service == null || isolate == null) {
      _pending = true;
      if (!_held.isClosed) {
        _held.add(null);
      }
      return;
    }
    final time = Stopwatch()..start();
    try {
      final report = await service.reloadSources(isolate);
      if (report.success != true) {
        await app.log(
          'hot reload failed',
          level: 'error',
          error: _reasons(report),
        );
        return;
      }
      await service.callServiceExtension(
        'ext.twk.reassemble',
        isolateId: isolate,
      );
      final details = report.json?['details'];
      final loaded = details is Map ? details['loadedLibraryCount'] : null;
      await app.log(
        'hot reload: ${loaded == 1 ? '1 library' : '$loaded libraries'} '
        'in ${time.elapsedMilliseconds} ms',
      );
    } on Object {
      // the app went away meanwhile
    }
  }

  /// Why the reload [report] failed: the messages of its notices, the
  /// compiler's errors.
  static String _reasons(ReloadReport report) {
    final notices = report.json?['notices'];
    return [
      if (notices is List)
        for (final notice in notices)
          if (notice is Map && notice['message'] is String)
            notice['message'] as String,
    ].join('\n');
  }

  /// Stops this process with [code] once the app has ended.
  void _stop(int code) {
    _stopping ??= code;
    final app = _app;
    if (app != null) {
      unawaited(_end(app.process));
    }
  }

  /// Ends [process]: SIGTERM, then SIGKILL after [patience].
  static Future<void> _end(Process process) async {
    process.kill();
    try {
      await process.exitCode.timeout(patience);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }
}

/// An app [HotRunner] started, and its VM service once connected.
final class _App {
  _App(this.process) {
    unawaited(process.exitCode.then((_) => ended = true));
  }

  final Process process;

  var ended = false;

  VmService? service;

  /// The isolate of the binding, which registered its service extensions
  /// (`ext.twk.*`), once it did: the one reloaded.
  String? isolate;

  /// Adds the record [message] to the app's log, at [level], with [error].
  Future<void> log(
    String message, {
    String level = 'info',
    String? error,
  }) async {
    try {
      await service!.callServiceExtension(
        'ext.twk.log',
        isolateId: isolate,
        args: {'message': message, 'level': level, 'error': ?error},
      );
    } on Object {
      // the app went away
    }
  }

  Future<void> close() async {
    ended = true;
    await service?.dispose();
  }
}

/// The file `twk run` writes the address of its app's VM service to, for
/// `twk inspect`: `run` in the `.dart_tool/twk` of [project]
/// ([LocalAddress.directoryOf]).
String serviceFileOf(String project) => LocalAddress.fileOf('run', project);
