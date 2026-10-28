/// Where the local services of a project listen (a `twk shell`, an app's
/// log): a Unix domain socket, or TCP on the loopback interface where
/// there are none (Windows), with a token a client opens with. Each
/// service's address is kept in a file beside the project,
/// `.dart_tool/twk/<service>`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A local socket's address and the token a client sends first.
///
/// A service [bind]s one and keeps it in its address file ([write],
/// [fileOf]); a client reads it from there ([read]) and [connect]s. The
/// terminal of the `twk shell` serving the current project:
///
/// ```dart
/// final address = LocalAddress.read(LocalAddress.fileOf('shell'));
/// if (address != null) {
///   final terminal = await Terminal.connect(address);
///   await terminal.close();
/// }
/// ```
final class LocalAddress {
  /// The socket at [address] (a Unix domain socket's path, or the loopback
  /// interface with [port]) that [token] opens.
  const LocalAddress(this.address, this.port, this.token) : _temporary = null;

  const LocalAddress._bound(this.address, this.token, this._temporary)
    : port = 0;

  /// A Unix domain socket's path, or the loopback interface.
  final InternetAddress address;

  /// The TCP port; 0 for a Unix domain socket.
  final int port;

  /// What a client proves it read the address file with: the first thing
  /// it sends.
  final String token;

  /// The temporary directory [bind] made for the socket.
  final String? _temporary;

  /// The longest path of a Unix domain socket everywhere (`sun_path` holds
  /// 104 bytes on macOS, the terminating NUL included).
  static const _maxSocketPath = 103;

  /// The directory of the project [directory] is in: the nearest one, from
  /// [directory] up, holding a `pubspec.yaml`; [directory] when none does.
  /// [directory] is the current directory when not given.
  static String projectOf([String? directory]) {
    final start = Directory(directory ?? Directory.current.path).absolute;
    for (var dir = start; ; dir = dir.parent) {
      if (File('${dir.path}${Platform.pathSeparator}pubspec.yaml')
          .existsSync()) {
        return dir.path;
      }
      if (dir.parent.path == dir.path) {
        return start.path;
      }
    }
  }

  /// The directory a project's address files are kept in:
  /// `<project>/.dart_tool/twk`.
  static String directoryOf(String project) {
    final sep = Platform.pathSeparator;
    return '$project$sep.dart_tool${sep}twk';
  }

  /// The file the address of [service] of the project [directory] is in
  /// ([projectOf]) is kept in.
  static String fileOf(String service, [String? directory]) =>
      '${directoryOf(projectOf(directory))}${Platform.pathSeparator}$service';

  /// Listens on a new local socket: a Unix domain socket `<name>.sock` in
  /// [directory], or in a new directory of the system's temporary one when
  /// that path is too long for a socket; TCP on the loopback interface,
  /// on a port the OS picks, on Windows. A file left at the path (a
  /// socket nobody closed) is replaced.
  static Future<(ServerSocket, LocalAddress)> bind(
    String directory,
    String name,
  ) async {
    final token = _token();
    if (Platform.isWindows) {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      return (server, LocalAddress(server.address, server.port, token));
    }
    Directory(directory).createSync(recursive: true);
    var path = '$directory/$name.sock';
    String? temporary;
    if (utf8.encode(path).length > _maxSocketPath) {
      temporary = Directory.systemTemp.createTempSync('twk').path;
      path = '$temporary/$name.sock';
    }
    final file = File(path);
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.unixDomainSock) {
      file.deleteSync();
    }
    final address = InternetAddress(path, type: InternetAddressType.unix);
    final server = await ServerSocket.bind(address, 0);
    return (server, LocalAddress._bound(address, token, temporary));
  }

  /// Connects to the socket; throws [SocketException] when that fails.
  ///
  /// A connect reset by a server that closes before it answers (ECONNRESET)
  /// is thrown by dart:io as a bare [OSError]: it is thrown here as the
  /// [SocketException] every other failed connect is.
  Future<Socket> connect() async {
    try {
      return await Socket.connect(address, port);
    } on OSError catch (e) {
      throw SocketException(
        'Connection failed',
        osError: e,
        address: address,
        port: port,
      );
    }
  }

  /// Removes the socket's file, if it has one (a closed server leaves it
  /// behind), with the temporary directory [bind] made for it.
  void unlink() {
    if (address.type != InternetAddressType.unix) {
      return;
    }
    try {
      File(address.address).deleteSync();
    } on FileSystemException {
      // gone already: closing the server may remove it
    }
    final temporary = _temporary;
    if (temporary != null) {
      try {
        Directory(temporary).deleteSync();
      } on FileSystemException {
        // gone already
      }
    }
  }

  /// The address as an address file holds it: `unix:<path>` or
  /// `tcp:<host>:<port>`, then the token, on lines of their own.
  String encode() {
    final where = address.type == InternetAddressType.unix
        ? 'unix:${address.address}'
        : 'tcp:${address.address}:$port';
    return '$where\n$token\n';
  }

  /// What [encode] made; null for anything else.
  static LocalAddress? decode(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.length < 2 || lines[1].isEmpty) {
      return null;
    }
    final where = lines[0];
    final token = lines[1];
    if (where.startsWith('unix:') && where.length > 5) {
      return LocalAddress(
        InternetAddress(where.substring(5), type: InternetAddressType.unix),
        0,
        token,
      );
    }
    final colon = where.lastIndexOf(':');
    if (where.startsWith('tcp:') && colon > 4) {
      final host = InternetAddress.tryParse(where.substring(4, colon));
      final port = int.tryParse(where.substring(colon + 1));
      if (host != null && port != null) {
        return LocalAddress(host, port, token);
      }
    }
    return null;
  }

  /// The environment variable that names the `twk shell` an app with no
  /// terminal of its own takes (`Terminal.open`), ahead of the project's
  /// address file: what [toVariable] makes.
  ///
  /// A shell that serves one app, or one session of an editor, passes it
  /// to the app it starts, so that two such shells serve one project
  /// without an address file between them.
  static const shellVariable = 'TWK_SHELL';

  /// The address and its token on one line, as [shellVariable] holds it:
  /// `unix:<path>#<token>` or `tcp:<host>:<port>#<token>`, the token
  /// after the last `#`.
  ///
  /// ```dart
  /// final (server, address) = await LocalAddress.bind('/tmp/twk', 'shell');
  /// final env = {LocalAddress.shellVariable: address.toVariable()};
  /// await server.close();
  /// ```
  String toVariable() => '$this#$token';

  /// What [toVariable] made; null for anything else (no `#`, no token, a
  /// line break, an address [decode] doesn't take).
  static LocalAddress? fromVariable(String value) {
    final hash = value.lastIndexOf('#');
    if (hash < 0 || value.contains('\n') || value.contains('\r')) {
      return null;
    }
    return decode(
      '${value.substring(0, hash)}\n${value.substring(hash + 1)}\n',
    );
  }

  /// The address kept in [file]; null when there is none to read.
  static LocalAddress? read(String file) {
    try {
      return decode(File(file).readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }

  /// Keeps the address in [file], replacing the one there; the
  /// directories it is in are made as needed.
  void write(String file) {
    File(file).parent.createSync(recursive: true);
    File('$file.$pid')
      ..writeAsStringSync(encode(), flush: true)
      ..renameSync(file);
  }

  /// Removes [file] if it still holds this address: a newer server may
  /// have replaced it.
  void forget(String file) {
    if (read(file) == this) {
      try {
        File(file).deleteSync();
      } on FileSystemException {
        // gone already
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LocalAddress &&
      other.address == address &&
      other.port == port &&
      other.token == token;

  @override
  int get hashCode => Object.hash(address, port, token);

  /// `unix:<path>` or `tcp:<host>:<port>`: the address without its token.
  @override
  String toString() => encode().split('\n').first;

  static String _token() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}
