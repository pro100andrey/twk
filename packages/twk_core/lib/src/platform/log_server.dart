/// The local socket a `LogSink` serves its records on (`LogSink.serve`),
/// as lines of text it is given: the platform's, so that it knows nothing
/// of the log above it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../terminal/address.dart';

/// The socket a `LogSink` serves its records on: a client that sends the
/// address's token and a line feed gets the lines of the backlog, then
/// every line [send] is given, each with a line feed.
final class LogServer {
  LogServer._(this._backlog, this._server, this.address, this._file) {
    _server.listen(_accept, onError: (Object _) {});
  }

  /// How many sinks of this process served: each socket's name is its own.
  static var _served = 0;

  /// Serves the lines of [backlog], asked for as each client is let in,
  /// then those given to [send], for the project [directory] is in. When
  /// the address can't be kept in its file, the socket is closed before
  /// that is thrown: left open, it would keep the process alive.
  static Future<LogServer> start(
    String? directory,
    Iterable<String> Function() backlog,
  ) async {
    final project = LocalAddress.projectOf(directory);
    final (server, address) = await LocalAddress.bind(
      LocalAddress.directoryOf(project),
      'logs-$pid-${_served++}',
    );
    final file = LocalAddress.fileOf('logs', project);
    try {
      await address.write(file);
    } on Object {
      // on Windows the socket is TCP's, bound before anything is made in
      // the project, so the address directory fails only here
      await server.close();
      address.unlink();
      rethrow;
    }
    return LogServer._(backlog, server, address, file);
  }

  final Iterable<String> Function() _backlog;
  final ServerSocket _server;

  /// Where the server listens: its address is in the project's `logs`
  /// address file while it does, for `twk logs` to find.
  final LocalAddress address;
  final String _file;

  /// The clients, each with whether it sent the token: those that did are
  /// sent the lines.
  final _clients = <Socket, bool>{};

  /// How many clients sent the token.
  var _letIn = 0;

  /// Whether a client sent the token: with none, a line need not be made
  /// to be [send].
  bool get serving => _letIn > 0;

  /// Sends [line] and a line feed to every client that sent the token.
  void send(String line) {
    if (_letIn == 0) {
      return;
    }
    final bytes = utf8.encode('$line\n');
    for (final MapEntry(key: client, value: served) in _clients.entries) {
      if (served) {
        client.add(bytes);
      }
    }
  }

  /// How long a client may take to send the token.
  static const _tokenTimeout = Duration(seconds: 5);

  void _accept(Socket client) {
    _clients[client] = false;
    unawaited(client.done.then<void>((_) {}, onError: (Object _) {}));
    final token = <int>[];
    final timer = Timer(_tokenTimeout, client.destroy);
    void end() {
      timer.cancel();
      _drop(client);
    }

    client.listen(
      (bytes) {
        if (_clients[client] ?? true) {
          return; // nothing more is asked of a client
        }
        token.addAll(bytes);
        final newline = token.indexOf(0x0A);
        if (newline < 0) {
          if (token.length > 256) {
            end();
          }
          return;
        }
        timer.cancel();
        if (utf8.decode(token.sublist(0, newline), allowMalformed: true) !=
            address.token) {
          end();
          return;
        }
        // the backlog in one write, not one of each line
        final backlog = StringBuffer();
        for (final line in _backlog()) {
          backlog
            ..write(line)
            ..writeCharCode(0x0A);
        }
        if (backlog.isNotEmpty) {
          client.add(utf8.encode(backlog.toString()));
        }
        _clients[client] = true;
        _letIn++;
      },
      onError: (Object _) => end(),
      onDone: end,
    );
  }

  void _drop(Socket client) {
    final served = _clients.remove(client);
    if (served != null) {
      if (served) {
        _letIn--;
      }
      client.destroy();
    }
  }

  /// Disconnects the clients, closes the socket and forgets the address
  /// file if it still holds this server's address.
  Future<void> close() async {
    _clients.keys.toList().forEach(_drop);
    await _server.close();
    address
      ..forget(_file)
      ..unlink();
  }
}
