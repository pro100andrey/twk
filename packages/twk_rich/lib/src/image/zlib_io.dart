/// zlib on the VM: dart:io's, native; the web's is `zlib_web.dart`.
library;

import 'dart:io' show ZLibDecoder, ZLibEncoder;
import 'dart:typed_data';

/// The data the zlib stream [data] holds.
Uint8List zlibInflate(List<int> data) {
  final out = ZLibDecoder().convert(data);
  return out is Uint8List ? out : Uint8List.fromList(out);
}

/// [data] deflated at [level] (0 to 9) into a zlib stream.
Uint8List zlibDeflate(List<int> data, {int level = 6}) {
  final out = ZLibEncoder(level: level).convert(data);
  return out is Uint8List ? out : Uint8List.fromList(out);
}
