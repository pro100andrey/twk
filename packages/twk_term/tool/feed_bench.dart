/// Times the emulator taking a program's output, as a terminal reads it
/// from a pseudo-terminal: in pieces of 64 KiB.
///
/// ```bash
/// python3 ../../tool/pty_run.py --input none --size 120x40 \
///     --out /tmp/cat.bin -- cat big.txt
/// taskset -c 21 dart run tool/feed_bench.dart /tmp/cat.bin
/// ```
///
/// Without a file, 10 MiB of lines like those of source code (some of
/// them with CJK, accents and box drawing) ending in CR LF. `--runs=N`
/// (5), `--size=COLSxROWS` (120x40), `--scrollback=N` (10000).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_term/twk_term.dart';

void main(List<String> args) {
  var runs = 5;
  var cols = 120;
  var rows = 40;
  var scrollback = 10000;
  String? path;
  for (final a in args) {
    if (a.startsWith('--runs=')) {
      runs = int.parse(a.substring(7));
    } else if (a.startsWith('--size=')) {
      final [c, r] = a.substring(7).split('x');
      cols = int.parse(c);
      rows = int.parse(r);
    } else if (a.startsWith('--scrollback=')) {
      scrollback = int.parse(a.substring(13));
    } else {
      path = a;
    }
  }
  final data = path == null
      ? _synthetic(10 << 20)
      : File(path).readAsBytesSync();
  const chunk = 64 << 10;
  // pieces of their own, as reads from a pseudo-terminal come
  final pieces = [
    for (var i = 0; i < data.length; i += chunk)
      Uint8List.fromList(
        data.sublist(i, i + chunk < data.length ? i + chunk : data.length),
      ),
  ];
  final times = <int>[];
  late TerminalEmulator t;
  for (var run = 0; run <= runs; run++) {
    t = TerminalEmulator(
      width: cols,
      height: rows,
      scrollbackLimit: scrollback,
    );
    final sw = Stopwatch()..start();
    for (final piece in pieces) {
      t.feed(piece);
    }
    sw.stop();
    if (run > 0) {
      times.add(sw.elapsedMicroseconds); // the first run warms up
    }
  }
  times.sort();
  final mb = data.length / (1 << 20);
  String rate(int us) => '${(mb / (us / 1e6)).toStringAsFixed(1)} MiB/s';
  String ms(int us) => '${(us / 1000).toStringAsFixed(1)} ms';
  final median = times[times.length ~/ 2];
  stdout
    ..writeln(
      '${path ?? 'synthetic'}: ${mb.toStringAsFixed(1)} MiB, '
      '${cols}x$rows, scrollback $scrollback, $runs runs',
    )
    ..writeln(
      'best ${ms(times.first)} (${rate(times.first)}), '
      'median ${ms(median)} (${rate(median)})',
    )
    ..writeln('last row: ${t.lineText(t.cursorY > 0 ? t.cursorY - 1 : 0)}');
}

Uint8List _synthetic(int size) {
  const lines = [
    '  final cells = Uint32List(width * height); // the packed cell buffer',
    '/// Draws [s] at (x, y) with [pen]; returns the columns it advanced.',
    '  for (var i = 0; i < n; i++) {',
    '    sb.write(glyphs.stringOf(c));',
    '}',
    '',
    '| 文字 | ширина | ünïcödé | ┌──┬──┐ │ └──┴──┘ |',
    "export 'src/emulator/emulator.dart' show TerminalEmulator;",
  ];
  final out = BytesBuilder(copy: false);
  var n = 0;
  for (var i = 0; n < size; i++) {
    final b = utf8.encode('${lines[i % lines.length]}\r\n');
    out.add(b);
    n += b.length;
  }
  return Uint8List.sublistView(out.takeBytes(), 0, size);
}
