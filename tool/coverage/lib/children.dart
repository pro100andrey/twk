/// The coverage of the Dart processes a package's tests start: a script in
/// a pseudo-terminal, `dart run` of a package's executable, a fixture under
/// a low descriptor limit.
///
/// The tests start them as `Platform.resolvedExecutable`, so the runner is
/// told a different one: the `bin/dart` of a copy of the SDK made of links
/// to the real one, but for that file, a script that starts the real
/// `dart` with its VM service on, silent, writing where it listens to a
/// file named by its process id, and every isolate paused on exit. A
/// [ChildCoverage] watches those files, connects to each process, collects
/// its coverage of the package when its isolates pause on exit, and lets
/// them go.
///
/// A process that ends by `exit()` or a signal does not pause and is not
/// measured, and is counted as such: its record of what it runs, written by
/// the script before the real `dart` starts, tells it apart from one that
/// never ran a program (`dart compile`, `dart pub`), even when it ends
/// before its service is up and has said where it listens. One started with
/// VM service flags of its own (a test that connects to its app) runs as it
/// would without the coverage tool.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coverage/coverage.dart';
import 'package:twk_doc_snippets/packages.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// How long [ChildCoverage.stop] waits for the processes still being
/// measured to end before it lets them go unmeasured.
const childGrace = Duration(seconds: 10);

/// The wrapper the copied SDK has for `bin/dart`: [real] with the VM
/// service on and isolates paused on exit, writing where it listens to
/// `<services>/<pid>.json`, and before that what it runs (its first
/// argument not an option) to `<services>/<pid>.start`, the process id
/// being the same once it has become [real]; [real] alone when the
/// arguments name a VM service flag of their own.
String dartWrapper(String real, String services) =>
    '''
#!/bin/sh
# The SDK's dart, its VM service on and its isolates paused on exit, for
# tool/coverage to collect the coverage of what it runs (children.dart).
for a in "\$@"; do
  case "\$a" in
    --enable-vm-service*|--observe*|--write-service-info*|--pause-isolates-on-*)
      exec '$real' "\$@" ;;
  esac
done
# what it runs: known once it ends, if its service never said where it is
for a in "\$@"; do
  case "\$a" in
    -*) ;;
    *) printf '%s' "\$a" > "$services/\$\$.start"; break ;;
  esac
done
exec '$real' -DSILENT_VM_SERVICE=true --enable-vm-service=0 \\
  --pause-isolates-on-exit "--write-service-info=$services/\$\$.json" "\$@"
''';

/// Makes [dir] a copy of the SDK [sdk] made of links, but for `bin/dart`,
/// [wrapper]; answers that file's path.
String shadowSdk(Directory sdk, Directory dir, String wrapper) {
  final bin = Directory('${dir.path}/bin')..createSync(recursive: true);
  for (final e in sdk.listSync(followLinks: false)) {
    final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (name != 'bin') {
      Link('${dir.path}/$name').createSync(e.path);
    }
  }
  for (final e in Directory('${sdk.path}/bin').listSync(followLinks: false)) {
    final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (name != 'dart') {
      Link('${bin.path}/$name').createSync(e.path);
    }
  }
  final dart = File('${bin.path}/dart')..writeAsStringSync(wrapper);
  Process.runSync('chmod', ['+x', dart.path]);
  return dart.path;
}

/// Whether the process [pid] is there and not a zombie (Linux).
bool alive(int pid) {
  try {
    final stat = File('/proc/$pid/stat').readAsStringSync();
    final state = stat.substring(stat.lastIndexOf(')') + 2).split(' ').first;
    return state != 'Z' && state != 'X';
  } on FileSystemException {
    return false;
  }
}

/// dartdev's commands that run no program and start no VM service: what a
/// process records it runs when it is not one to measure.
const sdkCommands = {
  'analyze',
  'build',
  'compile',
  'create',
  'development-service',
  'devtools',
  'doc',
  'fix',
  'format',
  'help',
  'info',
  'install',
  'installed',
  'language-server',
  'mcp-server',
  'pub',
  'tooling-daemon',
  'uninstall',
};

/// The coverage of the Dart processes started as [dart] while it runs.
final class ChildCoverage {
  ChildCoverage._(this.dart, this._services, this._out, this._package);

  /// Starts watching for the processes of [package]'s tests, the SDK's
  /// copy made under [temp], their coverage written to [out]; null where
  /// it can't be done (not Linux, or no `sh`).
  static ChildCoverage? start(
    RepoPackage package,
    Directory temp,
    Directory out,
  ) {
    if (!Platform.isLinux || !File('/bin/sh').existsSync()) {
      return null;
    }
    final real = Platform.resolvedExecutable;
    final services = Directory('${temp.path}/services')..createSync();
    final dart = shadowSdk(
      File(real).parent.parent,
      Directory('${temp.path}/sdk'),
      dartWrapper(real, services.path),
    );
    out.createSync(recursive: true);
    final children = ChildCoverage._(dart, services, out, package);
    children._timer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => children._poll(),
    );
    return children;
  }

  /// The `dart` to give the tests as `Platform.resolvedExecutable`.
  final String dart;

  final Directory _services;
  final Directory _out;
  final RepoPackage _package;
  late final Timer _timer;
  final _measures = <Future<void>>[];

  /// The processes being measured, by id, with their service's address.
  final _running = <int, Uri>{};

  /// The processes started whose service has not said where it listens.
  final _starting = <int>{};
  var _stopped = false;
  Future<void>? _stop;

  /// Completed once nothing is being measured or starting, while [stop]
  /// waits for it.
  Completer<void>? _settled;

  /// The processes measured.
  var measured = 0;

  /// The processes of a program that ended without pausing (before their
  /// VM service was up, too), or were still running when the watch
  /// stopped: not measured.
  var lost = 0;

  /// The id of each process the watch took to measure, once it read where
  /// its VM service listens: from then on [stop] waits for it, or lets it
  /// go. For what has to know that a process is being measured, as a test
  /// does; closed once [stop] has.
  Stream<int> get taken => _taken.stream;
  final _taken = StreamController<int>.broadcast();

  void _poll() {
    final started = <int>{};
    final served = <int>{};
    for (final e in _services.listSync()) {
      final name = e.uri.pathSegments.last;
      final pid = int.tryParse(name.split('.').first);
      if (e is! File || pid == null) {
        continue;
      }
      if (name.endsWith('.json')) {
        served.add(pid);
      } else if (name.endsWith('.start')) {
        started.add(pid);
      }
    }
    served.forEach(_take);
    _starting.addAll(started.where((pid) => !_running.containsKey(pid)));
    for (final pid in _starting.toList()) {
      // ended: what it wrote before then is all it will have written
      if (alive(pid) || _take(pid)) {
        continue;
      }
      _starting.remove(pid);
      _forget(pid);
    }
    _check();
  }

  File _serviceFile(int pid) => File('${_services.path}/$pid.json');
  File _startFile(int pid) => File('${_services.path}/$pid.start');

  /// Takes [pid] to measure, once its service file says where it listens;
  /// false while it does not, whole.
  bool _take(int pid) {
    final file = _serviceFile(pid);
    final Uri uri;
    try {
      final info = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      uri = Uri.parse(info['uri']! as String);
    } on Object {
      return false; // not there, or not written whole yet
    }
    // read once: a process given the same id later writes them again
    file.deleteSync();
    _deleteIfThere(_startFile(pid));
    _starting.remove(pid);
    _running[pid] = uri;
    _measures.add(_measure(pid, uri));
    if (!_taken.isClosed) {
      _taken.add(pid);
    }
    return true;
  }

  /// Counts [pid], whose service never said where it listens, as lost
  /// when what it ran was a program, and forgets its files.
  void _forget(int pid) {
    final start = _startFile(pid);
    final String runs;
    try {
      runs = start.readAsStringSync();
    } on FileSystemException {
      return; // read already
    }
    if (!sdkCommands.contains(runs)) {
      lost++;
    }
    _deleteIfThere(start);
    _deleteIfThere(_serviceFile(pid)); // what it wrote of it, if anything
  }

  void _check() {
    final settled = _settled;
    if (settled != null &&
        !settled.isCompleted &&
        _starting.isEmpty &&
        _running.isEmpty) {
      settled.complete();
    }
  }

  /// Collects [pid]'s coverage when its isolates pause on exit; gives up
  /// when it ends without.
  Future<void> _measure(int pid, Uri uri) async {
    try {
      await _collect(pid, uri);
    } finally {
      _running.remove(pid);
      _check();
    }
  }

  Future<void> _collect(int pid, Uri uri) async {
    final libraries = {
      for (final f in _package.libraryFiles())
        'package:${_package.name}/'
                '${f.substring(_package.path.length + '/lib/'.length)}':
            <int>{},
    };
    // package:coverage lets an error of a request it does not await go
    // unhandled (a resume after the process went): caught here, it ends
    // the measure, which a result already in keeps
    final collected = Completer<Map<String, dynamic>?>();
    void answer(Map<String, dynamic>? result) {
      if (!collected.isCompleted) {
        collected.complete(result);
      }
    }

    unawaited(
      runZonedGuarded(
        () async => answer(
          await collect(
            uri,
            true,
            true,
            false,
            {_package.name},
            // to connect: the service is up once its file is written
            timeout: const Duration(seconds: 10),
            // not compiled again for the report: the lines the process did
            // not compile are the test runner's to count
            coverableLineCache: libraries,
          ),
        ),
        (_, _) => answer(null),
      ),
    );
    final gone = Completer<Map<String, dynamic>?>();
    final watch = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!alive(pid) && !gone.isCompleted) {
        gone.complete(null);
      }
    });
    final result = await Future.any([collected.future, gone.future]);
    watch.cancel();
    if (_stopped) {
      return;
    }
    if (result == null) {
      lost++;
      // paused on exit with nobody to let it go, it would never end
      if (alive(pid)) {
        await release(uri);
      }
      return;
    }
    measured++;
    File(
      '${_out.path}/$measured-$pid.json',
    ).writeAsStringSync(jsonEncode(result));
  }

  /// Stops watching, once the processes being measured or starting have
  /// ended or [grace] has passed; those still running then are not
  /// measured, and those being measured are let go, their isolates no
  /// longer pausing on exit. Called again, answers the first call's end.
  Future<void> stop({Duration grace = childGrace}) =>
      _stop ??= _stopAfter(grace);

  Future<void> _stopAfter(Duration grace) async {
    final settled = _settled = Completer<void>();
    // the watch goes on meanwhile: a process starting is taken once its
    // service says where it listens, or forgotten once it ends
    _poll();
    await Future.any([
      settled.future.then((_) => Future.wait(_measures)),
      Future<void>.delayed(grace),
    ]);
    _timer.cancel();
    _stopped = true;
    for (final pid in _starting) {
      _forget(pid);
    }
    _starting.clear();
    for (final uri in _running.values.toList()) {
      lost++;
      await release(uri);
    }
    await _taken.close();
  }
}

void _deleteIfThere(File file) {
  try {
    file.deleteSync();
  } on FileSystemException {
    // gone already
  }
}

/// Lets the process whose VM service is at [uri] end: its isolates no
/// longer pause on exit, and those paused there resume.
Future<void> release(Uri uri) async {
  final VmService service;
  try {
    service = await vmServiceConnectUri(
      '${convertToWebSocketUrl(serviceProtocolUrl: uri)}',
    );
  } on Object {
    return; // gone already
  }
  try {
    for (final ref in (await service.getVM()).isolates ?? <IsolateRef>[]) {
      final id = ref.id!;
      await service.setIsolatePauseMode(id, shouldPauseOnExit: false);
      final isolate = await service.getIsolate(id);
      if (isolate.pauseEvent?.kind == EventKind.kPauseExit) {
        await service.resume(id);
      }
    }
  } on Object {
    // it ended meanwhile
  } finally {
    await service.dispose();
  }
}
