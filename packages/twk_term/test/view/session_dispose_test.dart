import 'package:test/test.dart';
import 'package:twk_term/twk_term.dart';

void main() {
  test('disposed before its program started, a session ends', () async {
    final session = TerminalSession.start('sh', const ['-c', 'true'])
      ..dispose();
    expect(session.ended, isTrue);
    expect(session.pty, isNull);
    expect(await session.exitCode, isNull);
    session.resize(20, 3);
    expect(session.pty, isNull);
  });

  test('not yet started, a session has not ended', () {
    final session = TerminalSession.start('sh', const ['-c', 'true']);
    addTearDown(session.dispose);
    expect(session.ended, isFalse);
  });
}
