/// zlib: dart:io's on the VM, inflating in Dart where there is no dart:io
/// (the web), so that a PNG decodes in a browser too.
library;

export 'zlib_io.dart' if (dart.library.js_interop) 'zlib_web.dart';
