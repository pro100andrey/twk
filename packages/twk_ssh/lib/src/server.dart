/// The server: a listening socket, one [SshConnection] per client.
library;

import 'dart:async';
import 'dart:io';

import 'auth.dart';
import 'connection.dart';
import 'keys.dart';
import 'transport.dart';
import 'wire.dart';

/// How long [SshServer] refuses an address whose connection ended without
/// a login after a failed attempt: [perFailure] for each such connection
/// (those at it at once adding up), [max] at most. OpenSSH's
/// `PerSourcePenalties`, `authfail` and `max`: guessing passwords costs
/// time, not only connections.
final class SshPenalty {
  /// [perFailure] for each connection that failed, [max] at most.
  const SshPenalty({
    this.perFailure = const Duration(seconds: 5),
    this.max = const Duration(minutes: 10),
  });

  /// How long an address is refused for each connection of it that ended
  /// without a login after a failed attempt.
  final Duration perFailure;

  /// The longest an address is refused for.
  final Duration max;
}

/// A minimal SSH server: it proves itself with its host keys, lets in whom
/// its [SshAuth] accepts, and runs each session a client asks for with the
/// `onSession` handler (see [SshConnection] for what a connection does).
final class SshServer {
  SshServer._(
    this._socket,
    this.maxUnauthenticated,
    this.penalty,
    this.penaltyExempt,
    this._clock,
    this._accept,
  );

  /// Listens on [address] and [port] (0: one the system picks).
  ///
  /// [loginTimeout] is how long a client has to log in, and
  /// [maxUnauthenticated] how many may be at it at once: a connection that
  /// comes while that many have not logged in yet is closed at once,
  /// before a byte is sent or read, as OpenSSH's `MaxStartups` starts to
  /// do at 10. An address whose connection ends without a login after a
  /// failed attempt is refused the same way for a while ([penalty], read
  /// on [clock]); null refuses none, and [penaltyExempt] says which never
  /// are (OpenSSH's `PerSourcePenaltyExemptList`). Behind a reverse proxy,
  /// a load balancer or Docker's userland proxy every client may come
  /// from the one address of it, and one client's failures would refuse
  /// them all: such a server exempts that address, or takes no penalty
  /// and leaves the limit to what is in front of it. Each connection's keys
  /// change after [rekeyLimit], its time read on [clock] too (a stopwatch
  /// of the connection's by default; a test's runs on a fake clock), and
  /// its deadlines on [timers]
  /// (`Timer.new` by default; see [SshConnection]). [version] is what the
  /// server's version line names after `SSH-2.0-`. An error that ends a
  /// session's handler goes to [onError].
  static Future<SshServer> bind(
    Object address,
    int port, {
    required List<SshHostKey> hostKeys,
    required SshAuth auth,
    required SessionHandler onSession,
    Duration loginTimeout = const Duration(minutes: 2),
    int maxUnauthenticated = 10,
    SshPenalty? penalty = const SshPenalty(),
    bool Function(InternetAddress address)? penaltyExempt,
    SshRekeyLimit rekeyLimit = const SshRekeyLimit(),
    Stopwatch? clock,
    SshTimers? timers,
    String version = 'twk_ssh_0.1',
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    if (hostKeys.isEmpty) {
      throw ArgumentError.value(hostKeys, 'hostKeys', 'no host key');
    }
    if (maxUnauthenticated < 1) {
      throw RangeError.value(
        maxUnauthenticated,
        'maxUnauthenticated',
        'must be at least 1',
      );
    }
    final socket = await ServerSocket.bind(address, port);
    return SshServer._(
      socket,
      maxUnauthenticated,
      penalty,
      penaltyExempt,
      clock ?? (Stopwatch()..start()),
      (client) => SshConnection(
        client,
        hostKeys: hostKeys,
        auth: auth,
        onSession: onSession,
        version: version,
        loginTimeout: loginTimeout,
        rekeyLimit: rekeyLimit,
        clock: clock,
        timers: timers,
        onError: onError,
      ),
    ).._listen();
  }

  /// How many clients may be connected without having logged in.
  final int maxUnauthenticated;

  /// How long an address whose connection ended without a login after a
  /// failed attempt is refused; null for none.
  final SshPenalty? penalty;

  /// Whether an address is never refused for [penalty].
  final bool Function(InternetAddress address)? penaltyExempt;

  final Stopwatch _clock;

  // the addresses refused, each until a time on _clock
  final _penalties = <InternetAddress, Duration>{};

  final ServerSocket _socket;
  final SshConnection Function(Socket client) _accept;
  late final StreamSubscription<Socket> _clients;
  final _connections = <SshConnection>{};

  /// The address the server listens on.
  InternetAddress get address => _socket.address;

  /// The port the server listens on: the one the system picked for 0.
  int get port => _socket.port;

  /// The clients connected now.
  Iterable<SshConnection> get connections => _connections;

  /// How many connections were closed at once for [maxUnauthenticated] or
  /// a penalty of their address.
  int get refused => _refused;
  var _refused = 0;

  void _listen() {
    _clients = _socket.listen((client) {
      final from = client.remoteAddress;
      final now = _clock.elapsed;
      final until = _penalties[from];
      if (until != null && until <= now) {
        _penalties.remove(from);
      }
      final unauthenticated = _connections.where((c) => c.user == null).length;
      if (unauthenticated >= maxUnauthenticated ||
          (until != null && until > now)) {
        _refused++;
        client.destroy();
        return;
      }
      final connection = _accept(
        client..setOption(SocketOption.tcpNoDelay, true),
      );
      _connections.add(connection);
      unawaited(
        connection.done.then((_) {
          _connections.remove(connection);
          if (connection.user == null &&
              connection.failures > 0 &&
              !(penaltyExempt?.call(from) ?? false)) {
            _penalise(from);
          }
        }),
      );
    });
  }

  void _penalise(InternetAddress address) {
    final p = penalty;
    if (p == null) {
      return;
    }
    final now = _clock.elapsed;
    final from = _penalties[address];
    final until = (from != null && from > now ? from : now) + p.perFailure;
    _penalties[address] = until - now > p.max ? now + p.max : until;
  }

  /// Stops listening and ends every connection.
  Future<void> close() async {
    await _clients.cancel();
    await _socket.close();
    final open = List.of(_connections);
    for (final c in open) {
      c.transport.disconnect(SshDisconnect.byApplication, 'server closing');
    }
    await Future.wait([for (final c in open) c.done]);
  }
}
