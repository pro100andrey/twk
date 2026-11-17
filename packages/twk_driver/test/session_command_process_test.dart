// A session over `sh` in a real pseudo-terminal, without an app service:
// input written, waits on the output, the end of the program.
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'package:test/test.dart';
import 'package:twk/twk.dart' show ElementFinder;
import 'package:twk_driver/twk_driver.dart';

void main() {
  Future<Session> start(String script) async {
    final session = await Session.compose(
      ProcessSpec('sh', arguments: ['-c', script]),
      process: const PtyCommandPort(),
      screen: EmulatorScreen(),
      timeout: const Duration(seconds: 30),
    );
    addTearDown(session.close);
    return session;
  }

  test(
    'type a line, wait for the answer on the screen, the exit code',
    () async {
      final s = await start(r'read x; echo "got:$x"; exit 3');
      expect(s.driven, isFalse);
      await s.type('abc\n');
      final step = await s.waitFor(
        (screen) => RegExp(r'^got:abc$', multiLine: true).hasMatch(screen),
        what: 'the answer',
      );
      expect(step.screen, contains('got:abc'));
      expect(await s.exitCode, 3);
      final report = await s.close();
      expect(report.exitCode, 3);
      expect(report.exitedByItself, isTrue);
    },
  );

  test('a wait on the cursor line, and the app-only calls refused', () async {
    final s = await start(r'printf "name? "; read x; echo "hi $x"; sleep 30');
    await s.waitFor(
      (_) => s.screen.line(s.screen.cursorY).endsWith('name?'),
      what: 'the prompt',
    );
    await s.press('b o b');
    await s.press('enter');
    await s.waitFor((screen) => screen.contains('hi bob'));
    await expectLater(
      s.find(const ElementFinder.text('x')),
      throwsA(
        isA<DriverError>().having(
          (e) => e.message,
          'message',
          contains('not a twk app (no app service)'),
        ),
      ),
    );
    // closed through its own handle: the program is killed
    final report = await s.close();
    expect(report.exitedByItself, isFalse);
  });
}
