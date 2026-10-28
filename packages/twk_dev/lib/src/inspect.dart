/// `twk inspect`: [InspectCommand], and [RunningApps], the apps `twk run`
/// runs.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:twk/twk.dart' show ScreenMode, runApp;
import 'package:twk_core/twk_core.dart'
    show Terminal, TerminalException, TerminalOptions;
import 'package:vm_service/vm_service.dart' show VmService;

import 'app_client.dart';
import 'inspector_view.dart';
import 'project.dart';
import 'run.dart';

/// `twk inspect`: shows a running app's widget tree in this terminal
/// ([InspectorView]), the app at a VM service address given, or the one
/// `twk run` runs.
final class InspectCommand extends Command<int> {
  /// Sets up `twk inspect`'s option: `--directory`.
  InspectCommand() {
    argParser.addOption(
      'directory',
      abbr: 'C',
      valueHelp: 'path',
      help:
          'A directory of the project whose app `twk run` runs (default: the '
          'current one).',
    );
  }

  @override
  String get name => 'inspect';

  @override
  String get invocation =>
      'twk inspect [<vm-service-uri>] [--directory=<path>]';

  @override
  String get description =>
      'Inspect the widget tree of a running app.\n\n'
      'Connects to the app at <vm-service-uri>, or to the one `twk run` '
      'runs from the project, and shows its widget tree, the selected '
      "node's properties and layout, the node outlined on the app's "
      "screen, and selects the node under a cell clicked on the app's "
      'screen. Without <vm-service-uri> it waits for an app, and for the '
      'next one when it ends.';

  /// How often the service file is read while no app is there.
  static const poll = Duration(milliseconds: 200);

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;
    if (rest.length > 1) {
      usageException('One VM service address at most.');
    }
    final Stream<AppClient> apps;
    final String waiting;
    final String gone;
    final RunningApps? file;
    // the connection to the app at the address given: closed however this
    // ends, also when the app on it never came (closing the app closes it)
    VmService? service;
    if (rest.isEmpty) {
      final project = projectOf(args.option('directory'));
      file = RunningApps(serviceFileOf(project));
      apps = file.apps;
      waiting = 'waiting for an app that twk run runs in $project';
      gone = 'the app has gone; $waiting';
    } else {
      file = null;
      final uri = Uri.tryParse(rest.single);
      if (uri == null || !uri.hasAuthority) {
        usageException('Not a VM service address: ${rest.single}');
      }
      try {
        service = await VmAppClient.connect(uri);
      } on Object catch (e) {
        stderr.writeln('twk inspect: no VM service at $uri: $e');
        return 1;
      }
      apps = Stream.fromFuture(VmAppClient.attach(service, '$uri'));
      waiting = 'waiting for the app at $uri to run';
      gone = 'the app has gone; q quits';
    }
    AppClient? last;
    // read out in the inline mode, as runApp does it
    final reader = Platform.environment['TWK_SCREEN_READER'] == '1';
    try {
      await runApp(
        InspectorView(
          apps: apps.map((app) => last = app),
          waiting: waiting,
          gone: gone,
        ),
        mode: reader ? ScreenMode.inline : ScreenMode.fullscreen,
        // a viewer to use: a terminal, never plain output
        terminal: await Terminal.open(
          TerminalOptions(alternateScreen: !reader, mouse: false, plain: false),
        ),
        exitOnCtrlC: false,
      );
    } on TerminalException catch (e) {
      stderr.writeln('twk inspect: ${e.message}');
      return 1;
    } finally {
      await file?.stop();
      await last?.close();
      await service?.dispose();
    }
    return 0;
  }
}

/// The apps `twk run` runs, by the service file it writes ([serviceFileOf])
/// at [path]: each as it comes ([apps]), the next once one has gone.
final class RunningApps {
  /// The apps whose service file is [path].
  RunningApps(this.path);

  /// The service file `twk run` writes, a line: the WebSocket address of
  /// the VM service of the app it runs.
  final String path;

  var _stopped = false;

  // what is being connected to
  VmService? _service;

  /// The apps, one after another: one connected to, once it runs.
  late final Stream<AppClient> apps = _apps();

  Stream<AppClient> _apps() async* {
    while (!_stopped) {
      final uri = _read();
      final service = uri == null ? null : await _connect(uri);
      if (service == null) {
        await Future<void>.delayed(InspectCommand.poll);
        continue;
      }
      _service = service;
      final AppClient app;
      try {
        app = await VmAppClient.attach(service, '$uri');
      } on AppError {
        continue;
      } finally {
        _service = null;
      }
      if (_stopped) {
        await app.close();
        return;
      }
      yield app;
      await app.done;
    }
  }

  Uri? _read() {
    try {
      return Uri.tryParse(File(path).readAsStringSync().trim());
    } on FileSystemException {
      return null;
    }
  }

  static Future<VmService?> _connect(Uri uri) async {
    try {
      return await VmAppClient.connect(uri);
    } on Object {
      // left by a twk run that did not end, or the app ends
      return null;
    }
  }

  /// Stops looking for apps, and connecting to one.
  Future<void> stop() async {
    _stopped = true;
    await _service?.dispose();
  }
}
