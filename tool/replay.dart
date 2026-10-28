// Replays a captured terminal byte stream into the test emulator and prints
// the final screen plus any problems (unsupported sequences, wraps).
//
//   dart run tool/replay.dart [--fullscreen | --inline [--viewport=L,T,W,H]] \
//       capture.bin 100 30
//
// With --fullscreen what is printed once the alternate screen is left
// (`CSI ? 1049 l`) is left out until it is entered again (`CSI ? 1049 h`),
// another program's output while the app handed the terminal over, and
// after it is left the last time: ordinary terminal text (line feeds,
// wrapping) that the strict emulator would flag. Escape sequences alone
// between a leave and an enter (the capability probe's) are replayed.
// With --inline the capture is an app in the inline mode, replayed on a
// normal screen with a scrollback (printed whole, scrollback first): the
// lines printed before the app's capability probe are guarded, an absolute
// row is an error, and the cursor must end visible on a line below
// everything the app drew.
// With --inline --viewport=LEFT,TOP,WIDTH,HEIGHT the app drew in that
// rectangle of the normal screen instead, a fixed viewport
// (`TwkApp.viewport`; runApp's `viewport` in `ScreenMode.inline`), which
// it reaches by absolute rows: they are its own, but from the probe on
// every cell outside the rectangle must show what it showed then (those
// that were blank show a letter meanwhile, so that anything written or
// erased there shows; the screen is printed without them), the alternate
// screen is an error, and the cursor must end visible where it was then.
// Plain --inline stays strict about absolute rows, as an inline region
// doesn't know which row it is on; a viewport on the alternate screen is
// replayed with --fullscreen, as any app there.
// With --trace the file is an output trace (TWK_TRACE_OUTPUT, see
// packages/twk_core/lib/src/terminal/trace.dart) and COLS ROWS default to
// the size it began at; each write it holds is a frame here (the probe,
// the modes, a title are writes of their own). --step prints the screen
// after every frame under a line `=== frame N/TOTAL at T µs, B bytes ===`,
// --frame=N only the screen after frame N (counted from 1), with the
// problems found up to it.
// Exit status 1 when the emulator found errors, wraps or an unbalanced
// DEC 2026, with --inline a cursor that ended elsewhere, or with
// --viewport a cell outside it changed or the alternate screen.
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart' show Trace, TraceDirection;
import 'package:twk_test/vt.dart';

const _usage =
    'usage: dart run tool/replay.dart [--fullscreen | --inline [--viewport=L,T,W,H]] '
    'capture.bin COLS ROWS\n'
    '       dart run tool/replay.dart [--fullscreen | --inline [--viewport=L,T,W,H]] '
    '--trace [--step | --frame=N] out.trace [COLS ROWS]';

void main(List<String> args) {
  final flags = args.where((a) => a.startsWith('--')).toSet();
  final rest = args.where((a) => !a.startsWith('--')).toList();
  final frameFlag = flags.where((a) => a.startsWith('--frame=')).firstOrNull;
  final frame = frameFlag == null ? null : int.tryParse(frameFlag.substring(8));
  final viewFlag = flags.where((a) => a.startsWith('--viewport=')).firstOrNull;
  final view = viewFlag == null ? null : _rect(viewFlag.substring(11));
  final unknown = flags.difference({
    '--fullscreen',
    '--inline',
    '--trace',
    '--step',
    ?frameFlag,
    ?viewFlag,
  });
  final traced = flags.contains('--trace');
  final step = flags.contains('--step');
  final sized = rest.length == 3 || (traced && rest.length == 1);
  var w = rest.length == 3 ? int.tryParse(rest[1]) : null;
  var h = rest.length == 3 ? int.tryParse(rest[2]) : null;
  if (unknown.isNotEmpty ||
      !sized ||
      (rest.length == 3 && (w == null || h == null || w < 1 || h < 1)) ||
      (frameFlag != null && (frame == null || frame < 1)) ||
      ((step || frameFlag != null) && !traced) ||
      (step && frameFlag != null) ||
      (viewFlag != null && (view == null || !flags.contains('--inline')))) {
    if (unknown.isNotEmpty) {
      stderr.writeln('unknown option ${unknown.first}');
    }
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final fullscreenOnly = flags.contains('--fullscreen');
  final inline = flags.contains('--inline');
  var bytes = File(rest[0]).readAsBytesSync();
  // where each frame ends in bytes; for a trace when it was written, and
  // its length
  var ends = [bytes.length];
  var times = [0];
  var sizes = [bytes.length];
  if (traced) {
    final Trace trace;
    try {
      trace = Trace.parse(bytes);
    } on FormatException catch (e) {
      stderr.writeln('${rest[0]}: ${e.message}');
      exitCode = 65;
      return;
    }
    if (trace.direction != TraceDirection.output) {
      stderr.writeln('${rest[0]}: an input trace; replay an output one');
      exitCode = 65;
      return;
    }
    if (trace.truncated) {
      stderr.writeln('${rest[0]}: cut off; replaying the frames before it');
    }
    w ??= trace.width;
    h ??= trace.height;
    bytes = trace.bytes;
    var end = 0;
    ends = [for (final r in trace.records) end += r.bytes.length];
    times = [for (final r in trace.records) r.micros];
    sizes = [for (final r in trace.records) r.bytes.length];
  }
  if (frame != null && frame > ends.length) {
    stderr.writeln('frame $frame of ${ends.length}');
    exitCode = 64;
    return;
  }
  if (fullscreenOnly) {
    (bytes, ends) = _onAlternateScreen(bytes, ends);
  }
  final vt = Vt(
    w!,
    h!,
    strict: false,
    scrollback: inline,
    allowLineFeed: inline,
    // a viewport is where it is on the screen
    relativeOnly: inline && view == null,
  );
  // the inline region starts below what was printed before the probe, the
  // viewport is drawn over the screen it showed
  final start = inline ? _indexOf(bytes, '\x1b[?2026\$p') : -1;
  final probe = start < 0 ? 0 : start;
  var guarded = !inline;
  _Outside? outside;
  var fed = 0;
  void feedTo(int end) {
    if (!guarded && probe <= end) {
      vt.feed(Uint8List.sublistView(bytes, fed, probe));
      if (view == null) {
        vt.guardRows(vt.cx == 0 ? vt.cy : vt.cy + 1);
      } else {
        outside = _Outside(vt, view);
      }
      guarded = true;
      fed = probe;
    }
    vt.feed(Uint8List.sublistView(bytes, fed, end));
    fed = end;
  }

  String text() => inline ? vt.lines.join('\n') : vt.dump();
  String screen() => outside?.unmarked(text) ?? text();
  final last = frame ?? ends.length;
  for (var i = 0; i < last; i++) {
    feedTo(ends[i]);
    outside?.check();
    if (step) {
      stdout
        ..writeln(
          '=== frame ${i + 1}/${ends.length} at ${times[i]} µs, '
          '${sizes[i]} bytes ===',
        )
        ..writeln(screen());
    }
  }
  var below = true;
  var back = true;
  final out = outside;
  if (inline && last == ends.length) {
    if (view == null) {
      below =
          vt.cx == 0 &&
          vt.cursorVisible &&
          vt.lines.skip(vt.history.length + vt.cy).every((l) => l.isEmpty);
    } else {
      back = vt.cursorVisible && (vt.cx, vt.cy) == out?.cursor;
    }
  }
  if (!step) {
    stdout.writeln(screen());
  }
  final changed = out?.changed ?? const <String>[];
  final checks = view != null
      ? ' outsideChanged=${changed.length} cursorPutBack=$back'
      : inline
      ? ' cursorBelowRegion=$below'
      : '';
  stdout.writeln(
    '--- bytes=$fed errors=${vt.errors.length} '
    'printWraps=${vt.printWraps} syncDepth=${vt.syncDepth} '
    'altScreenSwitches=${vt.altScreenSwitches} '
    'cursorVisible=${vt.cursorVisible} autowrap=${vt.autowrap}$checks',
  );
  // in a viewport of the normal screen the alternate screen is an error
  final problems = [
    ...vt.errors.take(10),
    ...changed.take(10),
    if (view != null && vt.altScreenSwitches > 0)
      'the alternate screen in a viewport of the normal screen',
  ];
  for (final e in problems) {
    stdout.writeln('  $e');
  }
  if (problems.isNotEmpty ||
      vt.printWraps > 0 ||
      vt.syncDepth != 0 ||
      !below ||
      !back) {
    exitCode = 1;
  }
}

/// `LEFT,TOP,WIDTH,HEIGHT`, each a number from 0 on; null for anything
/// else.
(int, int, int, int)? _rect(String s) {
  final n = [for (final p in s.split(',')) int.tryParse(p)];
  if (n case [final l?, final t?, final w?, final h?]
      when l >= 0 && t >= 0 && w >= 0 && h >= 0) {
    return (l, t, w, h);
  }
  return null;
}

/// The cells of [vt]'s screen outside a fixed viewport, as the app found
/// them: each blank one shows a letter from now on, so that anything the
/// app writes or erases there shows; [check] keeps what changed.
final class _Outside {
  _Outside(this.vt, (int, int, int, int) view) : cursor = (vt.cx, vt.cy) {
    final (left, top, width, height) = view;
    for (var y = 0; y < vt.height; y++) {
      for (var x = 0; x < vt.width; x++) {
        if (x >= left && x < left + width && y >= top && y < top + height) {
          continue;
        }
        final c = vt.cell(x, y);
        final blank = '$c' == ' ' && c.image == null && c.kitty == null;
        if (blank) {
          c.text = String.fromCharCode(0x61 + (x + y) % 26);
        }
        _cells.add((x, y, '$c', blank));
      }
    }
  }

  final Vt vt;

  /// Where the cursor was, which the app puts back.
  final (int, int) cursor;

  /// Column, row, what it shows (a letter where it was blank) and whether
  /// it was.
  final _cells = <(int, int, String, bool)>[];

  /// The cells changed, the first change of each.
  final changed = <String>[];
  final _seen = <(int, int)>{};

  /// Adds the cells changed since the last call to [changed].
  void check() {
    for (final (x, y, was, blank) in _cells) {
      final now = '${vt.cell(x, y)}';
      if (now != was && _seen.add((x, y))) {
        changed.add(
          'cell ($x, $y) outside the viewport written or erased: now '
          '"$now", before ${blank ? 'blank' : '"$was"'}',
        );
      }
    }
  }

  /// What [read] reads of [vt] while the cells that were blank and show
  /// their letter still are blank again.
  String unmarked(String Function() read) {
    final marked = [
      for (final (x, y, was, blank) in _cells)
        if (blank && '${vt.cell(x, y)}' == was) (vt.cell(x, y), was),
    ];
    for (final (c, _) in marked) {
      c.text = ' ';
    }
    final s = read();
    for (final (c, letter) in marked) {
      c.text = letter;
    }
    return s;
  }
}

/// [b] without what is printed after an `ESC [ ? 1049 l` until the next
/// `ESC [ ? 1049 h`, or until the end after the last one; and [ends],
/// where frames end in [b], as where they end in what is kept.
(Uint8List, List<int>) _onAlternateScreen(Uint8List b, List<int> ends) {
  const leave = '\x1b[?1049l';
  const enter = '\x1b[?1049h';
  // the ranges kept, [from, to) in a row
  final kept = <int>[];
  var from = 0;
  while (true) {
    final left = _indexOf(b, leave, from);
    if (left < 0) {
      kept.addAll([from, b.length]);
      break;
    }
    final gap = left + leave.length;
    kept.addAll([from, gap]);
    final entered = _indexOf(b, enter, gap);
    if (entered < 0) {
      break;
    }
    from = _prints(Uint8List.sublistView(b, gap, entered)) ? entered : gap;
  }
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < kept.length; i += 2) {
    out.add(Uint8List.sublistView(b, kept[i], kept[i + 1]));
  }

  /// How many of the bytes before [end] are kept.
  int keptBefore(int end) {
    var n = 0;
    for (var i = 0; i < kept.length && kept[i] < end; i += 2) {
      n += (kept[i + 1] < end ? kept[i + 1] : end) - kept[i];
    }
    return n;
  }

  return (out.takeBytes(), [for (final e in ends) keptBefore(e)]);
}

/// Whether [b] holds more than escape sequences: text or a control.
bool _prints(Uint8List b) {
  var i = 0;
  while (i < b.length) {
    if (b[i] != 0x1B || i + 1 == b.length) {
      return true;
    }
    final kind = b[i + 1];
    i += 2;
    if (kind == 0x5B) {
      // CSI: up to its final byte
      while (i < b.length && (b[i] < 0x40 || b[i] > 0x7E)) {
        i++;
      }
      i++;
    } else if (kind == 0x5D) {
      // OSC: up to BEL or ST
      while (i < b.length && b[i] != 0x07 && b[i] != 0x1B) {
        i++;
      }
      i += i < b.length && b[i] == 0x1B ? 2 : 1;
    }
  }
  return false;
}

/// Where [s] (ASCII) first occurs in [b] from [start] on, or -1.
int _indexOf(Uint8List b, String s, [int start = 0]) {
  outer:
  for (var i = start; i + s.length <= b.length; i++) {
    for (var k = 0; k < s.length; k++) {
      if (b[i + k] != s.codeUnitAt(k)) {
        continue outer;
      }
    }
    return i;
  }
  return -1;
}
