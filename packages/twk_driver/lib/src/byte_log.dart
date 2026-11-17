/// [ByteLog], what an app wrote as a terminal gave it, counted as the app
/// counts it.
library;

import 'dart:typed_data';

final class _Chunk {
  _Chunk(this.bytes, this.rawStart, this.appStart, this.onlcr);

  final Uint8List bytes;
  final int rawStart;
  final int appStart;
  final bool onlcr;
}

/// The bytes received from a terminal, in the pieces it gave them, and
/// where the app's own count of what it wrote falls in them.
///
/// The terminal's line discipline writes each LF as CR LF while ONLCR is
/// set, so the bytes received are the app's plus one CR for each LF. The
/// app's count ([rawOffsetFor]'s argument) is the received count less those
/// CRs, each of which comes right before its LF: an LF that follows a CR
/// while ONLCR is set counts for nothing.
final class ByteLog {
  final _chunks = <_Chunk>[];
  var _raw = 0;
  var _app = 0;
  var _lastCr = false;

  /// How many bytes were received.
  int get rawLength => _raw;

  /// How many bytes the app has written, as far as the received ones say.
  int get appLength => _app;

  /// Appends [bytes], received while the terminal's ONLCR was [onlcr].
  void add(Uint8List bytes, {required bool onlcr}) {
    _chunks.add(_Chunk(bytes, _raw, _app, onlcr));
    for (final b in bytes) {
      if (!(onlcr && b == 0x0A && _lastCr)) {
        _app++;
      }
      _lastCr = b == 0x0D;
    }
    _raw += bytes.length;
  }

  /// How many of the bytes received hold the first [app] bytes the app
  /// wrote, and the CR the terminal added to its last LF; null while fewer
  /// than [app] were received.
  ///
  /// The count that ends on a CR that is the last byte received is taken to
  /// be the app's own: a CR added to an LF comes with it, whole, in the
  /// terminal's one piece.
  int? rawOffsetFor(int app) {
    if (app > _app) {
      return null;
    }
    if (app <= 0) {
      return 0;
    }
    // the last chunk that starts before the count
    var lo = 0;
    var hi = _chunks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_chunks[mid].appStart < app) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final chunk = _chunks[lo];
    var count = chunk.appStart;
    var cr =
        lo > 0 &&
        _chunks[lo - 1].bytes.isNotEmpty &&
        _chunks[lo - 1].bytes.last == 0x0D;
    for (var i = 0; i < chunk.bytes.length; i++) {
      final b = chunk.bytes[i];
      if (!(chunk.onlcr && b == 0x0A && cr)) {
        count++;
      }
      cr = b == 0x0D;
      if (count == app) {
        var end = i + 1;
        // the LF of a CR counted already goes with it
        if (end < chunk.bytes.length &&
            chunk.onlcr &&
            cr &&
            chunk.bytes[end] == 0x0A) {
          end++;
        }
        if (end == chunk.bytes.length &&
            cr &&
            lo + 1 < _chunks.length &&
            _chunks[lo + 1].onlcr &&
            _chunks[lo + 1].bytes.isNotEmpty &&
            _chunks[lo + 1].bytes.first == 0x0A) {
          end++;
        }
        return chunk.rawStart + end;
      }
    }
    return null;
  }

  /// The bytes received from [from] to [to].
  Uint8List slice(int from, int to) {
    final out = Uint8List(to - from);
    if (_chunks.isEmpty) {
      return out;
    }
    // the last chunk that starts at or before [from]
    var lo = 0;
    var hi = _chunks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_chunks[mid].rawStart <= from) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    for (var i = lo; i < _chunks.length; i++) {
      final chunk = _chunks[i];
      final start = chunk.rawStart;
      final end = start + chunk.bytes.length;
      if (end <= from) {
        continue;
      }
      if (start >= to) {
        break;
      }
      final a = from > start ? from : start;
      final b = to < end ? to : end;
      out.setRange(a - from, b - from, chunk.bytes, a - start);
    }
    return out;
  }
}
