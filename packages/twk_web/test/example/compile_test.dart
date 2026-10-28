// The example builds with dart2wasm into what web/index.html loads.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show runProcess;

void main() {
  test('web/main.dart compiles to what web/index.html loads', () async {
    final out = await Directory.systemTemp.createTemp('twk_web');
    addTearDown(() => out.delete(recursive: true));
    final compiled = await runProcess(Platform.resolvedExecutable, [
      'compile',
      'wasm',
      'web/main.dart',
      '-o',
      '${out.path}/main.wasm',
    ], group: true);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
    expect(File('${out.path}/main.wasm').existsSync(), isTrue);
    final page = File('web/index.html').readAsStringSync();
    expect(page, contains("import('./main.mjs')"));
    expect(page, contains("compileStreaming(fetch('main.wasm'))"));
    expect(
      File('${out.path}/main.mjs').readAsStringSync(),
      contains('export async function compileStreaming('),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
