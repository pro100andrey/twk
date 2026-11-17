/// [Session], a running app driven through the four ports.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show pid;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:twk/twk.dart' show ElementFinder, KeyCombo;
import 'package:twk_core/terminal.dart' show LogRecord;
import 'package:twk_core/twk_core.dart'
    show Clock, KeyEvent, MouseEvent, MouseKind, SystemClock;

import 'app_client.dart' show AppError, Json, VmAppClient;
import 'byte_log.dart';
import 'clock_control.dart';
import 'emulator_screen.dart';
import 'errors.dart';
import 'found.dart';
import 'ports.dart';
import 'pty_terminal.dart';
import 'trace.dart';
import 'tree_text.dart';

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
    required this.quitting,
    required this.screen,
  });

  /// Its place among the events seen, from 0.
  final int seq;

  /// `twk.frame`, `twk.input` or `twk.scheduled`.
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

  /// Whether the app said it was quitting.
  final bool quitting;

  /// The screen at that boundary, as text.
  final String screen;

  /// Whether this is a frame, and not an acknowledgement of input.
  bool get isFrame => kind == 'twk.frame';
}

/// What an action returns: the frame it ended at and the screen.
final class Step {
  /// A step that ended at [frame]; [exit] is how the app ended, when it
  /// did.
  const Step(this.frame, this.screen, this.seen, {this.exit});

  /// The number of frames the app had run.
  final int frame;

  /// The screen as text.
  final String screen;

  /// The last event seen: the one the step ended at.
  final Seen seen;

  /// How the app ended, null while it runs. A step of an app that said it
  /// was quitting (`press('q')`) comes back with it, as does every call
  /// after: the same result each time. An app that ended unexpectedly is
  /// an [AppEnded] instead.
  final ExitResult? exit;
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
    int? driverPid,
  }) : process = process ?? PtyProcessPort(),
       clock = clock ?? SystemClock(),
       driverPid = driverPid ?? pid;

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

  /// The process id `TWK_DRIVEN` names: the driver's own, which the app
  /// takes the variable for only when it is its parent's.
  final int driverPid;
}

/// A twk app run as a process in a pseudo-terminal and driven from
/// outside: the keys it is given are real bytes, the screen is read through
/// an emulator, the widget tree through its VM service, and every action
/// returns once the app has drawn the frame that took the input in.
final class Session {
  Session._(
    this._launched,
    this._screen,
    this._clock,
    this._macos,
    this._driverPid,
    this._withService,
    this._driven,
    this._drivenValue,
  );

  /// Starts [spec] with the adapters of [ports] (the real ones by default:
  /// a Dart program in a pseudo-terminal, the emulators, the app's VM
  /// service) and returns once the app has run its first frame. It is
  /// [compose] with what a twk app needs.
  ///
  /// [timeout] bounds each wait of this session in time of the
  /// [SessionPorts.clock], the real one by default: an app that has not
  /// answered within it is reported, with its screen. The app ending
  /// answers every wait at once.
  ///
  /// With [driven] (the default) the app runs on the driver's time
  /// (`TWK_DRIVEN`, part 4 of DESIGN.md): its timers fire when [clock]
  /// moves it, `press` moves it only to the frame the input asked for, and
  /// [waitFor] moves it on until the screen is what it waits for. [startTime]
  /// is what the app's `AppBinding.now` reads when its clock is at zero;
  /// null, the real time at its start. [trace] makes the session write a
  /// trace ([Session.trace], part 8 of DESIGN.md). The start fails at once,
  /// naming the cause, where the app did not take the variable. Without
  /// [driven] the app runs on real time, and only the waits that take `io`
  /// are of use.
  static Future<Session> start(
    ProcessSpec spec, {
    SessionPorts? ports,
    Duration timeout = const Duration(seconds: 20),
    bool driven = true,
    DateTime? startTime,
    TraceOptions? trace,
  }) {
    final p = ports ?? SessionPorts();
    return compose(
      spec,
      process: p.process,
      screen:
          p.screen?.call(spec.width, spec.height) ??
          EmulatorScreen(width: spec.width, height: spec.height),
      connect: p.connect ?? _connect,
      clock: p.clock,
      timeout: timeout,
      driven: driven,
      startTime: startTime,
      macos: p.macos,
      driverPid: p.driverPid,
      trace: trace,
    );
  }

  /// Starts [spec] with [process] and drives it through the ports given: a
  /// session is these, and [start] only makes the adapters of a twk app.
  ///
  /// The terminal is the one [process] launches (a recorder wraps the
  /// [Launched] of its port in its own, see [TerminalPort.write]); [screen]
  /// is the caller's, of the size of [spec], themed as it likes: the
  /// session assumes nothing of it beyond [ScreenPort]; [clock] is the time
  /// the session's timeouts run on (a test's own, a recorder's).
  ///
  /// [connect] is what makes the session one of a twk app: it connects to
  /// the VM service at the address the program wrote, and the session then
  /// acts and waits by the frames the app posts, finds widgets and taps
  /// them, and with [driven] runs the app on the driver's time (as for
  /// [start]), and returns once the app has run its first frame. Without
  /// it (null) the program is any program in a terminal, a shell for one:
  ///
  ///  * `press`, `type`, `paste` and `resize` return as soon as the bytes
  ///    are written: nothing says when the program has taken them in, so
  ///    the step has the screen as it is;
  ///  * a wait ([waitFor], [waitForScreen]) looks at the screen each chunk
  ///    of output leaves it as, never at one drawn in part (inside a
  ///    synchronized update), and fails when [timeout] (or `io`, for
  ///    [waitFor]) has passed on [clock];
  ///  * `find`, `findOne`, `tap` and [clock] fail at once with "not a twk
  ///    app (no app service)";
  ///  * [driven] is meaningless (there is no app to take the time): it is
  ///    an [ArgumentError] to ask for it, and [Session.driven] is false;
  ///  * `exitCode`, `ended` and `close` are as for an app.
  static Future<Session> compose(
    ProcessSpec spec, {
    required ProcessPort process,
    required ScreenPort screen,
    Future<AppServicePort> Function(Uri uri)? connect,
    Clock? clock,
    Duration timeout = const Duration(seconds: 20),
    bool driven = false,
    DateTime? startTime,
    bool macos = false,
    int? driverPid,
    TraceOptions? trace,
  }) async {
    if (driven && connect == null) {
      throw ArgumentError.value(
        driven,
        'driven',
        'a program without an app service has no clock to drive',
      );
    }
    final me = driverPid ?? pid;
    final value = driven ? '$me${_at(startTime)}' : null;
    final launched = await process.spawn(
      value == null
          ? spec
          : ProcessSpec(
              spec.program,
              arguments: spec.arguments,
              workingDirectory: spec.workingDirectory,
              environment: {...spec.environment, 'TWK_DRIVEN': value},
              width: spec.width,
              height: spec.height,
            ),
    );
    return _open(
      launched,
      screen,
      clock ?? SystemClock(),
      timeout,
      macos,
      me,
      connect: connect,
      driven: driven,
      drivenValue: value,
      trace: trace,
      spec: spec,
    );
  }

  /// A session over a program that is running already: [launched], whose
  /// end and kill are the session's from here on, and [screen] and [clock]
  /// as for [compose]. [service] is the connection to the app's VM service,
  /// when it is a twk app (null: any program, see [compose]); [driven] says
  /// that it was started with `TWK_DRIVEN` for this process
  /// (`ext.twk.clock` then answers that it took it, or the attach fails).
  static Future<Session> attach(
    Launched launched, {
    required ScreenPort screen,
    AppServicePort? service,
    Clock? clock,
    Duration timeout = const Duration(seconds: 20),
    bool driven = false,
    bool macos = false,
    TraceOptions? trace,
  }) {
    if (driven && service == null) {
      throw ArgumentError.value(
        driven,
        'driven',
        'a program without an app service has no clock to drive',
      );
    }
    return _open(
      launched,
      screen,
      clock ?? SystemClock(),
      timeout,
      macos,
      pid,
      service: service,
      driven: driven,
      trace: trace,
    );
  }

  static Future<Session> _open(
    Launched launched,
    ScreenPort screen,
    Clock clock,
    Duration timeout,
    bool macos,
    int driverPid, {
    required bool driven,
    Future<AppServicePort> Function(Uri uri)? connect,
    AppServicePort? service,
    String? drivenValue,
    TraceOptions? trace,
    ProcessSpec? spec,
  }) async {
    final started = clock.elapsedMicroseconds;
    final session = Session._(
      launched,
      screen,
      clock,
      macos,
      driverPid,
      connect != null || service != null,
      driven,
      drivenValue,
    )..timeout = timeout;
    try {
      if (trace != null) {
        // inside the guard: a trace that cannot be opened ends the app
        // that was launched
        session._trace = TraceRecorder(
          trace,
          program: spec?.program ?? 'attached',
          arguments: spec?.arguments ?? const [],
          width: spec?.width ?? screen.frame.width,
          height: spec?.height ?? screen.frame.height,
          driven: driven,
          now: () =>
              Duration(microseconds: clock.elapsedMicroseconds - started),
        );
      }
      await session._init(connect, service);
    } on Object {
      await session._kill();
      rethrow;
    }
    return session;
  }

  final Launched _launched;
  final ScreenPort _screen;
  final Clock _clock;
  final bool _macos;
  final int _driverPid;
  final bool _withService;
  final bool _driven;
  final String? _drivenValue;
  AppServicePort? _service;

  /// How long a wait of this session may last before it is reported.
  late Duration timeout;

  TraceRecorder? _trace;
  _TraceStep? _current;
  var _steps = 0;
  var _chunks = 0;
  var _frameSize = (0, 0);
  final _log = ByteLog();
  var _fed = 0;
  var _written = 0;
  final _queue = Queue<AppEvent>();
  final _history = <Seen>[];
  var _seq = 0;
  final _waiters = <_Waiter>[];
  ExitResult? _ended;
  static const _logKept = 50;
  final _tail = <String>[];
  final _stepLog = <String>[];
  var _quitting = false;
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

  /// The trace this session writes, null where none was asked for
  /// ([start]'s `trace`).
  Trace? get trace => _trace;

  /// The last records of the app's log (`twk.log`), as text lines, oldest
  /// first: at most [_logKept] of them.
  List<String> get log => List.unmodifiable(_tail);

  /// What the app wrote, as the terminal gave it.
  Uint8List get output => _log.slice(0, _log.rawLength);

  // -------------------------------------------------------------- start --

  Future<void> _init(
    Future<AppServicePort> Function(Uri uri)? connect,
    AppServicePort? given,
  ) async {
    _screen.answerTo(_write);
    _subs.add(
      _terminal.output.listen(
        _onBytes,
        onDone: () {
          _outputDone = true;
          _maybeEnd();
        },
      ),
    );
    unawaited(
      _launched.exitCode.then((code) {
        _exit = code;
        _exited = true;
        _maybeEnd();
      }),
    );
    if (!_withService) {
      // any program: where it is, is what its terminal shows
      _noteOutput();
      return;
    }
    final AppServicePort service;
    if (given != null) {
      service = given;
    } else {
      final uri = await _race(_launched.serviceUri, 'the VM service address');
      service = await _race(connect!(uri), 'the VM service');
    }
    _service = service;
    unawaited(service.done.then((_) => _serviceClosed()));
    _subs.add(service.events.listen(_onEvent));
    await _call(service, 'flags', {'frameEvents': 'true'});
    // where the app is: the boundary of the output the first frame ended
    // at, whether a frame ran before the events were asked for or not. The
    // clock's status carries what the app's `status` does, and says
    // whether the app took the time the driver offered it.
    final status = await _call(service, _driven ? 'clock' : 'status');
    if (_driven && status['driven'] != true) {
      throw DriverError(
        'the app is not driven: it did not take TWK_DRIVEN'
        '${_drivenValue == null ? '' : '=$_drivenValue'}, '
        'which an app takes only when its parent process is the driver '
        '(pid $_driverPid). A program started through `dart run` '
        'has a process between; start it with `dart <file>` or compile it. '
        'Pass driven: false to run it on real time.',
      );
    }
    _queue.add(AppEvent('twk.input', status));
    _drain();
    if ((status['frame']! as int) == 0) {
      await _until((s) => s.isFrame, from: 0, what: 'the first frame');
    } else {
      await _until((_) => true, from: 0, what: 'the first screen');
    }
  }

  static String _at(DateTime? t) =>
      t == null ? '' : '@${t.toUtc().toIso8601String()}';

  static Future<AppServicePort> _connect(Uri uri) async {
    final service = await VmAppClient.connect(uri);
    return VmAppClient.attach(service, '$uri');
  }

  /// The hold on the app's time (`ext.twk.clock`): where it stands, and
  /// the moves of a driven app's clock.
  late final clock = ClockControl((params) {
    final op = params['op'] ?? 'status';
    Future<Json> call() => _call(_app('ext.twk.clock'), 'clock', params);
    return op == 'status' ? call() : _traced('clock.$op', {...params}, call);
  });

  /// The app's service, or the error of a session that has none.
  AppServicePort _app(String what) =>
      _service ??
      (_withService
          ? throw const DriverError('the app service is not connected yet')
          : throw DriverError(
              '$what: not a twk app (no app service): the session was made '
              'without one, and only a twk app gives its widget tree, taps and '
              'clock',
            ));

  /// Whether the app runs on the driver's time; false for a session without
  /// an app service.
  bool get driven => _driven;

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
    if (!_withService) {
      // no frames to wait for: the screen is what the bytes made of it
      _feed(_log.rawLength);
      if (!_screen.frame.updating) {
        _noteOutput();
      }
      return;
    }
    _drain();
  }

  /// Notes the screen as it is after a chunk of output, which a session
  /// without an app service waits on as one on an app waits on a frame.
  void _noteOutput() {
    _chunks++;
    _trace?.frame(
      _chunks,
      _trace!.lastOutput,
      _log.appLength,
      _log.rawLength,
    );
    final seen = Seen(
      seq: _seq++,
      kind: 'output',
      frame: 0,
      drawn: false,
      width: _screen.frame.width,
      height: _screen.frame.height,
      inputRead: 0,
      outputWritten: _log.appLength,
      inputPending: false,
      scheduled: false,
      frameDue: null,
      time: _clock.elapsedMicroseconds,
      quitting: false,
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

  void _onEvent(AppEvent event) {
    if (event.kind == 'twk.log') {
      _onLog(event.data);
      return;
    }
    if (event.kind == 'twk.frame' ||
        event.kind == 'twk.input' ||
        event.kind == 'twk.scheduled') {
      _queue.add(event);
      _drain();
    }
  }

  /// Keeps the records of a `twk.log` as text lines: the tail of the log,
  /// and what the step now running adds to its line of the trace.
  void _onLog(Json data) {
    final records = data['records'];
    if (records is! List<Object?>) {
      return;
    }
    for (final r in records) {
      if (r is! Map<String, Object?>) {
        continue;
      }
      String line;
      try {
        line = LogRecord.fromJson(r).toString();
      } on Object {
        line = '$r';
      }
      _tail.add(line);
      if (_tail.length > _logKept) {
        _tail.removeAt(0);
      }
      _stepLog.add(line);
      if (_stepLog.length > 200) {
        _stepLog.removeAt(0);
      }
    }
  }

  /// Feeds the frame emulator the bytes received up to [offset], and the
  /// trace's cast the same, in one event.
  void _feed(int offset) {
    if (offset <= _fed) {
      return;
    }
    final bytes = _log.slice(_fed, offset);
    _screen.feedFrame(bytes);
    _trace?.output(bytes);
    _fed = offset;
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
        _finish(
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
        final first = _frameSize == (0, 0);
        _frameSize = (w, h);
        _screen.resizeFrame(w, h);
        if (!first || (w, h) != _trace?.size) {
          _trace?.resize(w, h);
        }
      }
      _feed(offset);
      if (e.kind == 'twk.frame') {
        _trace?.frame(d['frame']! as int, _trace!.lastOutput, written, offset);
      }
      final seen = Seen(
        seq: _seq++,
        kind: e.kind,
        frame: d['frame']! as int,
        drawn: d['drawn'] as bool? ?? false,
        width: w,
        height: h,
        inputRead: d['inputRead']! as int,
        outputWritten: written,
        inputPending: d['inputPending']! as bool,
        scheduled: d['scheduled']! as bool,
        frameDue: d['frameDue'] as int?,
        time: d['time']! as int,
        quitting: d['quitting'] as bool? ?? false,
        screen: _screen.frame.text,
      );
      if (seen.quitting) {
        _quitting = true;
      }
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

  var _serviceDone = false;
  Timer? _grace;

  void _serviceClosed() {
    _serviceDone = true;
    if (_exited) {
      _maybeEnd();
    } else if (!_quitting) {
      // an app that ends closes its service first: its exit code follows
      _grace ??= _clock.timer(_exitGrace, () {
        _finish("the app's VM service closed");
      });
    }
    // an app that said it was quitting is waited for as long as it takes
  }

  void _maybeEnd() {
    if (!_exited || !_outputDone) {
      return;
    }
    if (_service != null && !_serviceDone) {
      // its last events come before the service closes: they say whether
      // the app was quitting
      _grace ??= _clock.timer(_exitGrace, _finishExited);
      return;
    }
    _finishExited();
  }

  void _finishExited() {
    // everything the app wrote is on the screen it leaves
    _feed(_log.rawLength);
    _finish(_closing ? 'the app was closed' : 'the app exited');
  }

  void _finish(String reason) {
    if (_ended != null) {
      return;
    }
    _grace?.cancel();
    final ended = _ended = ExitResult(
      code: _exit,
      screen: _screen.frame.text,
      log: List.unmodifiable(_tail),
      expected: _quitting || _closing,
      reason: reason,
    );
    _ending.complete(_exit);
    for (final waiter in [..._waiters]) {
      waiter.fail(AppEnded(ended));
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
      waiter.fail(AppEnded(e));
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

  /// The first event seen from number [from] on that [test] accepts, or
  /// the failure of a wait that lasts [within] (the session's [timeout]
  /// where not given) of the driver's clock: each wait has its own bound.
  Future<Seen> _until(
    bool Function(Seen) test, {
    required int from,
    required String what,
    Duration? within,
  }) {
    final bound = within ?? timeout;
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
    timer = _clock.timer(bound, () {
      if (!done.isCompleted) {
        done.completeError(
          DriverError(
            "no $what within $bound of the driver's clock; the app has "
            'not answered. Screen at frame $frame:\n${_screen.frame.text}',
          ),
        );
      }
    });
    _waiters.add(waiter);
    done.future.whenComplete(() => _waiters.remove(waiter)).ignore();
    if (_ended case final e?) {
      waiter.fail(AppEnded(e));
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
    try {
      var seen = await _until(
        (s) =>
            s.inputRead >= target &&
            !s.inputPending &&
            (size == null || (s.width, s.height) == size),
        from: from,
        what: 'the frame that takes the input in',
      );
      if (!seen.isFrame && seen.scheduled) {
        if (_driven && seen.frameDue != null) {
          // the input's frame is due a gap after the last: the clock moves
          // there, to that and nothing further
          await clock.advanceTo(math.max(seen.frameDue!, seen.time));
        }
        seen = await _until(
          (s) => s.isFrame && s.inputRead >= target,
          from: seen.seq + 1,
          what: 'the frame the input asked for',
        );
      }
      if (seen.quitting) {
        // the app said it is quitting: its exit is the answer
        await _until(
          (_) => false,
          from: seen.seq + 1,
          what: 'the app that said it is quitting to exit',
        );
      }
      return Step(seen.frame, seen.screen, seen);
    } on AppEnded catch (e) {
      if (e.expected) {
        return _exitStep(e.result);
      }
      rethrow;
    }
  }

  Step _exitStep(ExitResult result) => Step(
    _history.isEmpty ? 0 : _history.last.frame,
    result.screen,
    _history.last,
    exit: result,
  );

  /// The step of an app that has ended as it said it would; the error of
  /// one that did not; null while it runs.
  Step? _afterEnd() {
    final ended = _ended;
    if (ended == null) {
      return null;
    }
    if (!ended.expected) {
      throw AppEnded(ended);
    }
    return _exitStep(ended);
  }

  Future<Step> _act(List<List<int>> writes) async {
    if (_afterEnd() case final step?) {
      return step;
    }
    if (!_withService) {
      // nothing says when the program has taken the bytes in
      writes.forEach(_write);
      return Step(frame, _screen.frame.text, _history.last);
    }
    Step? step;
    for (final bytes in writes) {
      final from = _seq;
      _write(bytes);
      step = await _settled(_written, from: from);
      if (step.exit != null) {
        return step;
      }
    }
    return step ?? Step(frame, _screen.frame.text, _history.last);
  }

  void _checkOpen() {
    if (_ended case final e?) {
      throw AppEnded(e);
    }
  }

  // ------------------------------------------------------------- actions --

  /// Presses each key of [keys] in turn, as key bindings name them, apart
  /// by spaces (`ctrl+s`, `shift+tab`, `g g`), in the bytes the app's
  /// modes ask for. Returns once the app has drawn the frame of each, the
  /// last one's step. A [DriverError] for a key the app's modes give no
  /// bytes for. Where the app says it is quitting (`press('q')`), the step
  /// waits for its exit and has it as `exit`: the app exited (0); an
  /// [AppEnded] where the app ended without having said so.
  Future<Step> press(String keys) => _traced('press', {'keys': keys}, () {
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
  });

  /// Types [text], as the bytes of its characters in one write.
  Future<Step> type(String text) =>
      _traced('type', {'text': text}, () => _act([_screen.encodeText(text)]));

  /// Pastes [text], bracketed when the app asked for it.
  Future<Step> paste(String text) => _traced(
    'paste',
    {'text': text},
    () => _act([_screen.encodePaste(text)]),
  );

  /// Sets the terminal's size and returns once the app has drawn a frame at
  /// it.
  Future<Step> resize(int width, int height) => _traced(
    'resize',
    {'width': width, 'height': height},
    () => _resize(width, height),
  );

  Future<Step> _resize(int width, int height) async {
    if (_afterEnd() case final step?) {
      return step;
    }
    final from = _seq;
    _screen.resizeAnswering(width, height);
    if (!_withService) {
      _screen.resizeFrame(width, height);
      _terminal.resize(width, height);
      return Step(frame, _screen.frame.text, _history.last);
    }
    _terminal.resize(width, height);
    return _settled(_written, size: (width, height), from: from);
  }

  // ---------------------------------------------------------- the screen --

  /// Takes the clock's [status] as an acknowledgement of the app's
  /// input, which says what the app has run and written at the time of the
  /// answer, and returns once the frame emulator has the output it
  /// accounts for: the event that came of it.
  Future<Seen> _observe(ClockStatus status) {
    final seq = _seq + _queue.length;
    _queue.add(AppEvent('twk.input', status.json));
    _drain();
    return _until((s) => s.seq >= seq, from: seq, what: "the app's output");
  }

  /// Waits until [test] accepts the screen of a frame, the one shown now
  /// first, then each frame the app draws, none missed between checks.
  ///
  /// On a driven app it moves the app's time itself, from timer to timer,
  /// until the app's clock has moved [budget] (of app time, 10 s by
  /// default), and fails with "not within" and the timers that wait. An
  /// app that is quiet, with no timer, no frame asked for and nothing held
  /// in its input parser, will never change its screen by itself: that is
  /// "never", at once, with the frame, the screen and, where [near] is
  /// given, the line of it closest to that text. Real I/O in flight (a
  /// socket, a file, a process) is invisible to the clock, so a wait that
  /// involves any passes [io]: a quiet app is then waited on in real time,
  /// up to [io] (on the driver's clock), for frames that may still come.
  ///
  /// An app that does not run on the driver's time (`driven: false`) is
  /// waited on in real time up to [io], which is then required. The app
  /// ending ends the wait ([AppEnded]).
  Future<Step> waitFor(
    bool Function(String screen) test, {
    Duration budget = const Duration(seconds: 10),
    Duration? io,
    String what = 'the screen',
    String? near,
  }) => _traced('waitFor', {
    'what': what,
    'budget': budget.inMicroseconds,
    'io': ?io?.inMicroseconds,
    'near': ?near,
  }, () => _waitFor(test, budget: budget, io: io, what: what, near: near));

  Future<Step> _waitFor(
    bool Function(String screen) test, {
    required Duration budget,
    required Duration? io,
    required String what,
    required String? near,
  }) async {
    if (_afterEnd() case final step?) {
      return step;
    }
    final found = Completer<Seen>();
    final from = _history.isEmpty ? 0 : _history.last.seq;
    final waiter = _Waiter(
      (s) => test(s.screen),
      from,
      what,
      onSeen: (s) {
        if (!found.isCompleted) {
          found.complete(s);
        }
      },
      onFail: (e) {
        if (!found.isCompleted) {
          found.completeError(e);
        }
      },
    );
    _waiters.add(waiter);
    found.future.ignore();
    try {
      for (final s in [..._history]) {
        waiter.offer(s);
      }
      if (!found.isCompleted) {
        await _search(found, what: what, budget: budget, io: io, near: near);
      }
      final seen = await found.future;
      return Step(seen.frame, seen.screen, seen);
    } finally {
      _waiters.remove(waiter);
    }
  }

  Future<void> _search(
    Completer<Seen> found, {
    required String what,
    required Duration budget,
    required Duration? io,
    required String? near,
  }) async {
    if (!_driven) {
      // without a service the output is all there is to wait on, for as
      // long as the session's timeout
      final limit = io ?? (_withService ? null : timeout);
      if (limit == null) {
        throw const DriverError(
          'waitFor on an app that is not driven waits in real time, for '
          'which it needs io: how long',
        );
      }
      final expired = Completer<void>();
      final timer = _clock.timer(limit, expired.complete);
      try {
        await Future.any([found.future, expired.future]);
      } finally {
        timer.cancel();
      }
      if (!found.isCompleted) {
        throw DriverError(
          "no $what within ${_seconds(limit)} of the driver's clock. "
          'Screen at frame $frame:\n${_screen.frame.text}',
        );
      }
      return;
    }
    final first = await clock.status();
    final begun = first.time;
    int? ioEnd;
    var status = first;
    while (!found.isCompleted) {
      status = await clock.status();
      final seen = await _observe(status);
      if (found.isCompleted) {
        return;
      }
      if (status.inputRead < _written) {
        // the app has not read what was written: its next event says more
        if (await _eventWithin(
              seen.seq + 1,
              timeout,
              'the app to read input',
            ) ==
            null) {
          throw _stuck(what, 'the app to read what was written to it', seen);
        }
        continue;
      }
      if (status.quiet ?? false) {
        if (io != null) {
          final end = ioEnd ??= _clock.elapsedMicroseconds + io.inMicroseconds;
          final left = end - _clock.elapsedMicroseconds;
          if (left > 0) {
            // what comes in from outside (a child's answer, a socket) asks
            // for a frame the app's clock has not reached: the app says so
            // with a `twk.scheduled` event, which ends this wait; none,
            // and it ends with the io time, on the driver's clock
            await _eventWithin(
              seen.seq + 1,
              Duration(microseconds: left),
              what,
            );
            continue;
          }
        }
        throw _never(what, seen, near, io);
      }
      if (status.time - begun >= budget.inMicroseconds) {
        break;
      }
      final due = status.nextDue;
      if (due == null) {
        // not quiet, yet no timer: something real, an escape that waits
        // out its timeout, a frame that is being written
        if (await _eventWithin(seen.seq + 1, timeout, 'the app to settle') ==
            null) {
          throw _stuck(what, 'the app to settle', seen);
        }
        continue;
      }
      await clock.advanceTo(
        math.min(math.max(due, status.time), begun + budget.inMicroseconds),
      );
    }
    if (found.isCompleted) {
      return;
    }
    final last = await clock.status(describe: true);
    final screen = _screen.frame.text;
    throw DriverError(
      'no $what within ${_seconds(budget)} of app time (the clock moved '
      '${((last.time - begun) / 1e6).toStringAsFixed(3)} s, to frame '
      '${last.frame}). Timers waiting:\n${last.describeTimers(last.time)}\n'
      'Screen at frame $frame:\n$screen',
    );
  }

  /// The first event from number [from] on, or null once [within] has
  /// passed on the driver's clock.
  Future<Seen?> _eventWithin(int from, Duration within, String what) async {
    try {
      return await _until(
        (_) => true,
        from: from,
        what: what,
        within: within,
      );
    } on AppEnded {
      rethrow;
    } on DriverError {
      return null;
    }
  }

  /// The app did nothing for [timeout] of the driver's clock where [waited]
  /// was to happen: the wait for [what] fails, with the screen.
  DriverError _stuck(String what, String waited, Seen seen) => DriverError(
    'no $what: $waited did not happen within ${_seconds(timeout)} of the '
    "driver's clock, at frame ${seen.frame}.\n"
    'Screen at frame ${seen.frame}:\n${seen.screen}',
  );

  DriverError _never(String what, Seen seen, String? near, Duration? io) {
    final lines = seen.screen.split('\n');
    final closest = near == null ? null : _closestLine(lines, near);
    return QuietApp(
      before:
          'never: no $what at frame ${seen.frame}, and nothing will change '
          'it: the app is quiet (no timer waits, no frame is asked for, '
          'nothing is held in its input parser)'
          '${io == null ? '' : ' and nothing came in ${_seconds(io)}'}. '
          'Real I/O in flight (a socket, a file, a process) is invisible to '
          "the app's clock: ",
      ioGiven: io != null,
      after:
          '.${closest == null ? '' : '\nClosest line: "${closest.trim()}"'}'
          '\nScreen at frame ${seen.frame}:\n${seen.screen}',
    );
  }

  static String _seconds(Duration d) {
    final s = d.inMicroseconds / 1e6;
    return '${s == s.roundToDouble() ? s.round() : s} s';
  }

  /// The line of [lines] that shares the most pairs of characters with
  /// [text]; null where none shares any.
  static String? _closestLine(List<String> lines, String text) {
    Set<String> pairs(String s) => {
      for (var i = 0; i + 1 < s.length; i++) s.substring(i, i + 2),
    };
    final want = pairs(text);
    String? best;
    var bestScore = 0;
    for (final line in lines) {
      final score = pairs(line).where(want.contains).length;
      if (score > bestScore) {
        best = line;
        bestScore = score;
      }
    }
    return best;
  }

  /// Waits until [test] accepts the screen of a frame (as text), the one
  /// shown now first and then each frame the app draws: none is missed
  /// between checks, since the frames are the app's own. [timeout]
  /// bounds it, on the driver's clock. Returns that frame's step. The app
  /// ending ends the wait too ([AppEnded]).
  Future<Step> waitForScreen(
    bool Function(String screen) test, {
    required Duration timeout,
    String what = 'the screen',
  }) => _traced(
    'waitForScreen',
    {'what': what, 'timeout': timeout.inMicroseconds},
    () => _waitForScreen(test, timeout: timeout, what: what),
  );

  Future<Step> _waitForScreen(
    bool Function(String screen) test, {
    required Duration timeout,
    required String what,
  }) async {
    final from = _history.isEmpty ? 0 : _history.last.seq;
    final seen = await _until(
      (s) => test(s.screen),
      from: from,
      what: what,
      within: timeout,
    );
    return Step(seen.frame, seen.screen, seen);
  }

  // ---------------------------------------------------------------- tree --

  /// The nodes [finder] matches, as the app's widgets see it.
  Future<List<Found>> find(ElementFinder finder) =>
      _traced('find', const {}, () => _find(finder), finder: finder);

  Future<List<Found>> _find(ElementFinder finder) async {
    final service = _app('find');
    _checkOpen();
    final answer = await _call(service, 'find', {
      'finder': jsonEncode(finder.toJson()),
    });
    return foundOf(answer);
  }

  /// The one node [finder] matches. Strict: a [DriverError] with the count
  /// and the first five matches when it matches none or more than one;
  /// `first`, `last` and `at` of the finder pick on purpose.
  Future<Found> findOne(ElementFinder finder) => _traced(
    'findOne',
    const {},
    () async {
      final found = await find(finder);
      if (found.length == 1) {
        _current?.target = found.single;
        return found.single;
      }
      throw DriverError(_notOne(found));
    },
    finder: finder,
  );

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
  Future<Step> tap(ElementFinder finder) =>
      _traced('tap', const {}, () => _tap(finder), finder: finder);

  Future<Step> _tap(ElementFinder finder) async {
    _app('tap');
    if (_afterEnd() case final step?) {
      return step;
    }
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
    final hit = await _call(_app('tap'), 'hitTest', {'x': '$x', 'y': '$y'});
    _current?.hit = hit;
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
        final lflag = _lflag(modes, macos: _macos);
        final (icanon, echo, isig) = _macos
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
    // what the app wrote since the last boundary, in the cast
    _trace
      ?..output(_log.slice(_fed, _log.rawLength))
      ..close();
  }

  // --------------------------------------------------------------- trace --

  /// How long the trace waits for the widget tree at the end of a step.
  static const _treeWait = Duration(seconds: 2);

  /// Runs [body] as a step of the trace: a marker in the cast before it,
  /// a line of the trace after it. A step inside a step (a tap's finder
  /// search, a wait's moves of the clock) is part of the outer one.
  Future<T> _traced<T>(
    String action,
    Map<String, Object?> args,
    Future<T> Function() body, {
    ElementFinder? finder,
  }) async {
    final trace = _trace;
    if (trace == null || _current != null) {
      return body();
    }
    final n = ++_steps;
    final step = _current = _TraceStep(
      n,
      action,
      args,
      finder?.toJson(),
      frameBefore: _traceFrame,
      castEvent: trace.marker(
        '$n $action${args.isEmpty ? '' : ' ${jsonEncode(args)}'}',
      ),
    );
    try {
      return await body();
    } on Object catch (e) {
      step.error = '$e';
      rethrow;
    } finally {
      try {
        await _endStep(trace, step);
      } finally {
        _current = null;
      }
    }
  }

  /// The frame the trace counts: the app's, or for a program without an
  /// app service each chunk of output.
  int get _traceFrame => _withService ? frame : _chunks;

  Future<void> _endStep(TraceRecorder trace, _TraceStep step) async {
    String? tree;
    final service = _service;
    if (service != null && _ended == null) {
      try {
        final answer = await _within(service.call('tree'), _treeWait);
        tree = trace.tree(_traceFrame, treeText(answer));
      } on Object {
        // no tree to keep: the app is gone or does not answer
      }
    }
    final target = step.target;
    // what the app logged during the step, and what the options' own
    // source adds
    final log = [..._stepLog];
    _stepLog.clear();
    try {
      log.addAll(trace.options.log?.call() ?? const []);
    } on Object {
      // no records of that source
    }
    trace.step({
      'step': step.n,
      'action': step.action,
      'args': step.args,
      'finder': step.finder,
      'target': target == null
          ? null
          : {
              'id': target.id,
              'type': target.type,
              'shown': target.shown == null
                  ? null
                  : {
                      'x': target.shown!.x,
                      'y': target.shown!.y,
                      'width': target.shown!.width,
                      'height': target.shown!.height,
                    },
            },
      'hit': step.hit,
      'frameBefore': step.frameBefore,
      'frame': _traceFrame,
      'castEvent': step.castEvent,
      'appTime': _history.isEmpty ? null : _history.last.time,
      'realTime': _clock.elapsedMicroseconds,
      'result': step.error == null ? 'ok' : 'error',
      'error': step.error,
      'tree': tree,
      'log': log,
    });
  }

  /// [future], or a [DriverError] once [wait] has passed on the driver's
  /// clock.
  Future<T> _within<T>(Future<T> future, Duration wait) {
    final done = Completer<T>();
    final timer = _clock.timer(wait, () {
      if (!done.isCompleted) {
        done.completeError(const DriverError('no answer'));
      }
    });
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
    return done.future.whenComplete(timer.cancel);
  }
}

/// A step of the trace under way.
final class _TraceStep {
  _TraceStep(
    this.n,
    this.action,
    this.args,
    this.finder, {
    required this.frameBefore,
    required this.castEvent,
  });

  final int n;
  final String action;
  final Map<String, Object?> args;
  final Object? finder;
  final int frameBefore;
  final int castEvent;
  Found? target;
  Json? hit;
  String? error;
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
  final void Function(Object) onFail;

  void offer(Seen seen) {
    try {
      if (seen.seq >= from && test(seen)) {
        onSeen(seen);
      }
    } on Object catch (e) {
      // the caller's predicate threw: this wait fails with it, the others
      // are offered the event all the same
      onFail(e);
    }
  }

  void fail(AppEnded e) => onFail(e);
}
