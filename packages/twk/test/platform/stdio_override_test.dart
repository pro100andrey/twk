// A stdout a test puts in by IOOverrides that says it is a terminal is one,
// for twk's CLI and for the core, as a pseudo-terminal of no size is too
// (sizeless_terminal_test, sizeless_pty_test).
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/src/platform/io.dart' show stdioIsTerminal;
import 'package:twk_core/twk_core.dart' as core show stdioIsTerminal;

/// A stdout that says whether it is a terminal, and does nothing else.
final class _Said implements Stdout {
  _Said({required this.hasTerminal});

  @override
  final bool hasTerminal;

  @override
  Object? noSuchMethod(Invocation invocation) => null;
}

void main() {
  for (final terminal in [true, false]) {
    test('a stdout put in that says it is ${terminal ? '' : 'not '}a '
        'terminal is ${terminal ? 'one' : 'none'}', () {
      IOOverrides.runZoned(() {
        expect(stdioIsTerminal(), terminal);
        expect(core.stdioIsTerminal(), terminal);
      }, stdout: () => _Said(hasTerminal: terminal));
    });
  }
}
