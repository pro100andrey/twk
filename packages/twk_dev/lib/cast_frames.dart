/// Recordings played through the test emulator (package:twk_test's `Vt`),
/// a screen a frame, to assert on: a session `twk record` recorded is
/// also a regression test.
///
/// ```dart
/// final frames = castFrames(Cast.read('test/tally.cast'));
/// expect(frames.last.lines[1], startsWith('│ › coffee     1 ■'));
/// expect(frames.last.errors, isEmpty);
/// ```
library;

import 'dart:convert';

import 'package:twk_test/vt.dart';

import 'src/cast.dart';

export 'src/cast.dart' show Cast, CastEvent, CastHeader;

// Examples can assume:
// import 'package:test/test.dart';

/// A screen a recording showed: the emulator's once an output event was
/// fed to it, unless it left a synchronized update (DEC mode 2026) open,
/// whose screen a terminal doesn't show.
final class CastFrame {
  CastFrame._(
    this.number,
    this.time,
    this.width,
    this.height,
    this.lines,
    this.cursorX,
    this.cursorY,
    this.cursorVisible,
    this.errors,
  );

  /// From 1, in the order shown.
  final int number;

  /// When it was shown, in seconds from the start, as the recording has
  /// it.
  final double time;

  /// The screen's width, in cells.
  final int width;

  /// The screen's height, in cells.
  final int height;

  /// The rows, top first, without the blanks that end them.
  final List<String> lines;

  /// The cursor's column, from 0.
  final int cursorX;

  /// The cursor's row, from 0.
  final int cursorY;

  /// Whether the cursor shows.
  final bool cursorVisible;

  /// What the emulator could not take in the output up to this frame: an
  /// unknown sequence, a raw control byte.
  final List<String> errors;

  /// `frame 3 at 1.250 s, 40×10:`, then the rows, numbered.
  @override
  String toString() => [
    'frame $number at ${time.toStringAsFixed(3)} s, $width×$height:',
    for (final (y, line) in lines.indexed) '${'$y'.padLeft(3)} │$line',
  ].join('\n');
}

/// The frames of [cast]: its output fed to the test emulator of the
/// recording's size, a resize event resizing it as a terminal that keeps
/// what it shows does ([Vt.resizeKeeping]), and the screen taken after
/// each output event that leaves no synchronized update open. Line feeds
/// are taken (a shell's output has them); what the emulator doesn't know
/// is no error, but each frame's [CastFrame.errors].
List<CastFrame> castFrames(Cast cast) {
  final vt = Vt(
    cast.header.width,
    cast.header.height,
    strict: false,
    allowLineFeed: true,
  );
  final frames = <CastFrame>[];
  var errors = const <String>[];
  for (final event in cast.events) {
    if (event.size case (final w, final h)?) {
      vt.resizeKeeping(w, h);
      continue;
    }
    if (event.code != CastEvent.output) {
      continue;
    }
    vt.feed(utf8.encode(event.data));
    if (vt.syncDepth > 0) {
      continue;
    }
    if (vt.errors.length != errors.length) {
      errors = List.unmodifiable(vt.errors);
    }
    frames.add(
      CastFrame._(
        frames.length + 1,
        event.time,
        vt.width,
        vt.height,
        List.unmodifiable(vt.lines),
        vt.cx,
        vt.cy,
        vt.cursorVisible,
        errors,
      ),
    );
  }
  return frames;
}
