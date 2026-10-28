/// The frames of a test's app, recorded: each with its time on the
/// test's clock, the screen it left ([RecordedFrame]), and all of them as
/// an output trace for `tool/replay.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show Trace, TraceDirection;

import '../vt.dart';
import 'screen_text.dart';
import 'tester.dart';

// Examples can assume:
// import 'package:test/test.dart';
// late TwkTester t;

/// A frame the app wrote ([TwkTester.frames]): its bytes, when, and the
/// screen it left.
///
/// Its [toString] is its number, time and size and the screen, as a test
/// that fails prints the last frames.
///
/// ```dart
/// final first = t.frames.first;
/// expect(first.time, Duration.zero);
/// expect(first.lines.first, 'Loading…');
/// ```
final class RecordedFrame {
  RecordedFrame._(this.number, this.time, this.bytes, this.lines, this._screen);

  /// From 1, in the order the app wrote them: as `tool/replay.dart` counts
  /// the writes of a trace.
  final int number;

  /// When it was written, on the test's clock.
  final Duration time;

  /// As written.
  final Uint8List bytes;

  /// The rows of the screen once it was written, as [TwkTester.lines]
  /// gives them.
  final List<String> lines;

  // the screen as a failure message shows it
  final String _screen;

  /// `frame 3 at 0.050 s, 120 bytes`, and on the lines after it the
  /// screen as a failing matcher shows it: rows numbered, styles marked.
  @override
  String toString() =>
      'frame $number at ${(time.inMicroseconds / 1e6).toStringAsFixed(3)} s, '
      '${bytes.length} bytes:\n$_screen';
}

/// What a tester keeps of its app's frames besides their bytes: when each
/// was written and when the terminal was resized; and how the emulator
/// started, to replay them.
@internal
final class FrameRecorder {
  FrameRecorder(
    this.width,
    this.height, {
    required this.inline,
    required this.history,
  });

  /// The terminal's size when the app started.
  final int width;
  final int height;

  /// The app runs in the inline mode, below [history].
  final bool inline;
  final List<String> history;

  /// When each frame was written.
  final _times = <Duration>[];

  /// The resizes: how many frames came before each, and the size.
  final _resizes = <(int, int, int)>[];

  /// The frames after the first [count] were written [now].
  void stamp(int count, Duration now) {
    while (_times.length < count) {
      _times.add(now);
    }
  }

  /// The terminal became [width] × [height] after the first [count]
  /// frames.
  void resized(int count, int width, int height) =>
      _resizes.add((count, width, height));

  /// [frames] as [RecordedFrame]s, each with the screen replayed up to it.
  List<RecordedFrame> replay(List<Uint8List> frames) {
    final out = <RecordedFrame>[];
    _replay(frames, _emulator(), (i, vt) => out.add(_frame(frames, i, vt)));
    return out;
  }

  /// The last [count] of [frames] that changed the screen, as a failing
  /// test prints them; null when none did.
  String? last(List<Uint8List> frames, int count) {
    final changed = <RecordedFrame>[];
    final vt = _emulator();
    var before = describeScreen(vt);
    _replay(frames, vt, (i, vt) {
      final screen = describeScreen(vt);
      if (screen != before) {
        changed.add(_frame(frames, i, vt, screen));
        if (changed.length > count) {
          changed.removeAt(0);
        }
      }
      before = screen;
    });
    if (changed.isEmpty) {
      return null;
    }
    final wrote = frames.length == 1 ? '1 frame' : '${frames.length} frames';
    return 'the app wrote $wrote; the last ${changed.length} that changed '
        'the screen:\n\n${changed.join('\n\n')}';
  }

  /// [frames] as an output trace (see `Trace` in twk_core).
  Uint8List trace(List<Uint8List> frames) {
    final out = BytesBuilder(copy: false)
      ..add(
        ascii.encode(
          '${Trace.magic} ${Trace.version} ${TraceDirection.output.name} '
          '${width}x$height\n',
        ),
      );
    for (final (i, bytes) in frames.indexed) {
      out
        ..add(ascii.encode('${_times[i].inMicroseconds} ${bytes.length}\n'))
        ..add(bytes)
        ..addByte(0x0A);
    }
    return out.takeBytes();
  }

  /// An emulator as the tester's started, which records what it does not
  /// take instead of throwing.
  Vt _emulator() {
    final vt = inline
        ? Vt(
            width,
            height,
            strict: false,
            scrollback: true,
            allowLineFeed: true,
            relativeOnly: true,
          )
        : Vt(width, height, strict: false);
    for (final line in history) {
      vt
        ..feed(utf8.encode(line))
        ..feed(const [0x0D, 0x0A]);
    }
    return vt..guardRows(vt.cy);
  }

  /// Feeds [frames] to [vt] in turn, resized where the terminal was, and
  /// calls [each] after each.
  void _replay(
    List<Uint8List> frames,
    Vt vt,
    void Function(int i, Vt vt) each,
  ) {
    var r = 0;
    for (final (i, bytes) in frames.indexed) {
      for (; r < _resizes.length && _resizes[r].$1 <= i; r++) {
        final (_, width, height) = _resizes[r];
        if (inline) {
          vt.resizeKeeping(width, height);
        } else {
          vt.resize(width, height);
        }
      }
      vt.feed(bytes);
      each(i, vt);
    }
  }

  /// Frame [i] of [frames], [vt] fed up to it.
  RecordedFrame _frame(
    List<Uint8List> frames,
    int i,
    Vt vt, [
    String? screen,
  ]) => RecordedFrame._(
    i + 1,
    _times[i],
    frames[i],
    vt.lines.sublist(vt.history.length),
    screen ?? describeScreen(vt),
  );
}
