import 'dart:io';

import 'package:ssh_template/ssh_template.dart';

// ssh: each client that logs in gets the app on its own terminal
//
//   dart run bin/main.dart [port]
//   ssh -t -p 2222 localhost
Future<void> main(List<String> args) async {
  final server = await serveCounter(
    port: args.isEmpty ? 2222 : int.parse(args.first),
  );
  stdout.writeln('serving: ssh -t -p ${server.port} localhost (Ctrl+C stops)');
  await ProcessSignal.sigint.watch().first;
  await server.close();
}
