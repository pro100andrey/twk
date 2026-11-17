/// [Session], a running app driven through the four ports.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:twk/twk.dart' show ElementFinder, KeyCombo;
import 'package:twk_core/twk_core.dart'
    show Clock, KeyEvent, MouseEvent, MouseKind, SystemClock;

import 'app_client.dart' show AppError, Json, VmAppClient;
import 'byte_log.dart';
import 'emulator_screen.dart';
import 'errors.dart';
import 'found.dart';
import 'ports.dart';
import 'pty_terminal.dart';

/// What the app posted at a frame or after an input, with the screen the
/// frame emulator had once it took the app's bytes up to it.
final class Seen {
  /// A processed event.
  const Seen({
    required this.seq,
    required this.kind,
    required this.frame,
    required this.drawn,
    required this.width,
    required this.height,
    required this.inputRead,
    required this.outputWritten,
    required this.inputPending,
    required this.scheduled,
    required this.frameDue,
    required this.time,
    required this.screen,
  });

  /// Its place among the events seen, from 0.
  final int seq;

  /// `twk.frame` or `twk.input`.
  final String kind;

  /// How many frames the app had run.
  final int frame;

  /// Whether a frame drew anything.
  final bool drawn;

  /// The size of the app's screen.
  final int width;

  /// The size of the app's screen.
  final int height;

  /// The bytes of input the app had taken in, as it counts them.
  final int inputRead;

  /// The bytes the app had accepted for the terminal.
  final int outputWritten;

  /// Whether the app's parser held input back.
  final bool inputPending;

  /// Whether a frame was asked for.
  final bool scheduled;

  /// When that frame was due, in microseconds of the app's clock.
  final int? frameDue;

  /// The app's clock, in microseconds.
  final int time;

  /// The screen at that boundary, as text.
  final String screen;

  /// Whether this is a frame, and not an acknowledgement of input.
  bool get isFrame => kind == 'twk.frame';
}

/// What an action returns: the frame it ended at and the screen.
final class Step {
  /// A step that ended at [frame].
  const Step(this.frame, this.screen, this.seen);

  /// The number of frames the app had run.
  final int frame;

  /// The screen as text.
  final String screen;

  /// The event the step ended at.
  final Seen seen;
}

/// What the app left behind when it ended, as an end-to-end check wants
/// it.
final class CloseReport {
  /// A report: [exitCode], whether the app [exitedByItself], and the
  /// [problems] found.
  const CloseReport(this.exitCode, this.exitedByItself, this.problems);

  /// The exit code, null where it is not known.
  final int? exitCode;

  /// Whether the app ended on its own, not by the driver's [Session.close]:
  /// only then do its terminal's modes say anything.
  final bool exitedByItself;

  /// What was not as an app that ends well leaves it: the tty not back in
  /// cooked mode, the alternate screen not left, the cursor hidden. Empty
  /// when nothing was.
  final List<String> problems;
}

/// A Linux or macOS `struct termios`' `c_lflag`.
int _lflag(Uint8List termios, {required bool macos}) => macos
    ? ByteData.sublistView(termios).getUint64(24, Endian.host)
    : ByteData.sublistView(termios).getUint32(12, Endian.host);

/// The ports a session is made of, each replaceable by a fake.
final class SessionPorts {
  /// Ports; none given is the real one.
  SessionPorts({
    ProcessPort? process,
    this.screen,
    this.connect,
    Clock? clock,
    this.macos = false,
  }) : process = process ?? PtyProcessPort(),
       clock = clock ?? SystemClock();

  /// Starts the app in a pseudo-terminal.
  final ProcessPort process;

  /// Makes the screens for the size; the emulators by default.
  final ScreenPort Function(int width, int height)? screen;

  /// Connects to the app's VM service at an address; [VmAppClient] by
  /// default.
  final Future<AppServicePort> Function(Uri uri)? connect;

  /// The time the driver's own timeouts run on.
  final Clock clock;

  /// Whether the terminal's attributes are macOS's (`c_lflag` 64 bits).
  final bool macos;
}

/// A twk app run as a process in a pseudo-terminal and driven from
/// outside: the keys it is given are real bytes, the screen is read through
/// an emulator, the widget tree through its VM service, and every action
/// returns once the app has drawn the frame that took the input in.
final class Session {
  Session._(this._launched, this._ports, this._screen, this._service);

  /// Starts [spec] and returns once the app has run its first frame.
  ///
  /// [timeout] bounds each wait of this session in time of the
  /// [SessionPorts.clock], the real one by default: an app that has not
  /// answered within it is reported, with its screen. The app ending
  /// answers every wait at once.
  static Future<Session> start(
    ProcessSpec spec, {
    SessionPorts? ports,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final p = ports ?? SessionPorts();
    final launched = await p.process.spawn(spec);
    final screen =
        p.screen?.call(spec.width, spec.height) ??
        EmulatorScreen(width: spec.width, height: spec.height);
    final session = Session._(launched, p, screen, null)..timeout = timeout;
    try {
      await session._init();
    } on Object {
      await session._kill();
      rethrow;
    }
    return session;
  }

  final Launched _launched;
  final SessionPorts _ports;
  final ScreenPort _screen;
  AppServicePort? _service;

  /// How long a wait of this session may last before it is reported.
  late Duration timeout;

  var _frameSize = (0, 0);
  final _log = ByteLog();
  var _fed = 0;
  var _written = 0;
  final _queue = Queue<AppEvent>();
  final _history = <Seen>[];
  var _seq = 0;
  final _waiters = <_Waiter>[];
  AppEnded? _ended;
  final _ending = Completer<int?>();
  var _outputDone = false;
  int? _exit;
  var _exited = false;
  var _closing = false;
  final _subs = <StreamSubscription<Object?>>[];

  TerminalPort get _terminal => _launched.terminal;

  /// The screen of the last frame seen, as the frame emulator shows it.
  ScreenView get screen => _screen.frame;

  /// The screen of the last frame seen, as text.
  String get screenText => _screen.frame.text;

  /// How many frames the app had run at the last event seen.
  int get frame => _history.isEmpty ? 0 : _history.last.frame;

  /// The bytes the driver has written: the app's input, and the answers to
  /// its queries.
  int get bytesWritten => _written;

  /// Completes with the app's exit code when the app has ended (null where
  /// it is not known): the process exited and its terminal ended, or its
  /// VM service closed.
  Future<int?> get exitCode => _ending.future;

  /// Whether the app has ended: exited, its terminal closed or its VM
  /// service gone.
  bool get ended => _ended != null;

  /// What the app wrote, as the terminal gave it.
  Uint8List get output => _log.slice(0, _log.rawLength);

  // -------------------------------------------------------------- start --

  Future<void> _init() async {
    _screen.answerTo(_write);
    _subs.add(
      _terminal.output.listen(
        _onBytes,
        onDone: () {
          _outputDone = true;
          _maybeEnd("the app's terminal ended");
        },
      ),
    );
    unawaited(
      _launched.exitCode.then((code) {
        _exit = code;
        _exited = true;
        _maybeEnd('the app exited');
      }),
    );
    final uri = await _race(_launched.serviceUri, 'the VM service address');
    final connect = _ports.connect ?? _connect;
    final service = await _race(connect(uri), 'the VM service');
    _service = service;
    unawaited(service.done.then((_) => _serviceClosed()));
    _subs.add(service.events.listen(_onEvent));
    await _call(service, 'flags', {'frameEvents': 'true'});
    final answer = await _call(service, 'find', {
      'finder': jsonEncode(const {
        'first': {'text': ''},
      }),
    });
    if ((answer['frame']! as int) == 0) {
      await _until(
        (s) => s.isFrame,
        from: 0,
        what: 'the first frame',
      );
    } else {
      // A frame ran before the events were asked for: another is, to have
      // a boundary of the app's output to start from.
      // See Session.start's note on drv-clock, whose status gives it.
      final from = _seq;
      await _call(service, 'reassemble');
      await _until((s) => s.isFrame, from: from, what: 'the first frame');
    }
  }

  static Future<AppServicePort> _connect(Uri uri) async {
    final service = await VmAppClient.connect(uri);
    return VmAppClient.attach(service, '$uri');
  }

  // ------------------------------------------------------------ the bytes --

  void _write(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }
    _written += bytes.length;
    _terminal.write(bytes);
  }

  void _onBytes(Uint8List raw) {
    _log.add(raw, onlcr: _terminal.nlToCrNl ?? true);
    _screen.feedAnswering(raw);
    _drain();
  }

  void _onEvent(AppEvent event) {
    if (event.kind == 'twk.frame' || event.kind == 'twk.input') {
      _queue.add(event);
      _drain();
    }
  }

  /// Feeds the frame emulator up to the boundary of each event whose bytes
  /// have arrived, in order.
  void _drain() {
    while (_queue.isNotEmpty) {
      final e = _queue.first;
      final d = e.data;
      final written = d['outputWritten'];
      if (written is! int) {
        _queue.removeFirst();
        _fail(
          'the app counts none of its output (its terminal is not a '
          'CountingBackend)',
        );
        return;
      }
      final offset = _log.rawOffsetFor(written);
      if (offset == null) {
        return;
      }
      _queue.removeFirst();
      final size = d['size']! as Map<Object?, Object?>;
      final w = size['width']! as int;
      final h = size['height']! as int;
      if ((w, h) != _frameSize) {
        _frameSize = (w, h);
        _screen.resizeFrame(w, h);
      }
      if (offset > _fed) {
        _screen.feedFrame(_log.slice(_fed, offset));
        _fed = offset;
      }
      final seen = Seen(
        seq: _seq++,
        kind: e.kind,
        frame: d['frame']! as int,
        drawn: d['drawn']! as bool,
        width: w,
        height: h,
        inputRead: d['inputRead']! as int,
        outputWritten: written,
        inputPending: d['inputPending']! as bool,
        scheduled: d['scheduled']! as bool,
        frameDue: d['frameDue'] as int?,
        time: d['time']! as int,
        screen: _screen.frame.text,
      );
      _history.add(seen);
      if (_history.length > 256) {
        _history.removeRange(0, 128);
      }
      for (final waiter in [..._waiters]) {
        waiter.offer(seen);
      }
    }
  }

  // ---------------------------------------------------------------- ends --

  /// How long the process is given to exit after its VM service closed,
  /// for its exit code, before the end is reported without it.
  static const _exitGrace = Duration(seconds: 2);

  void _serviceClosed() {
    if (_exited) {
      return;
    }
    // an app that ends closes its service first: its exit code follows
    final timer = _ports.clock.timer(_exitGrace, () {
      _fail("the app's VM service closed");
    });
    unawaited(_launched.exitCode.then((_) => timer.cancel()));
  }

  void _maybeEnd(String reason) {
    if (!_exited || !_outputDone) {
      return;
    }
    // everything the app wrote is on the screen it leaves
    final rest = _log.rawLength;
    if (rest > _fed) {
      _screen.feedFrame(_log.slice(_fed, rest));
      _fed = rest;
    }
    _fail(_closing ? 'the app was closed' : 'the app exited');
  }

  void _fail(String reason) {
    if (_ended != null) {
      return;
    }
    final ended = _ended = AppEnded(
      reason,
      exitCode: _exit,
      screen: _screen.frame.text,
      log: const [],
    );
    _ending.complete(_exit);
    for (final waiter in [..._waiters]) {
      waiter.fail(ended);
    }
  }

  /// [future], or the app's end, whichever comes first.
  Future<T> _race<T>(Future<T> future, String what) {
    final done = Completer<T>();
    final waiter = _Waiter(
      (_) => false,
      0,
      what,
      onFail: (e) {
        if (!done.isCompleted) {
          done.completeError(e);
        }
      },
      onSeen: (_) {},
    );
    _waiters.add(waiter);
    if (_ended case final e?) {
      waiter.fail(e);
    }
    unawaited(
      future.then(
        (v) {
          if (!done.isCompleted) {
            done.complete(v);
          }
        },
        onError: (Object e, StackTrace s) {
          if (!done.isCompleted) {
            done.completeError(e, s);
          }
        },
      ),
    );
    return done.future.whenComplete(() => _waiters.remove(waiter));
  }

  Future<Json> _call(
    AppServicePort service,
    String method, [
    Map<String, String> params = const {},
  ]) async {
    try {
      return await _race(service.call(method, params), 'ext.twk.$method');
    } on AppError catch (e) {
      throw DriverError('ext.twk.$method: ${e.message}');
    }
  }

  // --------------------------------------------------------------- waits --

  /// The first event seen from number [from] on that [test] accepts.
  Future<Seen> _until(
    bool Function(Seen) test, {
    required int from,
    required String what,
  }) {
    final done = Completer<Seen>();
    late final Timer timer;
    final waiter = _Waiter(
      test,
      from,
      what,
      onSeen: (s) {
        if (!done.isCompleted) {
          timer.cancel();
          done.complete(s);
        }
      },
      onFail: (e) {
        if (!done.isCompleted) {
          timer.cancel();
          done.completeError(e);
        }
      },
    );
    timer = _ports.clock.timer(timeout, () {
      if (!done.isCompleted) {
        done.completeError(
          DriverError(
            "no $what within $timeout of the driver's clock; the app has "
            'not answered. Screen at frame $frame:\n${_screen.frame.text}',
          ),
        );
      }
    });
    _waiters.add(waiter);
    done.future.whenComplete(() => _waiters.remove(waiter)).ignore();
    if (_ended case final e?) {
      waiter.fail(e);
    } else {
      // events seen since [from] that are held already
      for (final s in _history) {
        if (s.seq >= from) {
          waiter.offer(s);
        }
      }
    }
    return done.future;
  }

  /// Waits for the frame that took in the input up to the byte [target] of
  /// what was written (part 3.3 of DESIGN.md), the app's screen then.
  Future<Step> _settled(
    int target, {
    required int from,
    (int, int)? size,
  }) async {
    var seen = await _until(
      (s) =>
          s.inputRead >= target &&
          !s.inputPending &&
          (size == null || (s.width, s.height) == size),
      from: from,
      what: 'the frame that takes the input in',
    );
    if (!seen.isFrame && seen.scheduled) {
      seen = await _until(
        (s) => s.isFrame && s.inputRead >= target,
        from: seen.seq + 1,
        what: 'the frame the input asked for',
      );
    }
    return Step(seen.frame, seen.screen, seen);
  }

  Future<Step> _act(List<List<int>> writes) async {
    _checkOpen();
    Step? step;
    for (final bytes in writes) {
      final from = _seq;
      _write(bytes);
      step = await _settled(_written, from: from);
    }
    return step ?? Step(frame, _screen.frame.text, _history.last);
  }

  void _checkOpen() {
    if (_ended case final e?) {
      throw e;
    }
  }

  // ------------------------------------------------------------- actions --

  /// Presses each key of [keys] in turn, as key bindings name them, apart
  /// by spaces (`ctrl+s`, `shift+tab`, `g g`), in the bytes the app's
  /// modes ask for. Returns once the app has drawn the frame of each, the
  /// last one's step. A [DriverError] for a key the app's modes give no
  /// bytes for, and [AppEnded] where the app ended first (`press('q')` on
  /// an app that quits).
  Future<Step> press(String keys) {
    final writes = <List<int>>[];
    for (final combo in KeyCombo.parseSequence(keys)) {
      final bytes = _screen.encodeKey(
        KeyEvent(combo.code, char: combo.char, modifiers: combo.modifiers),
      );
      if (bytes.isEmpty) {
        throw DriverError('"$combo" has no bytes in the modes the app set');
      }
      writes.add(bytes);
    }
    return _act(writes);
  }

  /// Types [text], as the bytes of its characters in one write.
  Future<Step> type(String text) => _act([_screen.encodeText(text)]);

  /// Pastes [text], bracketed when the app asked for it.
  Future<Step> paste(String text) => _act([_screen.encodePaste(text)]);

  /// Sets the terminal's size and returns once the app has drawn a frame at
  /// it.
  Future<Step> resize(int width, int height) {
    _checkOpen();
    final from = _seq;
    _screen.resizeAnswering(width, height);
    _terminal.resize(width, height);
    return _settled(_written, size: (width, height), from: from);
  }

  // ---------------------------------------------------------- the screen --

  /// Waits until [test] accepts the screen of a frame (as text), the one
  /// shown now first and then each frame the app draws: none is missed
  /// between checks, since the frames are the app's own. [timeout]
  /// bounds it, on the driver's clock. Returns that frame's step. The app
  /// ending ends the wait too ([AppEnded]).
  Future<Step> waitForScreen(
    bool Function(String screen) test, {
    required Duration timeout,
    String what = 'the screen',
  }) async {
    final saved = this.timeout;
    this.timeout = timeout;
    try {
      final from = _history.isEmpty ? 0 : _history.last.seq;
      final seen = await _until(
        (s) => test(s.screen),
        from: from,
        what: what,
      );
      return Step(seen.frame, seen.screen, seen);
    } finally {
      this.timeout = saved;
    }
  }

  // ---------------------------------------------------------------- tree --

  /// The nodes [finder] matches, as the app's widgets see it.
  Future<List<Found>> find(ElementFinder finder) async {
    _checkOpen();
    final service = _service!;
    final answer = await _call(service, 'find', {
      'finder': jsonEncode(finder.toJson()),
    });
    return foundOf(answer);
  }

  /// The one node [finder] matches. Strict: a [DriverError] with the count
  /// and the first five matches when it matches none or more than one;
  /// `first`, `last` and `at` of the finder pick on purpose.
  Future<Found> findOne(ElementFinder finder) async {
    final found = await find(finder);
    if (found.length == 1) {
      return found.single;
    }
    throw DriverError(_notOne(found));
  }

  static String _node(Json n) => '${n['type']} (node ${n['id']})';

  String _notOne(List<Found> found) => found.isEmpty
      ? 'the finder matches nothing. Screen at frame $frame:\n'
            '${_screen.frame.text}'
      : 'the finder matches ${found.length} nodes, one is meant (use first, '
            'last or at to pick):\n'
            '${found.take(5).map((f) => '  $f').join('\n')}'
            '${found.length > 5 ? '\n  and ${found.length - 5} more' : ''}';

  /// Clicks the one node [finder] matches, after checking that a click
  /// there reaches it (part 6 of DESIGN.md): its middle cell, down and up,
  /// the app's frame awaited as for a key.
  Future<Step> tap(ElementFinder finder) async {
    final target = await findOne(finder);
    final shown = target.shown;
    if (shown == null) {
      throw DriverError('${target.describe} is not visible: no cell shows it');
    }
    if (!_screen.frame.alternateScreen) {
      throw const DriverError(
        'tap: the app is not on the alternate screen; the cell of a mouse '
        'report is not known for an inline app',
      );
    }
    var x = shown.x + shown.width ~/ 2;
    final y = shown.y + shown.height ~/ 2;
    if (_screen.frame.isContinuation(x, y)) {
      x--;
    }
    final hit = await _call(_service!, 'hitTest', {'x': '$x', 'y': '$y'});
    final path = [for (final n in hit['path']! as List<Object?>) n! as Json];
    final listeners = [
      for (final l in hit['listeners']! as List<Object?>) l! as Json,
    ];
    final label = '${target.describe} at cell $x,$y';
    if (hit['takenBy'] case final String taker) {
      throw DriverError('$label: the $taker takes the mouse, not the tree');
    }
    if (!path.any((n) => n['id'] == target.id)) {
      final top = path.isEmpty ? null : path.first;
      final under = path.skip(1).map(_node).join(', ');
      throw DriverError(
        '$label is covered by '
        '${top == null ? 'nothing the tree has' : _node(top)}'
        '${under.isEmpty ? '' : '; under it: $under'}',
      );
    }
    final takes = listeners.any(
      (l) => (l['callbacks']! as List<Object?>).any(
        (c) => c == 'down' || c == 'up',
      ),
    );
    if (!takes) {
      throw DriverError(
        '$label is reached, but nothing there takes a click',
      );
    }
    if (hit['absorbedBy'] != null) {
      throw DriverError(
        '$label: an AbsorbPointer (render ${hit['absorbedBy']}) takes the '
        'press',
      );
    }
    if (!_screen.mouseTracked) {
      throw const DriverError('the app does not track the mouse');
    }
    final down = _screen.encodeMouse(MouseEvent(MouseKind.down, x, y));
    final up = _screen.encodeMouse(MouseEvent(MouseKind.up, x, y));
    return _act([down, up]);
  }

  // --------------------------------------------------------------- close --

  /// Ends the session: the app is let go if it still runs, and what it
  /// left behind is checked when it ended by itself: the tty back in
  /// cooked mode, the alternate screen left, the cursor visible.
  Future<CloseReport> close() async {
    final byItself = _exited;
    if (!_exited) {
      _closing = true;
    }
    await _kill();
    final problems = <String>[];
    if (byItself) {
      final modes = _terminal.modesAtEnd;
      if (modes != null) {
        final lflag = _lflag(modes, macos: _ports.macos);
        final (icanon, echo, isig) = _ports.macos
            ? (0x100, 0x8, 0x1)
            : (0x2, 0x8, 0x1);
        if (lflag & icanon == 0 || lflag & echo == 0 || lflag & isig == 0) {
          problems.add(
            'the tty was left in raw mode '
            '(c_lflag 0x${lflag.toRadixString(16)})',
          );
        }
      }
      if (_screen.frame.alternateScreen) {
        problems.add('the alternate screen was not left');
      }
      if (!_screen.frame.cursorVisible) {
        problems.add('the cursor was left hidden');
      }
    }
    return CloseReport(_exit, byItself, problems);
  }

  Future<void> _kill() async {
    try {
      await _service?.close();
    } on Object {
      // gone already
    }
    await _launched.kill();
    for (final s in _subs) {
      await s.cancel();
    }
  }
}

/// A wait for an event seen that [test] accepts.
final class _Waiter {
  _Waiter(
    this.test,
    this.from,
    this.what, {
    required this.onSeen,
    required this.onFail,
  });

  final bool Function(Seen) test;
  final int from;
  final String what;
  final void Function(Seen) onSeen;
  final void Function(AppEnded) onFail;

  void offer(Seen seen) {
    if (seen.seq >= from && test(seen)) {
      onSeen(seen);
    }
  }

  void fail(AppEnded e) => onFail(e);
}
