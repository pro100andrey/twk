/// Serving a twk app to SSH clients: [serveSsh].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show Terminal, TerminalException;

import 'auth.dart';
import 'keys.dart';
import 'link.dart';
import 'server.dart';
import 'session.dart';
import 'transport.dart';

// Examples can assume:
// import 'package:twk/twk.dart';

/// Builds the app of [session]: who logged in ([SshSession.user]), what
/// their client sent ([SshSession.environment], [SshSession.command]),
/// where from.
typedef SshApp = Widget Function(SshSession session);

/// Serves [app] to SSH clients on [address] and [port] (0: one the system
/// picks, [SshServer.port]): every session a client opens on a terminal
/// (`ssh -p 2222 host`) runs an app of its own, full screen, which
/// `app(session)` builds.
///
/// The server proves itself with [hostKeys] and lets in whom
/// [authenticate] accepts within [loginTimeout], at most
/// [maxUnauthenticated] clients at it at once, an address refused for a
/// while after its failures ([penalty], [penaltyExempt]), and changes
/// each connection's keys after [rekeyLimit] (see [SshServer.bind]).
/// Each session's terminal is opened over an [SshTerminalLink]
/// (`Terminal.overLink`): the client's `TERM`, size and Backspace byte,
/// its window's changes as resizes, what it types as input. When the app
/// quits ([AppBinding.quit], or Ctrl+C) its terminal is restored and the
/// session exits with status 0; when it ends with an error, that goes to
/// [onError] and the status is 1. A client that goes away ends its app.
/// A session without a terminal (`ssh -T`, a command without `-t`) is
/// told so and exits with 1.
///
/// The app is given what it knows of the client through `session` alone:
/// its binding's environment, which twk's own settings are read from
/// (`TWK_DEBUG`, `TWK_LOG`, `TWK_EDITOR`), is empty, neither the server
/// process's (which all sessions would share) nor the client's (which
/// would let it turn on debug aids or name an editor the server runs). An
/// environment given is the whole of it, so the terminal's settings
/// (`TerminalInfo.settings`) are not read either; over a link of the
/// program's own, as this one is, a terminal sets none anyway.
///
/// ```dart
/// Future<void> main() async {
///   final server = await serveSsh(
///     port: 2222,
///     hostKeys: [await SshHostKey.loadOrGenerate('host_ed25519')],
///     authenticate: SshAuth.authorizedKeys('authorized_keys'),
///     app: (session) => Text('hello ${session.user}'),
///   );
///   print('ssh -p ${server.port} localhost');
/// }
/// ```
Future<SshServer> serveSsh({
  required int port,
  required List<SshHostKey> hostKeys,
  required SshAuth authenticate,
  required SshApp app,
  Object? address,
  Duration loginTimeout = const Duration(minutes: 2),
  int maxUnauthenticated = 10,
  SshPenalty? penalty = const SshPenalty(),
  bool Function(InternetAddress address)? penaltyExempt,
  SshRekeyLimit rekeyLimit = const SshRekeyLimit(),
  void Function(Object error, StackTrace stack)? onError,
}) => SshServer.bind(
  address ?? InternetAddress.loopbackIPv4,
  port,
  hostKeys: hostKeys,
  auth: authenticate,
  onSession: (session) => _run(session, app),
  loginTimeout: loginTimeout,
  maxUnauthenticated: maxUnauthenticated,
  penalty: penalty,
  penaltyExempt: penaltyExempt,
  rekeyLimit: rekeyLimit,
  onError: onError,
);

Future<void> _run(SshSession session, SshApp app) async {
  if (session.pty == null) {
    session.add(
      utf8.encode('twk_ssh: the app needs a terminal (ssh -t)\r\n'),
    );
    return session.exit(1);
  }
  final widget = app(session);
  final link = SshTerminalLink(session);
  final Terminal terminal;
  try {
    terminal = await Terminal.overLink(link);
  } on TerminalException {
    // the client went away while the terminal was probed
    return session.exit(1);
  }
  final binding = AppBinding(terminal, environment: const {});
  // the client going away quits the app, which unmounts it
  link.onEnd = binding.quit;
  await binding.run(widget);
}
