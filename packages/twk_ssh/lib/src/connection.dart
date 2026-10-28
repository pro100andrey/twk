/// One client's connection above the transport: the user authentication
/// (RFC 4252) and the connection protocol (RFC 4254) with its one
/// session channel.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'auth.dart';
import 'keys.dart';
import 'session.dart';
import 'transport.dart';
import 'wire.dart';

/// Called with a session once the client asks for a shell or a command;
/// the session ends when the future completes (see `SshConnection`).
typedef SessionHandler = FutureOr<void> Function(SshSession session);

/// Starts a timer that calls [callback] once [duration] has passed:
/// `Timer.new`, or a test's on a fake clock.
typedef SshTimers = Timer Function(Duration duration, void Function() callback);

/// One client's connection: authentication within `loginTimeout`, then
/// one session channel at a time; the connection ends once that channel
/// is closed and the client doesn't close the connection itself.
///
/// The session starts on the client's `shell` or `exec` request:
/// [onSession] runs it, and when its future completes the session exits
/// with status 0 ([SshSession.exit] called before gives the status),
/// with 1 when it throws, which goes to [onError].
final class SshConnection implements SessionTransport {
  /// The connection of [socket], proving itself with [hostKeys] and
  /// letting in whom [auth] accepts within [loginTimeout]; [version] is
  /// what its version line names after `SSH-2.0-`. Its keys change after
  /// [rekeyLimit], read on [clock] (see [SshTransport]); its deadlines
  /// (the login's, the second it waits for the client after the session)
  /// run on [timers], `Timer.new` by default.
  SshConnection(
    Socket socket, {
    required List<SshHostKey> hostKeys,
    required this.auth,
    required this.onSession,
    String version = 'twk_ssh_0.1',
    Duration loginTimeout = const Duration(minutes: 2),
    SshRekeyLimit rekeyLimit = const SshRekeyLimit(),
    Stopwatch? clock,
    SshTimers? timers,
    this.onError,
  }) : remoteAddress = socket.remoteAddress,
       remotePort = socket.remotePort,
       _timers = timers ?? Timer.new {
    transport = SshTransport(
      socket,
      hostKeys: hostKeys,
      version: version,
      onMessage: _onMessage,
      onClose: _onClose,
      rekeyLimit: rekeyLimit,
      clock: clock,
    );
    _loginTimer = _timers(
      loginTimeout,
      () => transport.disconnect(
        SshDisconnect.byApplication,
        'authentication timed out',
      ),
    );
  }

  /// The transport the connection runs on.
  late final SshTransport transport;

  /// Who may log in.
  final SshAuth auth;

  /// Runs the session once the client asks for a shell or a command.
  final SessionHandler onSession;

  /// Where an error that ends [onSession] goes.
  final void Function(Object error, StackTrace stack)? onError;

  /// The client's address.
  final InternetAddress remoteAddress;

  /// The client's port.
  final int remotePort;

  final SshTimers _timers;
  late final Timer _loginTimer;
  Timer? _lingerTimer;

  var _serviceAccepted = false;

  /// Who logged in; null until someone has.
  String? get user => _user;
  String? _user;
  SshPublicKey? _key;

  /// Failed attempts so far.
  int get failures => _failures;
  var _failures = 0;
  var _askedNone = false;

  SshSession? _session;

  /// The session channel open now.
  SshSession? get session => _session;

  /// Completes once the connection is closed.
  Future<void> get done => transport.done;

  @override
  void send(Uint8List payload) => transport.send(payload);

  @override
  void channelClosed() {
    _session = null;
    // the client normally goes now; one that stays is let go
    _lingerTimer = _timers(const Duration(seconds: 1), transport.close);
  }

  void _onClose() {
    _loginTimer.cancel();
    _lingerTimer?.cancel();
    _session?.connectionLost();
  }

  void _reply(SshWriter w) => transport.send(w.takeBytes());

  FutureOr<bool> _onMessage(Uint8List payload) {
    final id = payload[0];
    final r = SshReader(payload)..byte();
    switch (id) {
      case SshMsg.serviceRequest:
        final service = r.utf8String();
        if (_serviceAccepted || service != 'ssh-userauth') {
          throw SshProtocolException(
            'service $service',
            SshDisconnect.serviceNotAvailable,
          );
        }
        _serviceAccepted = true;
        _reply(
          SshWriter()
            ..byte(SshMsg.serviceAccept)
            ..utf8String(service),
        );
        return true;
      case SshMsg.userauthRequest:
        if (!_serviceAccepted) {
          throw const SshProtocolException('authentication before its service');
        }
        // once in, further requests are ignored (RFC 4252 §5.1)
        return _user == null ? _authenticate(r) : true;
    }
    if (id >= 80 && _user == null) {
      throw SshProtocolException('message $id before authentication');
    }
    switch (id) {
      case SshMsg.globalRequest:
        r.utf8String();
        if (r.boolean()) {
          _reply(SshWriter()..byte(SshMsg.requestFailure));
        }
        return true;
      case SshMsg.channelOpen:
        _open(r);
        return true;
      case SshMsg.channelWindowAdjust:
        _channel(r)?.receiveWindowAdjust(r.uint32());
        return true;
      case SshMsg.channelData:
        _channel(r)?.receiveData(r.string());
        return true;
      case SshMsg.channelExtendedData:
        final session = _channel(r);
        r.uint32();
        session?.receiveExtendedData(r.string().length);
        return true;
      case SshMsg.channelEof:
        _channel(r)?.receiveEof();
        return true;
      case SshMsg.channelClose:
        _channel(r)?.receiveClose();
        return true;
      case SshMsg.channelRequest:
        _request(r);
        return true;
      case SshMsg.channelSuccess || SshMsg.channelFailure:
        _channel(r);
        return true;
    }
    return false;
  }

  // ----------------------------------------------------- authentication --

  Future<bool> _authenticate(SshReader r) async {
    final user = r.utf8String();
    final service = r.utf8String();
    final method = r.utf8String();
    if (service != 'ssh-connection') {
      throw SshProtocolException(
        'service $service',
        SshDisconnect.serviceNotAvailable,
      );
    }
    switch (method) {
      case 'none' when !_askedNone:
        _askedNone = true;
        _failure(counted: false);
        return true;
      case 'publickey' when auth.publicKey != null:
        await _publicKey(user, r);
        return true;
      case 'password' when auth.password != null:
        final change = r.boolean();
        final password = r.utf8String();
        if (!change && await auth.password!(user, password)) {
          _success(user, null);
        } else {
          _failure();
        }
        return true;
    }
    _failure();
    return true;
  }

  Future<void> _publicKey(String user, SshReader r) async {
    final signed = r.boolean();
    final algorithm = r.utf8String();
    final blob = r.string();
    final signature = signed ? r.string() : null;
    SshPublicKey? key;
    try {
      key = SshPublicKey.decode(blob);
    } on FormatException {
      key = null;
    }
    if (key == null ||
        !key.algorithms.contains(algorithm) ||
        !await auth.publicKey!(user, key)) {
      _failure();
      return;
    }
    if (signature == null) {
      _reply(
        SshWriter()
          ..byte(SshMsg.userauthPkOk)
          ..utf8String(algorithm)
          ..string(blob),
      );
      return;
    }
    final data =
        (SshWriter()
              ..string(transport.sessionId!)
              ..byte(SshMsg.userauthRequest)
              ..utf8String(user)
              ..utf8String('ssh-connection')
              ..utf8String('publickey')
              ..boolean(true)
              ..utf8String(algorithm)
              ..string(blob))
            .takeBytes();
    if (key.verify(algorithm, data, signature)) {
      _success(user, key);
    } else {
      _failure();
    }
  }

  void _success(String user, SshPublicKey? key) {
    _user = user;
    _key = key;
    _loginTimer.cancel();
    _reply(SshWriter()..byte(SshMsg.userauthSuccess));
  }

  void _failure({bool counted = true}) {
    if (counted && ++_failures >= auth.maxAttempts) {
      transport.disconnect(
        SshDisconnect.noMoreAuthMethods,
        'too many authentication failures',
      );
      return;
    }
    _reply(
      SshWriter()
        ..byte(SshMsg.userauthFailure)
        ..nameList(auth.methods)
        ..boolean(false),
    );
  }

  // ------------------------------------------------------------ channels --

  /// The session the message read from [r] is for: the open one, null
  /// once it is over. Any other channel is a protocol error.
  SshSession? _channel(SshReader r) {
    final id = r.uint32();
    final session = _session;
    if (id != 0 || session == null) {
      throw SshProtocolException('no channel $id');
    }
    return session.isDone ? null : session;
  }

  void _open(SshReader r) {
    final type = r.utf8String();
    final sender = r.uint32();
    final window = r.uint32();
    final maxPacket = r.uint32();
    void refuse(int code, String why) => _reply(
      SshWriter()
        ..byte(SshMsg.channelOpenFailure)
        ..uint32(sender)
        ..uint32(code)
        ..utf8String(why)
        ..utf8String(''),
    );
    if (type != 'session') {
      return refuse(
        SshOpenFailure.administrativelyProhibited,
        'only sessions are served',
      );
    }
    if (_session != null || _lingerTimer != null) {
      return refuse(
        SshOpenFailure.resourceShortage,
        'one session per connection',
      );
    }
    if (maxPacket == 0) {
      return refuse(SshOpenFailure.resourceShortage, 'no room for data');
    }
    _session = SshSession(
      user: _user!,
      publicKey: _key,
      remoteAddress: remoteAddress,
      remotePort: remotePort,
      transport: this,
      remoteId: sender,
      remoteWindow: window,
      remoteMaxPacket: maxPacket,
    );
    _reply(
      SshWriter()
        ..byte(SshMsg.channelOpenConfirmation)
        ..uint32(sender)
        ..uint32(0)
        ..uint32(SshSession.window)
        ..uint32(SshSession.maxPacket),
    );
  }

  void _request(SshReader r) {
    final session = _channel(r);
    final type = r.utf8String();
    final wantReply = r.boolean();
    if (session == null) {
      return;
    }
    final started = session.started;
    final ok = session.request(type, r);
    if (wantReply) {
      _reply(
        SshWriter()
          ..byte(ok ? SshMsg.channelSuccess : SshMsg.channelFailure)
          ..uint32(0),
      );
    }
    if (!started && session.started) {
      _run(session);
    }
  }

  void _run(SshSession session) {
    unawaited(
      Future.sync(() => onSession(session)).then(
        (_) => session.exit(),
        onError: (Object e, StackTrace s) {
          onError?.call(e, s);
          return session.exit(1);
        },
      ),
    );
  }
}
