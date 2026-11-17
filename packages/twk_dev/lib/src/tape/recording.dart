/// [RecordingProcessPort]: a [ProcessPort] whose programs' terminals note
/// what they output, and when, for a recording.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:twk_driver/twk_driver.dart';

/// Wraps [inner]: the [Launched] it starts has a terminal whose output
/// passes each chunk on to the session, and then to [recorded].
///
/// The time of a chunk is read from [now], the recorder's own clock,
/// before the chunk is passed on, so that what the session does with it
/// (its screens take it in at once) cannot move it; [recorded] is called
/// after, with the screens of the session already showing the chunk.
/// Nothing of this is in the driver: a recorder is a [TerminalPort] around
/// the terminal a [ProcessPort] gives.
final class RecordingProcessPort implements ProcessPort {
  /// A port that starts programs with [inner], noting their output.
  RecordingProcessPort(
    this.inner, {
    required this.now,
    required this.recorded,
  });

  /// The port that starts the programs.
  final ProcessPort inner;

  /// The recorder's time.
  final Duration Function() now;

  /// Called with each chunk of output and its time, once the session has
  /// taken it in.
  final void Function(Duration at, Uint8List bytes) recorded;

  @override
  Future<Launched> spawn(ProcessSpec spec) async =>
      _RecordedLaunched(await inner.spawn(spec), this);
}

final class _RecordedLaunched implements Launched {
  _RecordedLaunched(this._inner, RecordingProcessPort port)
    : terminal = _RecordedTerminal(_inner.terminal, port);

  final Launched _inner;

  @override
  final TerminalPort terminal;

  @override
  Future<int?> get exitCode => _inner.exitCode;

  @override
  Future<Uri> get serviceUri => _inner.serviceUri;

  @override
  Future<void> kill() => _inner.kill();
}

final class _RecordedTerminal implements TerminalPort {
  _RecordedTerminal(this._inner, this._port);

  final TerminalPort _inner;
  final RecordingProcessPort _port;

  @override
  late final Stream<Uint8List> output = _output();

  Stream<Uint8List> _output() {
    StreamSubscription<Uint8List>? source;
    late final StreamController<Uint8List> out;
    // sync: the session has the chunk when `add` returns
    out = StreamController<Uint8List>(
      sync: true,
      onListen: () {
        source = _inner.output.listen(
          (bytes) {
            final at = _port.now();
            out.add(bytes);
            _port.recorded(at, bytes);
          },
          onError: out.addError,
          onDone: out.close,
        );
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () => source?.cancel(),
    );
    return out.stream;
  }

  @override
  bool? get nlToCrNl => _inner.nlToCrNl;

  @override
  void write(List<int> bytes) => _inner.write(bytes);

  @override
  void resize(int width, int height) => _inner.resize(width, height);

  @override
  Uint8List? get modesAtEnd => _inner.modesAtEnd;
}
