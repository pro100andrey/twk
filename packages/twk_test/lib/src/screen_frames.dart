/// What a terminal showed of a program's output, a screen a write, as the
/// test emulator ([Vt]) shows it: [screenFrames].
library;

import 'dart:convert';

import '../vt.dart';

// Examples can assume:
// import 'package:test/test.dart';
// late List<TerminalWrite> writes;

/// What a program did to its terminal at `time` (seconds from the start):
/// wrote `output`, or, with `size`, had it resized to that many columns and
/// rows. twk_dev's `Cast.writes` gives a recording's.
typedef TerminalWrite = ({double time, String? output, (int, int)? size});

/// A screen a terminal showed: the emulator's once a write was fed to it,
/// unless it left a synchronized update (DEC mode 2026) open, whose screen
/// a terminal doesn't show.
final class ScreenFrame {
  ScreenFrame._(
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

  /// When it was shown, in seconds from the start, as its write says.
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

/// The frames of [writes] to a terminal [width] × [height] cells: each
/// output fed to the test emulator, a resize resizing it as a terminal that
/// keeps what it shows does ([Vt.resizeKeeping]), and the screen taken
/// after each output that leaves no synchronized update open. Line feeds
/// are taken (a shell's output has them); what the emulator doesn't know
/// is no error, but each frame's [ScreenFrame.errors].
///
/// ```dart
/// final frames = screenFrames(40, 10, writes);
/// expect(frames.last.lines[1], startsWith('│ › coffee     1 ■'));
/// expect(frames.last.errors, isEmpty);
/// ```
List<ScreenFrame> screenFrames(
  int width,
  int height,
  Iterable<TerminalWrite> writes,
) {
  final vt = Vt(width, height, strict: false, allowLineFeed: true);
  final frames = <ScreenFrame>[];
  var errors = const <String>[];
  for (final write in writes) {
    if (write.size case (final w, final h)?) {
      vt.resizeKeeping(w, h);
      continue;
    }
    final output = write.output;
    if (output == null) {
      continue;
    }
    vt.feed(utf8.encode(output));
    if (vt.syncDepth > 0) {
      continue;
    }
    if (vt.errors.length != errors.length) {
      errors = List.unmodifiable(vt.errors);
    }
    frames.add(
      ScreenFrame._(
        frames.length + 1,
        write.time,
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
