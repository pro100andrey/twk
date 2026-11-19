/// @docImport 'gif.dart';
/// @docImport 'image_file.dart';
/// @docImport 'png.dart';
library;

import 'bitmap.dart';

// Examples can assume:
// import 'dart:io';

/// One picture of an [AnimatedImage]: the whole canvas as it looks while
/// this frame shows, with the frames before it composed in, and how long
/// it shows.
final class ImageFrame {
  /// A frame of [bitmap] shown for [delay].
  const ImageFrame(this.bitmap, this.delay);

  /// The canvas at this frame, as large as the image.
  final Bitmap bitmap;

  /// How long it shows before the next.
  final Duration delay;

  @override
  String toString() => 'ImageFrame(${bitmap.width} × ${bitmap.height}, $delay)';
}

/// The frames of an animated GIF or APNG, each composed on the canvas as
/// the file's disposal and blend rules say, with the time each shows
/// ([decodeGif], [decodeApng], [decodeAnimation]). A still image is one
/// frame.
///
/// The delays are known at once, the pictures are not: a frame is composed
/// when [bitmapAt] reaches it, the file's frames being composed in order,
/// each on the one before, and only a window of the last composed is kept
/// ([windowBytes]), so that a long animation takes the memory of a few
/// frames, not of all. A frame past those kept is composed again from the
/// first, which is cheap for the playing order (each frame is the next of
/// the one before) and costly for a jump back.
///
/// ```dart
/// final gif = decodeGif(File('spinner.gif').readAsBytesSync());
/// final at2s = gif.frameAt(const Duration(seconds: 2));
/// print('${gif.frameCount} frames, ${gif.duration} a play: $at2s');
/// ```
final class AnimatedImage {
  /// An image of [frames], at least one, all in memory, played [loops]
  /// times (0, the default, for ever); [width] and [height] are the first
  /// frame's.
  AnimatedImage(List<ImageFrame> frames, {this.loops = 0})
    : assert(frames.isNotEmpty, 'an image has a frame at least'),
      width = frames.first.bitmap.width,
      height = frames.first.bitmap.height,
      delays = List.unmodifiable([for (final f in frames) f.delay]),
      duration = frames.fold(Duration.zero, (sum, f) => sum + f.delay),
      windowBytes = 0,
      _all = [for (final f in frames) f.bitmap],
      _compose = null,
      _rewind = null;

  /// An image of [width] × [height] pixels with a frame for each of
  /// [delays], composed as they are reached: `compose` gives the next frame's
  /// bitmap, a new one each time, the frames in order from the first, and
  /// `rewind` starts again at the first. [windowBytes] is what the
  /// composed frames kept may take at most, one frame at least.
  AnimatedImage.composed({
    required this.width,
    required this.height,
    required List<Duration> delays,
    required Bitmap Function() this._compose,
    required void Function() this._rewind,
    this.loops = 0,
    this.windowBytes = defaultWindowBytes,
  }) : assert(delays.isNotEmpty, 'an image has a frame at least'),
       delays = List.unmodifiable(delays),
       duration = delays.fold(Duration.zero, (sum, d) => sum + d),
       _all = null;

  /// What the composed frames kept take at most, by default: 32 MB.
  static const int defaultWindowBytes = 32 << 20;

  /// How many times the frames play; 0 for ever.
  final int loops;

  /// The canvas's width in pixels.
  final int width;

  /// The canvas's height in pixels.
  final int height;

  /// How long each frame shows, by its index.
  final List<Duration> delays;

  /// How long one play of the frames takes.
  final Duration duration;

  /// The most bytes of composed frames kept (0 where all are in memory).
  final int windowBytes;

  final List<Bitmap>? _all;
  final Bitmap Function()? _compose;
  final void Function()? _rewind;

  // the composed frames kept, the least recently used first
  final _kept = <int, Bitmap>{};
  // the index of the frame [_compose] gives next
  var _next = 0;

  /// How many frames it has.
  int get frameCount => delays.length;

  /// Whether it has more than one frame.
  bool get isAnimated => delays.length > 1;

  /// How many frames are composed and kept now.
  int get keptFrames => _all?.length ?? _kept.length;

  /// The canvas at frame [index], composed now where it is not kept: the
  /// frames from the one the composing stands at, or from the first where
  /// it is before. The bitmap is not changed by anything after.
  ///
  /// Throws a [FormatException] where the file's data for a frame, or one
  /// it is composed on, does not decode.
  Bitmap bitmapAt(int index) {
    RangeError.checkValidIndex(index, delays);
    if (_all case final all?) {
      return all[index];
    }
    if (_kept.remove(index) case final hit?) {
      return _kept[index] = hit;
    }
    if (index < _next) {
      _rewind!();
      _next = 0;
    }
    final capacity = windowBytes ~/ (width * height * 4);
    Bitmap? bitmap;
    while (_next <= index) {
      final at = _next;
      // a frame that fails to decode is tried again, from the first
      try {
        bitmap = _compose!();
      } on FormatException {
        _rewind!();
        _next = 0;
        rethrow;
      }
      _next = at + 1;
      _kept[at] = bitmap;
      while (_kept.length > 1 && _kept.length > capacity) {
        _kept.remove(_kept.keys.first);
      }
    }
    return bitmap!;
  }

  /// The index of the frame showing [elapsed] after the start: the first
  /// before it, the last once the plays ([loops]) are over.
  int indexAt(Duration elapsed) {
    if (delays.length == 1 || duration == Duration.zero) {
      return 0;
    }
    if (elapsed.isNegative) {
      return 0;
    }
    final total = duration.inMicroseconds;
    if (loops > 0 && elapsed.inMicroseconds >= total * loops) {
      return delays.length - 1;
    }
    var t = elapsed.inMicroseconds % total;
    for (var i = 0; i < delays.length; i++) {
      t -= delays[i].inMicroseconds;
      if (t < 0) {
        return i;
      }
    }
    return delays.length - 1;
  }

  /// The frame showing [elapsed] after the start.
  ImageFrame frameAt(Duration elapsed) {
    final i = indexAt(elapsed);
    return ImageFrame(bitmapAt(i), delays[i]);
  }

  /// When, counted from the start, the frame after the one showing at
  /// [elapsed] starts; null where none does, the plays being over or the
  /// image one frame.
  Duration? nextChangeAfter(Duration elapsed) {
    if (!isAnimated || duration == Duration.zero) {
      return null;
    }
    final total = duration.inMicroseconds;
    final at = elapsed.isNegative ? 0 : elapsed.inMicroseconds;
    if (loops > 0 && at >= total * loops) {
      return null;
    }
    final playStart = at - at % total;
    var t = playStart;
    for (final d in delays) {
      t += d.inMicroseconds;
      if (t > at) {
        // the last frame of the last play has no next
        return loops > 0 && t >= total * loops
            ? null
            : Duration(microseconds: t);
      }
    }
    return Duration(microseconds: t);
  }

  @override
  String toString() =>
      'AnimatedImage($width × $height, $frameCount frames, loops: $loops)';
}

/// The delay a file asks for in microseconds as a browser shows it: one of
/// 10 ms or less, which writers use for "as fast as possible", takes 100 ms.
Duration frameDelay(int microseconds) =>
    Duration(microseconds: microseconds <= 10000 ? 100000 : microseconds);
