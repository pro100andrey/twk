/// Output of a program with ANSI escape sequences turned into lines of
/// spans, whole or as it streams in: [parseAnsi], [AnsiStream].
///
/// @docImport 'package:twk/twk.dart';
/// @docImport 'strip.dart';
library;

// Examples can assume:
// import 'dart:io';
// import 'package:twk/twk.dart';
// void setState(void Function() fn) {}

import 'dart:convert';

import 'package:twk/twk.dart' show Span, Style;

import 'escapes.dart';
import 'line.dart';
import 'rendition.dart';

/// The lines of [text], output of a program with ANSI escape sequences, as
/// [AnsiStream] reads it, a tab moving to the next multiple of [tabWidth]
/// columns.
///
/// A program's output shown in its colors, a [Text.rich] per line:
///
/// ```dart
/// final lines = parseAnsi('\x1B[1;32mPASS\x1B[0m 3 tests\n');
/// Column(children: [for (final line in lines) Text.rich(line)]);
/// ```
List<List<Span>> parseAnsi(String text, {int tabWidth = 8}) =>
    (AnsiStream(tabWidth: tabWidth)
          ..add(text)
          ..close())
        .lines;

/// Output of a program, such as a compiler or a test runner, that arrives
/// in pieces, read as lines of spans: the lines a terminal would show it in,
/// with nothing in them that could act on the terminal they are drawn on.
///
/// SGR sequences style the text, in 16, 256 or 24-bit colors, in either the
/// `;` or the `:` form, and OSC 8 hyperlinks become [Style.link]s; a color
/// or attribute they reset is unset in the style. A line is written as a
/// terminal writes it: a carriage return or a backspace moves back over the
/// line, for text written after it to replace (so a progress line ends as
/// its last state), EL (`CSI K`) erases in it, and a tab moves to the next
/// multiple of [tabWidth] columns. Every other sequence, whether it moves
/// the cursor, erases the screen, sets a title or a mode, or is a DCS, APC,
/// PM or SOS string, is dropped whole, and so are the other C0 and C1
/// controls.
///
/// A piece may end anywhere, within a sequence or, for [addBytes], within a
/// UTF-8 character: what is cut off waits for the next piece. After
/// [close], adding more is a [StateError].
///
/// A command's output read as it runs, its lines shown after each piece:
///
/// ```dart
/// final output = AnsiStream();
/// final process = await Process.start('dart', ['test']);
/// process.stdout.listen(
///   (bytes) => setState(() => output.addBytes(bytes)),
///   onDone: () => setState(output.close),
/// );
/// // in build:
/// Column(children: [for (final line in output.lines) Text.rich(line)]);
/// ```
///
/// See also:
///
///  * [parseAnsi], the same for output that is all there.
///  * [stripAnsi], the text without the sequences, not read into lines.
final class AnsiStream {
  /// An empty stream, whose tabs move to the next multiple of [tabWidth]
  /// columns, 8 by default; [tabWidth] is at least 1.
  AnsiStream({this.tabWidth = 8}) : assert(tabWidth > 0, 'tabWidth < 1');

  /// Columns between tab stops.
  final int tabWidth;

  final _rendition = Rendition();
  final _line = LineBuffer();
  final _settled = <List<Span>>[];
  List<List<Span>>? _lines;
  var _closed = false;

  /// A high surrogate that ended the last text added.
  String? _high;
  ByteConversionSink? _decoder;

  late final _reader = EscapeReader(
    text: (text) => _line.write(text, _rendition.style),
    control: _control,
    csi: _csi,
    osc: _osc,
  );

  /// The lines so far: those ended, then the one being written, unless no
  /// cell of it is written yet.
  List<List<Span>> get lines => _lines ??= List.unmodifiable([
    ..._settled,
    if (!_line.isEmpty) _line.spans(),
  ]);

  /// How many of [lines], from the first, are ended: no output added later
  /// changes them, and [lines] keeps holding them as the very objects it
  /// held.
  int get settled => _settled.length;

  /// Reads [text].
  void add(String text) {
    _checkOpen();
    var s = text;
    if (_high != null) {
      s = _high! + s;
      _high = null;
    }
    if (s.isNotEmpty) {
      final last = s.codeUnitAt(s.length - 1);
      if (last >= 0xD800 && last <= 0xDBFF) {
        _high = s.substring(s.length - 1);
        s = s.substring(0, s.length - 1);
      }
    }
    _read(s);
  }

  /// Reads [bytes] of UTF-8; malformed bytes are U+FFFD.
  void addBytes(List<int> bytes) {
    _checkOpen();
    (_decoder ??= const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(_Reader(_read))).add(bytes);
  }

  /// Ends the output: the last line is ended, a UTF-8 character or a
  /// surrogate pair cut off is U+FFFD, and a sequence cut off is dropped.
  void close() {
    if (_closed) {
      return;
    }
    _decoder?.close();
    if (_high != null) {
      _high = null;
      _read('\uFFFD');
    }
    _reader.end();
    if (!_line.isEmpty) {
      _endLine();
    }
    _closed = true;
    _lines = null;
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError('AnsiStream is closed');
    }
  }

  void _read(String s) {
    _reader.read(s);
    _lines = null;
  }

  /// Acts on control [c].
  void _control(int c) {
    switch (c) {
      case 0x0A || 0x0B || 0x0C:
        _endLine();
      case 0x0D:
        _line.cursor = 0;
      case 0x08:
        _line.back();
      case 0x09:
        _line.tab(tabWidth);
    }
  }

  /// Acts on the CSI of [params] and [last]: SGR and EL.
  void _csi(String params, int last) {
    switch (last) {
      case 0x6D:
        _rendition.select(params);
      case 0x4B:
        final mode = params.isEmpty ? 0 : int.tryParse(params);
        if (mode != null) {
          _line.erase(mode);
        }
    }
  }

  /// Acts on the OSC [string]: OSC 8.
  void _osc(String string) {
    if (!string.startsWith('8;')) {
      return;
    }
    final end = string.indexOf(';', 2);
    if (end >= 0) {
      _rendition.link(string.substring(end + 1));
    }
  }

  void _endLine() {
    _settled.add(_line.spans());
    _line.clear();
  }
}

/// Hands the text a decoder makes to [read].
final class _Reader implements Sink<String> {
  _Reader(this.read);

  final void Function(String) read;

  @override
  void add(String data) => read(data);

  @override
  void close() {}
}
