/// A terminal served over a local socket: `twk shell` owns a terminal and
/// serves it ([TerminalShell]) to an app started elsewhere (from an IDE,
/// under the debugger), whose `Terminal` reads and writes it through a
/// [SocketLink]: a breakpoint stops the app, not the terminal.
///
/// The app does everything it does on its own terminal (the capability
/// probe, the modes, the frames, restoring it) over the socket; the shell
/// passes the bytes through and keeps what the app can't do from its
/// process: the console modes, the size, and putting the terminal back
/// when the app goes away without doing so itself (killed, or restarted
/// by the debugger).
///
/// The wire: frames of a type byte, the payload's length (4 bytes, big
/// endian) and the payload ([Wire], [frame]). The app opens with
/// [Wire.hello] and the token of the shell's address file; the shell
/// answers with [Wire.welcome] (size, environment, erase character, what
/// the terminal declares it does) or [Wire.refused]. `test/terminal/shell_wire.golden.json` describes it
/// frame by frame, and holds this file and the VS Code extension's port of
/// it (`editors/vscode/src/core/wire.ts`, `shell.ts`) to the same bytes: a
/// change here is made there and in the golden too.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'address.dart';
import 'link.dart';
import 'outbox.dart';
import 'stdio_link.dart';

/// The frames between a [SocketLink] and a [TerminalShell].
abstract final class Wire {
  /// The version of the wire both ends must speak.
  static const protocol = 1;

  /// App to shell, first: JSON `{"protocol": 1, "token": "..."}`.
  static const hello = 1;

  /// App to shell: bytes for the terminal.
  static const output = 2;

  /// App to shell: answer with [flushed] once the output before it is
  /// written.
  static const flush = 3;

  /// App to shell: the bytes that put the terminal back as it was, written
  /// by the shell if the app goes away without writing them (empty once
  /// the app has).
  static const lost = 4;

  /// App to shell: `[1]` raw mode, `[0]` the console modes as found.
  static const raw = 5;

  /// Shell to app, answering [hello]: JSON `{"columns", "lines",
  /// "eraseChar", "windows", "environment"}`, and `"declares"` where the
  /// terminal declares what it does ([TerminalDeclaration.toJson]), which
  /// the app takes over its guess by the environment.
  static const welcome = 16;

  /// Shell to app, answering [hello]: why not (UTF-8); the shell closes
  /// the connection.
  static const refused = 17;

  /// Shell to app: the terminal's input.
  static const input = 18;

  /// Shell to app: JSON `{"columns", "lines"}`, the terminal's new size.
  static const size = 19;

  /// Shell to app: what was asked with [flush] is written.
  static const flushed = 20;

  /// The longest payload either end accepts.
  static const int maxPayload = 1 << 26;
}

/// The header of a frame of [type] with a payload of [length] bytes.
Uint8List frameHeader(int type, int length) => Uint8List(5)
  ..[0] = type
  ..buffer.asByteData().setUint32(1, length);

/// A frame of [type] with [payload].
Uint8List frame(int type, [List<int> payload = const []]) =>
    Uint8List(5 + payload.length)
      ..setAll(0, frameHeader(type, payload.length))
      ..setAll(5, payload);

/// A frame of [type] with [json], UTF-8 encoded, as its payload.
Uint8List jsonFrame(int type, Object json) =>
    frame(type, utf8.encode(jsonEncode(json)));

/// Cuts the bytes of a socket into frames, whatever the reads split them
/// into.
final class FrameReader {
  /// A reader that hands each whole frame's type and payload to
  /// `onFrame`.
  FrameReader(this._onFrame);

  final void Function(int type, Uint8List payload) _onFrame;

  /// The size the buffer is made, and made again once a frame longer than
  /// [_kept] it grew for is read: one such frame is not held for the
  /// connection's life.
  static const int _size = 1 << 12;

  /// The longest buffer kept once emptied: the frames of a screen drawn
  /// whole, tens of kilobytes each, would make it grow and be dropped
  /// again for each one.
  static const int _kept = 1 << 20;
  var _buffer = Uint8List(_size);
  late var _data = ByteData.sublistView(_buffer);
  var _length = 0;

  /// Takes [bytes] read from the socket; calls back with each frame they
  /// complete. Throws [FormatException] for a payload longer than
  /// [Wire.maxPayload].
  void add(List<int> bytes) {
    if (_length + bytes.length > _buffer.length) {
      var size = _buffer.length * 2;
      while (size < _length + bytes.length) {
        size *= 2;
      }
      _use(Uint8List(size)..setRange(0, _length, _buffer));
    }
    _buffer.setRange(_length, _length + bytes.length, bytes);
    _length += bytes.length;
    var at = 0;
    while (_length - at >= 5) {
      final length = _data.getUint32(at + 1);
      if (length > Wire.maxPayload) {
        throw FormatException('a frame of $length bytes');
      }
      if (_length - at - 5 < length) {
        break;
      }
      final type = _buffer[at];
      // a copy of its own: the buffer is written over by what comes next
      final payload = _buffer.sublist(at + 5, at + 5 + length);
      at += 5 + length;
      _onFrame(type, payload);
    }
    if (at > 0) {
      _buffer.setRange(0, _length - at, _buffer, at);
      _length -= at;
    }
    if (_length == 0 && _buffer.length > _kept) {
      _use(Uint8List(_size));
    }
  }

  void _use(Uint8List buffer) {
    _buffer = buffer;
    _data = ByteData.sublistView(buffer);
  }
}

/// The app's end: a [TerminalLink] to the terminal a [TerminalShell]
/// serves.
///
/// When the shell goes away its input ends with a [TerminalException];
/// from then on what is written is dropped and flushes complete at once.
final class SocketLink implements DeclaringLink {
  SocketLink._(this._socket) {
    _reader = FrameReader(_onFrame);
    // what failed in a write is told by the reads, or doesn't matter
    unawaited(_socket.done.then<void>((_) {}, onError: (Object _) {}));
    _socket.listen(
      (bytes) {
        try {
          _reader.add(bytes);
        } on FormatException catch (e) {
          _gone(TerminalException('the shell sent $e'));
          _socket.destroy();
        }
      },
      onError: (Object e) =>
          _gone(TerminalException('the connection to the shell failed: $e')),
      onDone: () =>
          _gone(const TerminalException('the shell closed the connection')),
    );
  }

  /// Connects to the shell at [address]. Throws [SocketException] when
  /// nobody listens there, [TerminalException] when the shell refuses or
  /// doesn't answer within [timeout].
  static Future<SocketLink> connect(
    LocalAddress address, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = await address.connect();
    final link = SocketLink._(socket);
    try {
      socket.add(
        jsonFrame(Wire.hello, {
          'protocol': Wire.protocol,
          'token': address.token,
        }),
      );
      await link._welcome.future.timeout(
        timeout,
        onTimeout: () =>
            throw const TerminalException('the shell did not answer'),
      );
    } on Object {
      socket.destroy();
      rethrow;
    }
    return link;
  }

  /// The link to the `twk shell` [env] names in `TWK_SHELL`
  /// ([LocalAddress.shellVariable]), or else the one serving the project
  /// [directory] is in (see [LocalAddress.projectOf]); null when there is
  /// none: no address file, or nobody listening at its address. Throws
  /// [TerminalException] when the shell refuses.
  ///
  /// A `TWK_SHELL` that is set (not empty) is the only shell looked for:
  /// one it doesn't name ([LocalAddress.fromVariable] takes no such value)
  /// or where nobody listens throws [TerminalException], and the project's
  /// address file is not read, so that an app given a terminal never
  /// lands in another one.
  static Future<SocketLink?> toShell([
    String? directory,
    Map<String, String> env = const {},
  ]) async {
    const variable = LocalAddress.shellVariable;
    final named = env[variable];
    if (named != null && named.isNotEmpty) {
      final address = LocalAddress.fromVariable(named);
      if (address == null) {
        throw const TerminalException(
          '$variable names no twk shell: it is unix:<path>#<token> or '
          'tcp:<host>:<port>#<token>',
        );
      }
      try {
        return await connect(address);
      } on SocketException catch (e) {
        final why = e.osError?.message ?? e.message;
        throw TerminalException('no twk shell at $variable ($address): $why');
      }
    }
    final address = LocalAddress.read(LocalAddress.fileOf('shell', directory));
    if (address == null) {
      return null;
    }
    try {
      return await connect(address);
    } on SocketException {
      return null;
    }
  }

  final Socket _socket;
  late final FrameReader _reader;
  final _welcome = Completer<void>();
  final _input = StreamController<List<int>>();
  final _resizes = StreamController<void>.broadcast(sync: true);
  final _acks = Queue<Completer<void>>();

  /// The shell went away, or [close] was called.
  var _ended = false;

  @override
  var environment = const <String, String>{};

  /// What the welcome declares (`declares`); empty where it declares
  /// nothing.
  @override
  var declaration = const TerminalDeclaration();

  @override
  var windows = false;

  @override
  var columns = 80;

  @override
  var lines = 24;

  @override
  int? eraseChar;

  void _onFrame(int type, Uint8List payload) {
    switch (type) {
      case Wire.welcome when !_welcome.isCompleted:
        final json = jsonDecode(utf8.decode(payload)) as Map<String, Object?>;
        columns = json['columns']! as int;
        lines = json['lines']! as int;
        eraseChar = json['eraseChar'] as int?;
        windows = json['windows'] == true;
        environment = (json['environment']! as Map<String, Object?>).map(
          (k, v) => MapEntry(k, v! as String),
        );
        declaration = TerminalDeclaration.fromJson(json['declares']);
        _welcome.complete();
      case Wire.refused when !_welcome.isCompleted:
        _welcome.completeError(
          TerminalException('the shell refused: ${utf8.decode(payload)}'),
        );
      case Wire.input:
        _input.add(payload);
      case Wire.size:
        final json = jsonDecode(utf8.decode(payload)) as Map<String, Object?>;
        columns = json['columns']! as int;
        lines = json['lines']! as int;
        _resizes.add(null);
      case Wire.flushed when _acks.isNotEmpty:
        _acks.removeFirst().complete();
      default:
      // nothing else comes from a shell that speaks this protocol
    }
  }

  void _gone(TerminalException reason) {
    if (_ended) {
      return;
    }
    _ended = true;
    if (!_welcome.isCompleted) {
      _welcome.completeError(reason);
    }
    while (_acks.isNotEmpty) {
      _acks.removeFirst().complete();
    }
    _input.addError(reason);
    unawaited(_input.close());
    unawaited(_resizes.close());
  }

  void _send(int type, [List<int> payload = const []]) {
    if (!_ended) {
      _socket.add(frame(type, payload));
    }
  }

  @override
  void enterRaw() => _send(Wire.raw, const [1]);

  @override
  void restore() => _send(Wire.raw, const [0]);

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  void add(List<int> bytes) {
    if (!_ended && bytes.isNotEmpty) {
      _socket
        ..add(frameHeader(Wire.output, bytes.length))
        ..add(bytes);
    }
  }

  /// Completes once the shell wrote what was added to its terminal. There
  /// is no time limit: a shell whose terminal was paused (Ctrl+S) or which
  /// was stopped can't be told from one that hangs, and a local app waits
  /// for a paused terminal as well.
  @override
  Future<void> flush() {
    if (_ended) {
      return Future.value();
    }
    final ack = Completer<void>();
    _acks.add(ack);
    _send(Wire.flush);
    return ack.future;
  }

  @override
  Stream<void> get resizes => _resizes.stream;

  @override
  void restoreWith(List<int> bytes) => _send(Wire.lost, bytes);

  /// Closes the connection once what was written is sent: the shell puts
  /// the terminal back as [restoreWith] said, which is nothing once the
  /// app has.
  @override
  Future<void> close() async {
    if (_ended) {
      _socket.destroy();
      return;
    }
    _ended = true;
    while (_acks.isNotEmpty) {
      _acks.removeFirst().complete();
    }
    try {
      await _socket.close().timeout(const Duration(seconds: 1));
    } on Object {
      // the shell is gone or stuck: nothing more to tell it
    }
    _socket.destroy();
    // the done event is only delivered to a listener: without one the
    // future never completes
    final closed = _input.close();
    if (_input.hasListener) {
      await closed;
    }
    await _resizes.close();
  }
}

/// What a [TerminalShell] tells the command around it.
enum ShellEvent {
  /// An app connected and has the terminal.
  connected,

  /// The app went away and the terminal is back as before it came.
  disconnected,
}

/// The shell's end: serves a terminal ([TerminalLink], this process's own
/// with [start]) to the apps that connect to it, one at a time.
///
/// An app that connects with the token of the address gets the terminal:
/// the console in raw mode, the input and each change of size passed to
/// it, its output written. A newer app takes the terminal over from the
/// one that has it: that one is disconnected. When the app goes away,
/// closing the connection or killed, the terminal is put back as it was
/// before the app came: what its last [Wire.lost] bytes say, and the
/// console modes as found. Output is written a whole [Wire.output] frame
/// at a time, and a frame of `Terminal` holds whole sequences (a frame of
/// `TwkApp` its synchronized update too): an app killed while writing
/// leaves no sequence cut short. Input that comes while no app has the
/// terminal in raw mode is dropped.
///
/// What `twk shell` runs, in short:
///
/// ```dart
/// final shell = await TerminalShell.start(
///   onEvent: (event) {
///     if (event == ShellEvent.disconnected) {
///       // the terminal is the shell's again
///     }
///   },
/// );
/// shell.say('Waiting for an app\r\n');
/// // ... and once it is to end:
/// await shell.stop();
/// ```
final class TerminalShell {
  /// Serves `link` to the apps that connect to `server` with [address]'s
  /// token; when stopped, also forgets `file`, the address file, if it
  /// still holds [address]. `onEvent` hears of each app that comes and
  /// goes. A `link` that declares what its terminal does ([DeclaringLink])
  /// has each app welcomed with that; the process's own terminal declares
  /// nothing, and the apps guess by its environment.
  TerminalShell.serve(
    this._link,
    this._server,
    this.address, {
    this._file,
    this._onEvent,
  }) : _out = Outbox(_link.add, _link.flush) {
    _inputs = _link.input.listen((bytes) {
      final session = _session;
      if (session != null && session.raw) {
        session.send(Wire.input, bytes);
      }
    });
    _sizes = _link.resizes.listen(
      (_) => _session?.sendJson(Wire.size, {
        'columns': _link.columns,
        'lines': _link.lines,
      }),
    );
    _server.listen(_accept, onError: (Object _) {});
  }

  /// Serves this process's terminal to the apps of the project [directory]
  /// is in ([LocalAddress.projectOf]): listens on a new local socket
  /// ([LocalAddress.bind]) whose address goes to the project's address
  /// file `.dart_tool/twk/shell`, where `Terminal.open` finds it. Throws
  /// [TerminalException] when stdin or stdout is not a terminal, or a
  /// shell serves the project already; when the address can't be kept in
  /// its file or the terminal can't be served (stdin listened to already),
  /// what that throws, the socket closed and the address file forgotten
  /// first.
  static Future<TerminalShell> start({
    String? directory,
    void Function(ShellEvent event)? onEvent,
  }) async {
    if (!stdin.hasTerminal || !stdout.hasTerminal) {
      throw const TerminalException('not a terminal');
    }
    final project = LocalAddress.projectOf(directory);
    final file = LocalAddress.fileOf('shell', project);
    final running = LocalAddress.read(file);
    // or else left behind by a shell that didn't stop
    if (running != null && await answers(running)) {
      throw TerminalException('a twk shell serves $project already');
    }
    final (server, address) = await LocalAddress.bind(
      LocalAddress.directoryOf(project),
      'shell',
    );
    try {
      await address.write(file);
      return TerminalShell.serve(
        StdioLink(),
        server,
        address,
        file: file,
        onEvent: onEvent,
      );
    } on Object {
      // left open, the socket would keep the process alive, and the
      // address file would send apps to a shell that never answers: on
      // Windows the socket is TCP's, bound before anything is made in the
      // project; and stdin may be listened to already
      await server.close();
      address
        ..forget(file)
        ..unlink();
      rethrow;
    }
  }

  /// Whether a shell answers at [address] within [timeout]: a twk shell,
  /// or the VS Code extension's, refuses a hello of protocol 0, which
  /// takes nothing from the app that has its terminal.
  ///
  /// That somebody listens there is not enough: on Windows the address is
  /// a TCP port, which another program may have been given since the
  /// shell that wrote it went away.
  static Future<bool> answers(
    LocalAddress address, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final Socket socket;
    try {
      socket = await address.connect();
    } on SocketException {
      return false;
    }
    final refused = Completer<bool>();
    void answer(bool shell) {
      if (!refused.isCompleted) {
        refused.complete(shell);
      }
    }

    final reader = FrameReader((type, _) => answer(type == Wire.refused));
    unawaited(socket.done.then<void>((_) {}, onError: (Object _) {}));
    socket
      ..listen(
        (bytes) {
          try {
            reader.add(bytes);
          } on FormatException {
            answer(false);
          }
        },
        onError: (Object _) => answer(false),
        onDone: () => answer(false),
      )
      ..add(jsonFrame(Wire.hello, {'protocol': 0}));
    try {
      return await refused.future.timeout(timeout, onTimeout: () => false);
    } finally {
      socket.destroy();
    }
  }

  /// Where the shell listens.
  final LocalAddress address;

  final TerminalLink _link;
  final ServerSocket _server;
  final String? _file;
  final void Function(ShellEvent event)? _onEvent;
  final Outbox _out;
  late final StreamSubscription<List<int>> _inputs;
  late final StreamSubscription<void> _sizes;

  /// The app that has the terminal.
  _Session? _session;

  /// Connections that haven't said hello yet.
  final _pending = <_Session>{};

  var _stopped = false;
  final _done = Completer<void>();

  /// What a connection's frame threw, which stopped the shell.
  (Object, StackTrace)? _failure;

  /// How long a connection may take to say hello.
  static const helloTimeout = Duration(seconds: 5);

  /// Whether an app has the terminal.
  bool get serving => _session != null;

  /// Completes once [stop] has run; with the error, once the terminal is
  /// put back, where handling what an app sent threw (the console's raw
  /// mode failing, `onEvent` throwing), which stops the shell.
  Future<void> get done => _done.future;

  /// Writes [text] to the terminal: a line about the shell, for when no
  /// app has it.
  void say(String text) => _out.add(utf8.encode(text));

  void _accept(Socket socket) {
    if (_stopped) {
      socket.destroy();
      return;
    }
    final session = _Session(socket);
    _pending.add(session);
    final timer = Timer(helloTimeout, () {
      if (_pending.remove(session)) {
        socket.destroy();
      }
    });
    session.listen(
      (type, payload) {
        try {
          if (_pending.contains(session)) {
            timer.cancel();
            _pending.remove(session);
            _hello(session, type, payload);
          } else if (identical(session, _session)) {
            _frame(session, type, payload);
          }
        } on Object catch (error, stack) {
          // thrown on, it would end the process with the terminal raw (the
          // console gone, onEvent failing): the shell stops, the terminal
          // put back, and [done] completes with it
          _failure ??= (error, stack);
          unawaited(stop());
        }
      },
      () {
        timer.cancel();
        _pending.remove(session);
        _end(session);
      },
    );
  }

  void _hello(_Session session, int type, Uint8List payload) {
    String? refusal;
    if (type != Wire.hello) {
      refusal = 'no hello';
    } else {
      Object? json;
      try {
        json = jsonDecode(utf8.decode(payload));
      } on FormatException {
        json = null;
      }
      if (json is! Map<String, Object?>) {
        refusal = 'no hello';
      } else if (json['protocol'] != Wire.protocol) {
        refusal =
            'the app speaks protocol ${json['protocol']}, this shell '
            '${Wire.protocol}';
      } else if (json['token'] != address.token) {
        refusal = 'not the token of this shell';
      }
    }
    if (refusal != null) {
      session
        ..send(Wire.refused, utf8.encode(refusal))
        ..close();
      return;
    }
    final old = _session;
    if (old != null) {
      _end(old);
    }
    _session = session;
    _onEvent?.call(ShellEvent.connected);
    _link.enterRaw();
    final link = _link;
    final declares = link is DeclaringLink
        ? link.declaration.toJson()
        : const <String, Object>{};
    session
      ..raw = true
      ..sendJson(Wire.welcome, {
        'columns': link.columns,
        'lines': link.lines,
        'eraseChar': link.eraseChar,
        'windows': link.windows,
        'environment': link.environment,
        if (declares.isNotEmpty) 'declares': declares,
      });
  }

  void _frame(_Session session, int type, Uint8List payload) {
    switch (type) {
      case Wire.output:
        _out.add(payload);
      case Wire.flush:
        unawaited(
          _out
              .flush()
              .then<void>((_) {}, onError: (Object _) {})
              .whenComplete(() => session.send(Wire.flushed)),
        );
      case Wire.lost:
        session.lost = payload;
      case Wire.raw:
        final raw = payload.isNotEmpty && payload[0] == 1;
        if (raw && !session.raw) {
          _link.enterRaw();
        } else if (!raw && session.raw) {
          _link.restore();
        }
        session.raw = raw;
      default:
        // not of this protocol: the app is cut off
        _end(session);
    }
  }

  /// Puts the terminal back after [session], if it had it, and closes its
  /// connection.
  void _end(_Session session) {
    if (session.ended) {
      return;
    }
    session
      ..ended = true
      ..destroy();
    if (!identical(session, _session)) {
      return;
    }
    _session = null;
    _out.add(session.lost);
    if (session.raw) {
      _link.restore();
    }
    _onEvent?.call(ShellEvent.disconnected);
  }

  /// Stops serving: the app that has the terminal is disconnected and the
  /// terminal put back, the socket closed and its address file forgotten.
  /// Safe to call more than once.
  Future<void> stop() async {
    if (_stopped) {
      return done;
    }
    _stopped = true;
    try {
      await _server.close();
      for (final s in [..._pending]) {
        s.destroy();
      }
      _pending.clear();
      final session = _session;
      if (session != null) {
        _end(session);
      }
      try {
        await _out.flush();
      } on Object {
        // the terminal is gone
      }
    } finally {
      await _sizes.cancel();
      await _inputs.cancel();
      final file = _file;
      if (file != null) {
        address.forget(file);
      }
      address.unlink();
      await _link.close();
      if (_failure case (final error, final stack)) {
        _done.completeError(error, stack);
      } else {
        _done.complete();
      }
    }
  }
}

/// One connection to a [TerminalShell].
final class _Session {
  _Session(this._socket);

  final Socket _socket;

  /// The console is in raw mode for it.
  var raw = false;

  /// What puts the terminal back if it goes away ([Wire.lost]).
  List<int> lost = const [];

  var ended = false;

  void listen(
    void Function(int type, Uint8List payload) onFrame,
    void Function() onEnd,
  ) {
    final reader = FrameReader(onFrame);
    // what failed in a write is told by the reads, or doesn't matter
    unawaited(_socket.done.then<void>((_) {}, onError: (Object _) {}));
    _socket.listen(
      (bytes) {
        try {
          reader.add(bytes);
        } on FormatException {
          onEnd();
        }
      },
      onError: (Object _) => onEnd(),
      onDone: onEnd,
    );
  }

  void send(int type, [List<int> payload = const []]) {
    if (!ended) {
      _socket.add(frame(type, payload));
    }
  }

  void sendJson(int type, Object json) =>
      send(type, utf8.encode(jsonEncode(json)));

  /// Closes once what was sent is on its way.
  void close() {
    ended = true;
    unawaited(_socket.close().then<void>((_) {}, onError: (Object _) {}));
  }

  void destroy() => _socket.destroy();
}
