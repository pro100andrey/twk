/// [PtyProcessPort], the adapter of [ProcessPort] and [TerminalPort] over
/// twk_term's `Pty`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_term/twk_term.dart' show Pty, PtyOutput;

import 'errors.dart';
import 'ports.dart';

/// Starts a program as `dart [--enable-vm-service=0 ...] <program>` in a
/// pseudo-terminal whose output flags are a terminal's (`PtyOutput.terminal`),
/// the VM service's address written to a file it reads.
final class PtyProcessPort implements ProcessPort {
  /// A port that runs [dart] (this process's own executable by default).
  PtyProcessPort({String? dart, this.poll = const Duration(milliseconds: 10)})
    : _dart = dart ?? Platform.resolvedExecutable;

  final String _dart;

  /// How often the file with the service's address is looked at, in real
  /// time: the VM writes it once its service listens.
  final Duration poll;

  @override
  Future<Launched> spawn(ProcessSpec spec) async {
    final dir = Directory.systemTemp.createTempSync('twk_driver');
    final info = File('${dir.path}/service.json');
    final Pty pty;
    try {
      pty = Pty.start(
        _dart,
        [
          '--enable-vm-service=0',
          '--write-service-info=${info.uri}',
          // no word of the service on the app's terminal
          '-DSILENT_VM_SERVICE=true',
          spec.program,
          ...spec.arguments,
        ],
        width: spec.width,
        height: spec.height,
        workingDirectory: spec.workingDirectory,
        environment: _appEnvironment(spec.environment),
        output: PtyOutput.terminal,
      );
    } on Object {
      dir.deleteSync(recursive: true);
      rethrow;
    }
    return _PtyLaunched(pty, info, dir, poll);
  }
}

/// Starts any command in a pseudo-terminal, as it is: `spec.program` is
/// the executable (`sh`), its [ProcessSpec.arguments] its arguments, with
/// the same terminal flags as [PtyProcessPort] and no VM service. For a
/// session made without an app service.
final class PtyCommandPort implements ProcessPort {
  /// A port that runs commands.
  const PtyCommandPort();

  @override
  Future<Launched> spawn(ProcessSpec spec) async {
    final pty = Pty.start(
      spec.program,
      spec.arguments,
      width: spec.width,
      height: spec.height,
      workingDirectory: spec.workingDirectory,
      environment: _appEnvironment(spec.environment),
      output: PtyOutput.terminal,
    );
    return _CommandLaunched(pty);
  }
}

final class _CommandLaunched implements Launched {
  _CommandLaunched(this._pty) : terminal = _PtyTerminal(_pty) {
    exitCode = _pty.exitCode.whenComplete(() => _ended = true);
  }

  final Pty _pty;
  var _ended = false;

  @override
  final TerminalPort terminal;

  @override
  late final Future<int?> exitCode;

  @override
  Future<Uri> get serviceUri => Future.error(
    const DriverError('the command has no VM service: it is not a Dart app'),
  );

  @override
  Future<void> kill() async {
    if (!_ended) {
      _pty
        ..kill()
        ..close();
    } else {
      _pty.close();
    }
    await exitCode;
  }
}

final class _PtyTerminal implements TerminalPort {
  _PtyTerminal(this._pty);

  final Pty _pty;

  @override
  Stream<Uint8List> get output => _pty.output;

  @override
  bool? get nlToCrNl => _pty.nlToCrNl;

  @override
  void write(List<int> bytes) => _pty.write(bytes);

  @override
  void resize(int width, int height) => _pty.resize(width, height);

  @override
  Uint8List? get modesAtEnd => _pty.modesAtEnd;
}

final class _PtyLaunched implements Launched {
  _PtyLaunched(this._pty, this._info, this._dir, this._poll)
    : terminal = _PtyTerminal(_pty) {
    exitCode = _pty.exitCode.whenComplete(() => _ended = true);
  }

  final Pty _pty;
  final File _info;
  final Directory _dir;
  final Duration _poll;
  var _ended = false;

  @override
  final TerminalPort terminal;

  @override
  late final Future<int?> exitCode;

  @override
  late final Future<Uri> serviceUri = _read();

  Future<Uri> _read() async {
    while (!_ended) {
      try {
        final text = _info.readAsStringSync();
        final json = _decode(text);
        if (json != null) {
          return json;
        }
      } on FileSystemException {
        // not written yet
      }
      await Future.any([
        Future<void>.delayed(_poll),
        exitCode.then<void>((_) {}),
      ]);
    }
    throw const DriverError('the program ended before its VM service did');
  }

  static Uri? _decode(String text) {
    // written whole by the VM; a partial one is read again
    final match = RegExp(r'"uri"\s*:\s*"([^"]+)"').firstMatch(text);
    return match == null ? null : Uri.parse(match.group(1)!);
  }

  @override
  Future<void> kill() async {
    if (!_ended) {
      _pty
        ..kill()
        ..close();
    } else {
      _pty.close();
    }
    try {
      await exitCode;
    } finally {
      if (_dir.existsSync()) {
        _dir.deleteSync(recursive: true);
      }
    }
  }
}

/// The environment the driver gives a program over this process's: the
/// variables that switch colors from outside (`NO_COLOR`, which twk_core
/// takes for no colors when not empty, and `FORCE_COLOR`, which twk's
/// command line reads) emptied, so that what the developer's shell has set
/// does not change what a test or a recording sees; [given] over them.
Map<String, String> _appEnvironment(Map<String, String> given) => {
  'NO_COLOR': '',
  'FORCE_COLOR': '',
  ...given,
};
