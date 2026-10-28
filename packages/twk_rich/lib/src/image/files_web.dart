/// Reading an image file where there are no files (the web): an
/// [UnsupportedError]; there `Image.memory` takes the bytes, fetched as
/// the page fetches them.
library;

import 'dart:typed_data';

/// Throws an [UnsupportedError]: a browser reads no files.
Uint8List readImageFile(String path) =>
    throw UnsupportedError('no files to read $path from on the web');
