// tool/snippets.dart: the regions of the pages that are their Code, and
// the library written from them, which must be current.
import 'dart:io';

import 'package:test/test.dart';

import '../tool/snippets.dart';

void main() {
  test('a region is its lines without the indent they share', () {
    expect(
      regionsOf('''
final class _S {
  // #code sCode
  var _n = 0;

  void _up() => _n++;
  // #end
}
'''),
      [('sCode', 'var _n = 0;\n\nvoid _up() => _n++;')],
    );
  });

  test('a region without its end is an error', () {
    expect(() => regionsOf('// #code x\nvar a = 1;\n'), throwsStateError);
  });

  test('lib/src/pages/snippets.g.dart is what the regions write', () {
    expect(
      File('lib/src/pages/snippets.g.dart').readAsStringSync(),
      snippetsLibrary(Directory('lib/src/pages')),
      reason: 'dart run tool/snippets.dart writes it again',
    );
  });
}
