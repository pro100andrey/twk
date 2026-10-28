/// Reading an image file on the VM; the web's is `files_web.dart`.
library;

import 'dart:io' show File;
import 'dart:typed_data';

/// The bytes of the file at [path].
Uint8List readImageFile(String path) => File(path).readAsBytesSync();
