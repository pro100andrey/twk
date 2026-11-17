@Tags(['process'])
library;

import 'package:test/test.dart';

import 'create_cycle.dart';

// The page is built too, with dart2wasm as twk_web documents: it needs no
// browser, so the gates compile it, though none runs it.
void main() => templateCycle(
  'web',
  entry: 'web/main.dart',
  extraFiles: ['web/index.html'],
  compile: ['compile', 'wasm', 'web/main.dart', '-o', 'web/main.wasm'],
);
