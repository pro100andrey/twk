// An xterm.js terminal as an XtermLink sees it, on the VM.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:twk_web/src/link.dart';

/// An [XtermPort] that answers the core's probe as xterm.js 6.0.0 answers
/// it with its default options (src/common/InputHandler.ts and
/// src/browser/CoreBrowserTerminal.ts of @xterm/xterm 6.0.0): DA1 as
/// `CSI ? 1 ; 2 c` (`termName` 'xterm'); DECRQM of 2026 as reset (known),
/// of 2027, 2048, 69 and 2031 as not recognized; OSC 10 and 11 with its
/// theme's white and black; CPR with the cursor where the probe left it;
/// nothing to the kitty keyboard query (`CSI ? u`), XTVERSION, kitty's
/// graphics query (an APC, which its parser drops) and `CSI 16 t`
/// (answered only with `windowOptions.getCellSizePixels`).
///
/// As xterm.js does, it answers a write while it parses it, after the
/// write returned, and then calls the write's callback; while [hold] is
/// true the callbacks wait for [release].
final class FakeXterm implements XtermPort {
  FakeXterm({this.columns = 80, this.rows = 24});

  @override
  int columns;

  @override
  int rows;

  /// Every write, copied as it was handed over.
  final writes = <Uint8List>[];

  /// What was written, decoded.
  String get written => utf8.decode([for (final w in writes) ...w]);

  var hold = false;
  final _held = <void Function()>[];

  final _data = <void Function(String data)>[];
  final _binary = <void Function(String data)>[];
  final _resize = <void Function(int columns, int rows)>[];

  /// The listeners added and not removed.
  int get listeners => _data.length + _binary.length + _resize.length;

  /// Sends [data] to the program, as typing, a paste or a report does.
  void send(String data) {
    for (final l in [..._data]) {
      l(data);
    }
  }

  /// Sends [data], a string of bytes, as binary input.
  void sendBinary(String data) {
    for (final l in [..._binary]) {
      l(data);
    }
  }

  /// Resizes to [columns] by [rows], as `fit()` or `resize` does.
  void resize(int columns, int rows) {
    this.columns = columns;
    this.rows = rows;
    for (final l in [..._resize]) {
      l(columns, rows);
    }
  }

  /// Calls the callbacks [hold] kept back.
  void release() {
    final held = [..._held];
    _held.clear();
    for (final written in held) {
      written();
    }
  }

  @override
  void Function() onData(void Function(String data) listener) =>
      _add(_data, listener);

  @override
  void Function() onBinary(void Function(String data) listener) =>
      _add(_binary, listener);

  @override
  void Function() onResize(void Function(int columns, int rows) listener) =>
      _add(_resize, listener);

  void Function() _add<T>(List<T> listeners, T listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  @override
  void write(Uint8List bytes, void Function() written) {
    final copy = Uint8List.fromList(bytes);
    writes.add(copy);
    Timer.run(() {
      _answer(utf8.decode(copy, allowMalformed: true));
      if (hold) {
        _held.add(written);
      } else {
        written();
      }
    });
  }

  /// The modes DECRQM finds known: synchronized output, reset.
  static const _modes = {2026: 2};

  static final _query = RegExp(
    r'\x1b\[c|\x1b\[\?(\d+)\$p|\x1b\](1[01]);\?\x1b\\|(\x1b\[H─)?\x1b\[6n',
  );

  void _answer(String written) {
    for (final m in _query.allMatches(written)) {
      final s = m[0]!;
      if (s == '\x1b[c') {
        send('\x1b[?1;2c');
      } else if (m[1] case final mode?) {
        send('\x1b[?$mode;${_modes[int.parse(mode)] ?? 0}\$y');
      } else if (m[2] case final which?) {
        final rgb = which == '10' ? 'ffff/ffff/ffff' : '0000/0000/0000';
        send('\x1b]$which;rgb:$rgb\x1b\\');
      } else {
        send(m[3] == null ? '\x1b[1;1R' : '\x1b[1;2R');
      }
    }
  }
}
