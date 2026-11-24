// The variables of the terminal a test runs in, which a program in a
// pseudo-terminal of the tests is not in: tool/pty_run.py's HOST_TERMINAL
// and twk_term's pty.dart (_hostTerminal) leave out the same ones.
import 'dart:io';

import 'package:test/test.dart';

/// The quoted names between [start] and the next [end] in [file].
Set<String> _names(String file, String start, String end) {
  final text = File(file).readAsStringSync();
  final from = text.indexOf(start);
  expect(from, isNonNegative, reason: '$start in $file');
  final body = text.substring(from, text.indexOf(end, from + start.length));
  return {
    for (final m in RegExp('[\'"]([A-Z_]+)[\'"]').allMatches(body)) m[1]!,
  };
}

void main() {
  test('pty_run.py and twk_term leave out the same host variables', () {
    final python = _names('tool/pty_run.py', 'HOST_TERMINAL = {', '}');
    final dart = _names(
      'packages/twk_term/lib/src/pty/pty.dart',
      'const _hostTerminal = {',
      '};',
    );
    expect(python, isNotEmpty);
    // COLORTERM: pty_run.py leaves it out, twk_term sets it to truecolor
    // (ptyEnvironment), both so that the host's does not reach the program
    expect(python.difference(dart), {'COLORTERM'});
    expect(dart.difference(python), isEmpty);
  });
}
