/// A session: the channel a client runs a shell or a command on, with its
/// terminal, environment, input and output.
///
/// @docImport 'auth.dart';
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'keys.dart';
import 'wire.dart';

/// The terminal a client asked for (`pty-req`), as it is now: its size
/// changes with each `window-change`.
final class SshPty {
  /// A terminal of [term], [columns] by [rows], with [modes].
  SshPty({
    required this.term,
    required this.columns,
    required this.rows,
    this.pixelWidth = 0,
    this.pixelHeight = 0,
    this.modes = const {},
  });

  /// The client's `TERM`, `xterm-256color` say.
  final String term;

  /// The width, in cells.
  final int columns;

  /// The height, in cells.
  final int rows;

  /// The width in pixels; 0 when the client didn't say.
  final int pixelWidth;

  /// The height in pixels; 0 when the client didn't say.
  final int pixelHeight;

  /// The terminal modes (RFC 4254 §8), by opcode.
  final Map<int, int> modes;

  /// The most columns a terminal is taken as: a client's wider one (of up
  /// to 2^32 - 1) is cut to it, as a screen of that many cells is drawn.
  static const maxColumns = 2048;

  /// The most rows a terminal is taken as, as [maxColumns].
  static const maxRows = 1024;

  /// The opcode of VERASE, the byte the Backspace key sends.
  static const verase = 3;

  /// The byte the Backspace key sends (0x7F, or 0x08 on some setups);
  /// null when the client didn't say.
  int? get eraseChar => modes[verase];

  SshPty _resized(int columns, int rows, int pixelWidth, int pixelHeight) =>
      SshPty(
        term: term,
        columns: columns,
        rows: rows,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        modes: modes,
      );
}

/// What the server sends and receives on a session channel.
@internal
abstract interface class SessionTransport {
  void send(Uint8List payload);

  /// Whether what is sent now is held, a key exchange under way: the
  /// channel's data then waits in the channel, and its flushes with it,
  /// until [SshSession.resumeOutput].
  bool get holding;

  /// The channel is closed both ways.
  void channelClosed();
}

/// A shell or a command a client runs: one session channel of a
/// connection, from its `shell` or `exec` request to its close.
///
/// [input] is what the client types; [add] writes to it. The channel's
/// windows are kept both ways: input the app doesn't read (a paused or
/// absent listener) is held and not granted again, so the client stops
/// sending; output goes no faster than the client grants, and what it
/// hasn't granted yet waits here until it does ([flush] completes once
/// everything written is sent).
final class SshSession {
  @internal
  /// The session of a channel the client opened, with the number, the
  /// window and the largest packet it gave; made by the connection.
  SshSession({
    required this.user,
    required this.publicKey,
    required this.remoteAddress,
    required this.remotePort,
    required this._transport,
    required this._remoteId,
    required this._remoteWindow,
    required int remoteMaxPacket,
  }) : _remoteMaxPacket = remoteMaxPacket.clamp(1, maxPacket);

  /// The window granted to the client, and granted again once half of it
  /// is read.
  static const int window = 1 << 20;

  /// The most data the server takes in one message, and sends.
  static const int maxPacket = 1 << 15;

  /// Environment variables taken, and their sizes.
  static const _maxEnvironment = 64;
  static const _maxEnvironmentBytes = 4096;

  /// The user name the client logged in as, which [SshAuth] accepted it
  /// with. Where it accepts a key whatever the name
  /// ([SshAuth.authorizedKeys]), it is only what the client said: who
  /// proved to be there is [publicKey].
  final String user;

  /// The key [user] logged in with; null for a password.
  final SshPublicKey? publicKey;

  /// The client's address.
  final InternetAddress remoteAddress;

  /// The client's port.
  final int remotePort;

  final SessionTransport _transport;
  final int _remoteId;
  int _remoteWindow;
  final int _remoteMaxPacket;

  int _localWindow = window;
  var _unacknowledged = 0;

  /// The terminal the client asked for; null when it asked for none
  /// (`ssh -T`, or a command without `-t`).
  SshPty? get pty => _pty;
  SshPty? _pty;

  /// The environment the client sent (`env` requests: what `SendEnv` or
  /// `SetEnv` pass).
  Map<String, String> get environment => UnmodifiableMapView(_environment);
  final _environment = <String, String>{};

  /// The command of an `exec` request; null for a shell.
  String? get command => _command;
  String? _command;

  /// Whether a shell or a command was asked for, which starts the
  /// session.
  bool get started => _started;
  var _started = false;

  late final _input = StreamController<Uint8List>(
    onListen: _deliverHeld,
    onResume: _deliverHeld,
  );
  final _heldInput = Queue<Uint8List>();
  var _inputEnded = false;

  /// What the client sends; ends when it sends EOF or the session ends.
  Stream<Uint8List> get input => _input.stream;

  final _resizes = StreamController<SshPty>.broadcast(sync: true);

  /// [pty] after each `window-change`.
  Stream<SshPty> get resizes => _resizes.stream;

  final _signals = StreamController<String>.broadcast(sync: true);

  /// The signals the client sends, by name without `SIG`: `INT`, `TERM`.
  Stream<String> get signals => _signals.stream;

  final _output = Queue<Uint8List>();
  var _outputAt = 0;
  final _flushes = <Completer<void>>[];

  var _closeSent = false;
  var _closeReceived = false;
  final _done = Completer<void>();

  /// Completes once the session is over: the channel closed by either
  /// end, or the connection gone.
  Future<void> get done => _done.future;

  /// Whether the session is over ([done] has completed).
  bool get isDone => _done.isCompleted;

  /// Bytes the client sent that the app hasn't read yet.
  @visibleForTesting
  int get heldInput => _heldInput.fold(0, (n, b) => n + b.length);

  /// Bytes written and not yet sent: the client hasn't granted them.
  int get pendingOutput => _pending;
  var _pending = 0;

  /// The most bytes written and not yet sent ([pendingOutput]) a session
  /// holds: past it, the client granting none of them, the session is
  /// closed rather than the server holding without end what it does not
  /// take.
  static const int maxPendingOutput = 64 << 20;

  /// Writes [bytes] to the client: sent as far as its window allows, the
  /// rest when it grants more. Dropped once the session has ended or
  /// [exit] was called. Past [maxPendingOutput] of them waiting, the
  /// session is closed: a writer that awaits [flush] holds no more than it
  /// writes between two.
  void add(List<int> bytes) {
    if (_closeSent || isDone || bytes.isEmpty) {
      return;
    }
    _output.add(Uint8List.fromList(bytes));
    _pending += bytes.length;
    _sendOutput();
    if (_pending > maxPendingOutput) {
      _sendClose();
    }
  }

  /// Completes once everything [add]ed is sent, or the session ended.
  Future<void> flush() {
    if (_output.isEmpty || isDone) {
      return Future.value();
    }
    final c = Completer<void>();
    _flushes.add(c);
    return c.future;
  }

  var _exiting = false;

  /// Ends the session with [status]: what was written is sent first (for
  /// at most [drain], while the client grants nothing), then the
  /// `exit-status`, EOF and close. Completes once the client closed its
  /// end too, or the connection is gone.
  Future<void> exit([
    int status = 0,
    Duration drain = const Duration(seconds: 5),
  ]) async {
    if (_exiting || isDone) {
      return done;
    }
    _exiting = true;
    await flush().timeout(drain, onTimeout: () {});
    if (isDone) {
      return;
    }
    _send(
      SshWriter()
        ..byte(SshMsg.channelRequest)
        ..uint32(_remoteId)
        ..utf8String('exit-status')
        ..boolean(false)
        ..uint32(status),
    );
    _sendClose();
    return done;
  }

  void _send(SshWriter w) => _transport.send(w.takeBytes());

  void _sendClose() {
    if (_closeSent) {
      return;
    }
    _closeSent = true;
    _output.clear();
    _outputAt = 0;
    _pending = 0;
    _send(
      SshWriter()
        ..byte(SshMsg.channelEof)
        ..uint32(_remoteId),
    );
    _send(
      SshWriter()
        ..byte(SshMsg.channelClose)
        ..uint32(_remoteId),
    );
    if (_closeReceived) {
      _end();
    }
  }

  void _sendOutput() {
    while (_output.isNotEmpty &&
        _remoteWindow > 0 &&
        !_closeSent &&
        !_transport.holding) {
      final first = _output.first;
      final n = [
        first.length - _outputAt,
        _remoteWindow,
        _remoteMaxPacket,
      ].reduce((a, b) => a < b ? a : b);
      if (n <= 0) {
        break;
      }
      _send(
        SshWriter()
          ..byte(SshMsg.channelData)
          ..uint32(_remoteId)
          ..string(Uint8List.sublistView(first, _outputAt, _outputAt + n)),
      );
      _remoteWindow -= n;
      _outputAt += n;
      _pending -= n;
      if (_outputAt == first.length) {
        _output.removeFirst();
        _outputAt = 0;
      }
    }
    if (_output.isEmpty) {
      _completeFlushes();
    }
  }

  void _completeFlushes() {
    final flushes = List.of(_flushes);
    _flushes.clear();
    for (final c in flushes) {
      c.complete();
    }
  }

  void _deliverHeld() {
    while (_heldInput.isNotEmpty && _input.hasListener && !_input.isPaused) {
      final bytes = _heldInput.removeFirst();
      _input.add(bytes);
      _consumed(bytes.length);
    }
    if (_heldInput.isEmpty && _inputEnded && !_input.isClosed) {
      unawaited(_input.close());
    }
  }

  /// [n] bytes of input were handed to the app: the window is granted
  /// again once half of it is.
  void _consumed(int n) {
    _unacknowledged += n;
    if (_unacknowledged >= window ~/ 2 && !_closeReceived) {
      _send(
        SshWriter()
          ..byte(SshMsg.channelWindowAdjust)
          ..uint32(_remoteId)
          ..uint32(_unacknowledged),
      );
      _localWindow += _unacknowledged;
      _unacknowledged = 0;
    }
  }

  void _endInput() {
    _inputEnded = true;
    _deliverHeld();
  }

  void _end() {
    if (isDone) {
      return;
    }
    _done.complete();
    _completeFlushes();
    _heldInput.clear();
    _endInput();
    unawaited(_resizes.close());
    unawaited(_signals.close());
    _transport.channelClosed();
  }

  // ------------------------------------------- from the connection --

  /// The client's data on the channel.
  @internal
  void receiveData(Uint8List data) {
    if (data.length > _localWindow || data.length > maxPacket) {
      throw const SshProtocolException('data beyond the window');
    }
    _localWindow -= data.length;
    if (_inputEnded || isDone) {
      return;
    }
    _heldInput.add(Uint8List.fromList(data));
    _deliverHeld();
  }

  /// The client's extended data (stderr), which a session has no use for:
  /// it only counts against the window.
  @internal
  void receiveExtendedData(int length) {
    if (length > _localWindow || length > maxPacket) {
      throw const SshProtocolException('data beyond the window');
    }
    _localWindow -= length;
    _consumed(length);
  }

  @internal
  /// The transport sends again, a key exchange done: the output held in
  /// the channel meanwhile goes.
  void resumeOutput() => _sendOutput();

  @internal
  /// The client grants [bytes] more of output.
  void receiveWindowAdjust(int bytes) {
    if (_remoteWindow + bytes > 0xFFFFFFFF) {
      throw const SshProtocolException('a window beyond 2^32 - 1');
    }
    _remoteWindow += bytes;
    _sendOutput();
  }

  @internal
  /// The client sends no more input.
  void receiveEof() => _endInput();

  @internal
  /// The client closed the channel.
  void receiveClose() {
    _closeReceived = true;
    if (_closeSent) {
      _end();
    } else {
      _sendClose();
    }
  }

  static int _columns(int n) => n < SshPty.maxColumns ? n : SshPty.maxColumns;

  static int _rows(int n) => n < SshPty.maxRows ? n : SshPty.maxRows;

  /// The connection is gone.
  @internal
  void connectionLost() {
    _closeSent = true;
    _closeReceived = true;
    _end();
  }

  /// A channel request: whether it succeeded. Throws
  /// [SshProtocolException] for one that is malformed.
  @internal
  bool request(String type, SshReader r) {
    switch (type) {
      case 'pty-req' when _pty == null && !_started:
        final term = r.utf8String();
        final columns = _columns(r.uint32());
        final rows = _rows(r.uint32());
        final pixelWidth = r.uint32();
        final pixelHeight = r.uint32();
        _pty = SshPty(
          term: term,
          columns: columns,
          rows: rows,
          pixelWidth: pixelWidth,
          pixelHeight: pixelHeight,
          modes: _modes(r.string()),
        );
        return true;
      case 'env' when !_started:
        final name = r.utf8String();
        final value = r.utf8String();
        if (_environment.length >= _maxEnvironment ||
            name.length + value.length > _maxEnvironmentBytes) {
          return false;
        }
        _environment[name] = value;
        return true;
      case 'shell' when !_started:
        _started = true;
        return true;
      case 'exec' when !_started:
        _command = r.utf8String();
        _started = true;
        return true;
      case 'window-change':
        final pty = _pty;
        if (pty == null) {
          return false;
        }
        final resized = _pty = pty._resized(
          _columns(r.uint32()),
          _rows(r.uint32()),
          r.uint32(),
          r.uint32(),
        );
        _resizes.add(resized);
        return true;
      case 'signal':
        _signals.add(r.utf8String());
        return true;
    }
    return false;
  }

  /// The encoded terminal modes: an opcode and a uint32 each, to
  /// TTY_OP_END (0) or an opcode from 160 on, which ends what can be read.
  static Map<int, int> _modes(Uint8List encoded) {
    final r = SshReader(encoded);
    final modes = <int, int>{};
    while (!r.atEnd) {
      final opcode = r.byte();
      if (opcode == 0 || opcode >= 160) {
        break;
      }
      modes[opcode] = r.uint32();
    }
    return modes;
  }
}
