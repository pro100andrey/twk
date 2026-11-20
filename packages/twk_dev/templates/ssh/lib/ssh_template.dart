import 'dart:io';

import 'package:twk/twk.dart';
import 'package:twk_ssh/twk_ssh.dart';

/// Serves a [Counter] to each client that logs in over SSH on [port] of
/// the loopback interface, one of its own to each, greeted by name.
///
/// Who may log in is [authenticate]: by default a key listed in
/// [authorizedKeysPath], the user's `~/.ssh/authorized_keys`, and nothing
/// else (no password). The server's identity is the key in [hostKeyPath],
/// made there the first time. The server listens on `127.0.0.1`; `address`
/// of `serveSsh` opens it to other machines.
Future<SshServer> serveCounter({
  required int port,
  String hostKeyPath = 'host_ed25519',
  String? authorizedKeysPath,
  SshAuth? authenticate,
}) async => serveSsh(
  port: port,
  hostKeys: [await SshHostKey.loadOrGenerate(hostKeyPath)],
  authenticate:
      authenticate ??
      SshAuth.authorizedKeys(
        authorizedKeysPath ??
            '${Platform.environment['HOME'] ?? '.'}/.ssh/authorized_keys',
      ),
  app: (session) => Counter(user: session.user),
  onError: (e, s) => stderr.writeln('a session failed: $e\n$s'),
);

/// A counter for [user], who logged in: up counts, q quits (and ends the
/// session).
final class Counter extends StatefulWidget {
  const Counter({required this.user, super.key});

  /// Who logged in.
  final String user;

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      {
        'up': () => setState(() => _count++),
        'q': () => AppBinding.of(context).quit(),
      },
      // the root's constraints are the terminal's size
      child: LayoutBuilder(
        builder: (context, size) => Box(
          border: const .all(type: .rounded),
          titles: const [
            BorderTitle(' up: count  q: quit ', alignment: .bottomRight),
          ],
          padding: const .all(1),
          child: Column(
            children: [
              Text.rich(['Hello, '.dim, widget.user.bold]),
              Text('${size.maxWidth}x${size.maxHeight}', style: theme.muted),
              Text.rich(['Count: '.dim, '$_count'.bold.fg(.green)]),
            ],
          ),
        ),
      ),
    );
  }
}
