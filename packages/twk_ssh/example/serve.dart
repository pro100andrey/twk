// A counter served over SSH: each client that logs in gets one of its own,
// greeted by name, with its terminal's size. Up counts, q quits.
//
//   dart run example/serve.dart [port]
//   ssh -p 2222 localhost
//
// Any user may log in with a key of ~/.ssh/authorized_keys; the host key
// is made in host_ed25519 the first time and kept there.
import 'dart:io';

import 'package:twk/twk.dart';
import 'package:twk_ssh/twk_ssh.dart';

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'] ?? '.';
  final server = await serveSsh(
    port: args.isEmpty ? 2222 : int.parse(args.first),
    hostKeys: [await SshHostKey.loadOrGenerate('host_ed25519')],
    authenticate: SshAuth.authorizedKeys('$home/.ssh/authorized_keys'),
    app: (session) => Counter(user: session.user),
    onError: (e, s) => stderr.writeln('a session failed: $e\n$s'),
  );
  stdout.writeln('serving: ssh -p ${server.port} localhost (Ctrl+C stops)');
  await ProcessSignal.sigint.watch().first;
  await server.close();
}

final class Counter extends StatefulWidget {
  const Counter({required this.user, super.key});

  /// Who logged in.
  final String user;

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => setState(() => _n++),
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
            Text('${size.maxW}x${size.maxH}'),
            Text.rich(['Count: '.dim, '$_n'.bold.fg(.green)]),
          ],
        ),
      ),
    ),
  );
}
