// The package reaches dart:io through lib/src/platform/ only, so that what
// a web app compiles in imports none of it (platform.dart's rule).
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('no library of lib/ outside src/platform/ imports dart:io', () {
    final importsIo = RegExp(
      r'''^\s*(import|export)\s+['"]dart:io['"]''',
      multiLine: true,
    );
    expect(
      [
        for (final file in Directory('lib').listSync(recursive: true))
          if (file is File &&
              file.path.endsWith('.dart') &&
              !file.uri.path.contains('lib/src/platform/') &&
              importsIo.hasMatch(file.readAsStringSync()))
            file.path,
      ],
      isEmpty,
    );
  });
}
