// The counter the package's README and example/README.md show, held to
// example/counter.dart: the first ```dart block of each is that file
// without its opening comment.
import 'dart:io';

import 'package:test/test.dart';

final _fence = RegExp(r'^```dart\n(.*?)^```$', multiLine: true, dotAll: true);

/// example/counter.dart without the comment lines it opens with.
String counter() {
  final lines = File('example/counter.dart').readAsLinesSync();
  final code = lines.skipWhile((l) => l.startsWith('//'));
  return '${code.join('\n')}\n';
}

void main() {
  for (final path in ['README.md', 'example/README.md']) {
    test('$path shows example/counter.dart as it is', () {
      final block = _fence.firstMatch(File(path).readAsStringSync());
      expect(block, isNotNull, reason: 'no ```dart block in $path');
      expect(block![1], counter());
    });
  }
}
