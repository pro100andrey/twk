/// A terminal link to xterm.js ([XtermLink]) over what it needs of an
/// xterm.js terminal ([XtermPort]): its input, its size and writing to it.
/// Nothing here is the browser's, so it runs on the VM too, over a port of
/// a test's own.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart' show TerminalLink;

// Examples can assume:
// import 'package:twk/twk.dart';
// import 'package:twk_core/twk_core.dart';
// import 'package:web/web.dart' as web;
// late web.HTMLElement element;

/// What an [XtermLink] needs of an xterm.js terminal: what `Xterm.port`
/// gives over xterm.js's `Terminal`, and a test's fake on the VM. Each
/// `on…` method adds a listener and returns what removes it (xterm.js's
/// `IDisposable.dispose`).
abstract interface class XtermPort {
  /// How many columns the terminal has (`cols`).
  int get columns;

  /// How many rows the terminal has (`rows`).
  int get rows;

  /// [listener] gets what the terminal sends the program (`onData`): keys,
  /// pastes, focus and mouse reports in SGR encoding, the answers to its
  /// queries.
  void Function() onData(void Function(String data) listener);

  /// [listener] gets the terminal's binary input (`onBinary`): a string of
  /// bytes, a character from U+0000 to U+00FF each (mouse reports in the
  /// X10 encoding).
  void Function() onBinary(void Function(String data) listener);

  /// [listener] gets each new size (`onResize`).
  void Function() onResize(void Function(int columns, int rows) listener);

  /// Writes [bytes] (UTF-8) to the terminal, which calls [written] once it
  /// parsed them (`write`'s callback). The terminal keeps [bytes] until
  /// then.
  void write(Uint8List bytes, void Function() written);
}

/// A [TerminalLink] to the xterm.js terminal behind a port, for
/// `Terminal.overLink`. Its input is what the terminal sends
/// ([XtermPort.onData], the binary input as its bytes); its output is
/// written to it, and a flush completes once the terminal parsed all of
/// it (the callback of its last write). Its resizes are the terminal's.
/// There are no console modes: xterm.js has no line discipline, its input
/// is raw, and Backspace sends 0x7F. Nothing is left to restore when the
/// page goes away.
///
/// A terminal of the page's own, run by a `Terminal` of the core:
///
/// ```dart
/// final xterm = Xterm(XtermOptions(fontSize: 14))..open(element);
/// final terminal = await Terminal.overLink(XtermLink(xterm.port));
/// await runApp(const Text('Hello'), terminal: terminal);
/// xterm.dispose();
/// ```
///
/// See also:
///
///  * `runWebApp`, which does all of that, and fits the terminal to its
///    element.
final class XtermLink implements TerminalLink {
  /// [environment] tells what the terminal is
  /// ([TerminalLink.environment]): by default [xtermEnvironment].
  XtermLink(this._port, {Map<String, String>? environment})
    : environment = environment ?? xtermEnvironment;

  /// What xterm.js is to a program: 256 colors and 24-bit ones.
  static const xtermEnvironment = {
    'TERM': 'xterm-256color',
    'COLORTERM': 'truecolor',
    'TERM_PROGRAM': 'xterm.js',
  };

  final XtermPort _port;

  @override
  final Map<String, String> environment;

  @override
  bool get windows => false;

  @override
  int get columns => _port.columns;

  @override
  int get lines => _port.rows;

  @override
  int? get eraseChar => 0x7F;

  @override
  void enterRaw() {}

  @override
  void restore() {}

  /// What removes the listeners [input] and [resizes] added.
  final _removers = <void Function()>[];

  late final StreamController<List<int>> _input = StreamController(
    onListen: () => _removers
      ..add(_port.onData((data) => _input.add(utf8.encode(data))))
      ..add(
        _port.onBinary(
          (data) => _input.add(
            Uint8List.fromList([for (final c in data.codeUnits) c & 0xFF]),
          ),
        ),
      ),
  );

  @override
  Stream<List<int>> get input => _input.stream;

  late final StreamController<void> _resizes = StreamController(
    onListen: () => _removers.add(_port.onResize((_, _) => _resizes.add(null))),
  );

  @override
  Stream<void> get resizes => _resizes.stream;

  var _closed = false;

  /// Writes the terminal has not called back for yet.
  var _unwritten = 0;

  /// Completed when [_unwritten] gets to 0.
  Completer<void>? _drained;

  @override
  void add(List<int> bytes) {
    if (_closed || bytes.isEmpty) {
      return;
    }
    _unwritten++;
    _port.write(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      _written,
    );
  }

  void _written() {
    if (_unwritten > 0 && --_unwritten == 0) {
      _drained?.complete();
      _drained = null;
    }
  }

  @override
  Future<void> flush() => _closed || _unwritten == 0
      ? Future.value()
      : (_drained ??= Completer<void>()).future;

  @override
  void restoreWith(List<int> bytes) {}

  /// Removes the listeners from the terminal and completes a pending
  /// [flush]; the terminal itself is left as it is, its owner's to
  /// dispose.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final remove in _removers) {
      remove();
    }
    _removers.clear();
    _drained?.complete();
    _drained = null;
    // done once listened to, which neither may ever be
    unawaited(_input.close());
    unawaited(_resizes.close());
  }
}
