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
/// ```dart
/// final gif = decodeGif(File('spinner.gif').readAsBytesSync());
/// final at2s = gif.frameAt(const Duration(seconds: 2));
/// print('${gif.frames.length} frames, ${gif.duration} a play: $at2s');
/// ```
final class AnimatedImage {
  /// An image of [frames], at least one, played [loops] times (0, the
  /// default, for ever); [width] and [height] are the canvas's.
  AnimatedImage(this.frames, {this.loops = 0})
    : assert(frames.isNotEmpty, 'an image has a frame at least'),
      width = frames.first.bitmap.width,
      height = frames.first.bitmap.height,
      duration = frames.fold(Duration.zero, (sum, f) => sum + f.delay);

  /// The frames in the order they show.
  final List<ImageFrame> frames;

  /// How many times the frames play; 0 for ever.
  final int loops;

  /// The canvas's width in pixels.
  final int width;

  /// The canvas's height in pixels.
  final int height;

  /// How long one play of the frames takes.
  final Duration duration;

  /// Whether it has more than one frame.
  bool get isAnimated => frames.length > 1;

  /// The index of the frame showing [elapsed] after the start: the first
  /// before it, the last once the plays ([loops]) are over.
  int indexAt(Duration elapsed) {
    if (frames.length == 1 || duration == Duration.zero) {
      return 0;
    }
    if (elapsed.isNegative) {
      return 0;
    }
    final total = duration.inMicroseconds;
    if (loops > 0 && elapsed.inMicroseconds >= total * loops) {
      return frames.length - 1;
    }
    var t = elapsed.inMicroseconds % total;
    for (var i = 0; i < frames.length; i++) {
      t -= frames[i].delay.inMicroseconds;
      if (t < 0) {
        return i;
      }
    }
    return frames.length - 1;
  }

  /// The frame showing [elapsed] after the start.
  ImageFrame frameAt(Duration elapsed) => frames[indexAt(elapsed)];

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
    for (final f in frames) {
      t += f.delay.inMicroseconds;
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
      'AnimatedImage($width × $height, ${frames.length} frames, loops: $loops)';
}

/// The delay a file asks for in microseconds as a browser shows it: one of
/// 10 ms or less, which writers use for "as fast as possible", takes 100 ms.
Duration frameDelay(int microseconds) =>
    Duration(microseconds: microseconds <= 10000 ? 100000 : microseconds);
