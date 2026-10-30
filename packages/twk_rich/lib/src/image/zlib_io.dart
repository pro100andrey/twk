/// zlib on the VM: dart:io's, native; the web's is `zlib_web.dart`.
library;

import 'dart:io' show ZLibDecoder, ZLibEncoder;
import 'dart:typed_data';

/// The data the zlib stream [data] holds; a [FormatException] once it
/// holds more than [limit] bytes, given one, which is as far as it is
/// inflated.
Uint8List zlibInflate(List<int> data, {int? limit}) {
  if (limit == null) {
    final out = ZLibDecoder().convert(data);
    return out is Uint8List ? out : Uint8List.fromList(out);
  }
  final out = _Bounded(limit);
  final sink = ZLibDecoder().startChunkedConversion(out);
  // a KiB in inflates to a MiB out at most: the bound is checked as it
  // grows, not once it has
  for (var at = 0; at < data.length; at += 1024) {
    final end = at + 1024 < data.length ? at + 1024 : data.length;
    sink.addSlice(data, at, end, false);
  }
  sink.close();
  return out.bytes.takeBytes();
}

/// What is inflated, refused past [limit] bytes.
final class _Bounded implements Sink<List<int>> {
  _Bounded(this.limit);

  final int limit;
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > limit) {
      throw FormatException('zlib data of more than $limit bytes');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}

/// [data] deflated at [level] (0 to 9) into a zlib stream.
Uint8List zlibDeflate(List<int> data, {int level = 6}) {
  final out = ZLibEncoder(level: level).convert(data);
  return out is Uint8List ? out : Uint8List.fromList(out);
}
