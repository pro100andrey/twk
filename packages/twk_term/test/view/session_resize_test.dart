@Tags(['process'])
library;

import 'package:test/test.dart';
import 'package:twk_term/twk_term.dart';

void main() {
  test('a size below one is clamped for the program too', () {
    final session = TerminalSession.start('sh', const ['-c', 'sleep 30']);
    addTearDown(session.dispose);
    session.resize(20, 3);
    expect(session.pty, isNotNull);
    // Pty.resize refuses 0; the emulator's size is 1 x 1
    session.resize(0, 0);
    expect(session.emulator.width, 1);
    expect(session.emulator.height, 1);
  });
}
