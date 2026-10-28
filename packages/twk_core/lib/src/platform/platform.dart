/// What the core asks of the process it runs in: its environment, stdin
/// and stdout as a terminal, stderr, signals, files and local sockets
/// (`LocalAddress`, `SocketLink`, `TerminalShell`, `LogServer`). The core
/// reaches dart:io and dart:ffi through here only: `io.dart` on the VM;
/// on the web, which has none of these, `web.dart` stands in, so that
/// nothing a web app compiles in imports them. The web build is dart2wasm:
/// dart2js compiles the core too, but its Uint64List and Int64List, which
/// the cells are kept in, throw at run time.
library;

export 'io.dart' if (dart.library.js_interop) 'web.dart';
