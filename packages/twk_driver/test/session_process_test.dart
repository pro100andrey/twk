// Session against a real twk app in a real pseudo-terminal: the probe's
// queries answered by the answering emulator, keys that change the screen
// and keys that do not, a tap on a button, a resize, the app quitting on
// `q` with its terminal back as it found it.
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk/twk.dart' show ElementFinder;
import 'package:twk_driver/twk_driver.dart';

void main() {
  late String app;
  setUpAll(
    () async => app = await compiledProgram(
      'test/app/counter_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_driver/programs',
    ),
  );

  Future<Session> start({
    int width = 80,
    int height = 24,
    List<String> arguments = const [],
  }) async {
    final session = await Session.start(
      ProcessSpec(app, arguments: arguments, width: width, height: height),
      timeout: const Duration(seconds: 30),
    );
    addTearDown(session.close);
    return session;
  }

  test('start: the probe answered, the first frame on the screen', () async {
    final s = await start();
    expect(s.screenText, contains('Count: 0'));
    expect(s.screenText, contains('Saved: 0'));
    expect(s.frame, greaterThan(0));
  });

  test('press up: the frame that counted it, and a key that changes '
      'nothing returns too', () async {
    final s = await start();
    final step = await s.press('up');
    expect(step.screen, contains('Count: 1'));
    expect(step.frame, greaterThan(1));
    await s.press('up up');
    expect(s.screenText, contains('Count: 3'));
    // nothing is bound to x: no frame, the acknowledgement answers
    final before = s.frame;
    final none = await s.press('x');
    expect(none.frame, before);
    expect(s.screenText, contains('Count: 3'));
  });

  test('type and paste are input too', () async {
    final s = await start();
    await s.type('abc');
    await s.paste('hello');
    expect(s.screenText, contains('Count: 0'));
  });

  test('a finder finds the widget with its cells, strictly', () async {
    final s = await start();
    final save = await s.findOne(const ElementFinder.text('Save'));
    expect(save.shown, isNotNull);
    await expectLater(
      s.findOne(const ElementFinder.textContaining('a')),
      throwsA(isA<DriverError>()),
    );
  });

  test('tap on the button: the app saved', () async {
    final s = await start();
    final step = await s.tap(const ElementFinder.text('Save'));
    expect(step.screen, contains('Saved: 1'));
  });

  test('resize: a frame at the new size', () async {
    final s = await start();
    final step = await s.resize(100, 30);
    expect(step.seen.width, 100);
    expect(step.seen.height, 30);
    expect(s.screen.width, 100);
  });

  test('press q on an app that quits: its exit is 0 and it left its '
      'terminal as it found it', () async {
    final s = await start();
    // the app acknowledges the key before it ends: the step comes back
    await s.press('q');
    expect(await s.exitCode, 0);
    // from then on every wait is the app's end, not a timeout
    await expectLater(
      s.press('up'),
      throwsA(
        isA<AppEnded>()
            .having((e) => e.exitCode, 'exitCode', 0)
            .having((e) => e.message, 'message', contains('exited (0)')),
      ),
    );
    final report = await s.close();
    expect(report.exitedByItself, isTrue);
    expect(report.problems, isEmpty);
    expect(report.exitCode, 0);
  });

  test("the driver's count of the app's bytes follows the tty's CRs", () async {
    final s = await start();
    await s.press('up');
    // every frame boundary the app posted was found in the bytes received
    // (an LF the tty made CR LF counted once), or the press would not
    // have returned
    expect(s.output, isNotEmpty);
    expect(s.screenText, contains('Count: 1'));
  });

  test('inline: the LFs the app writes bare reach the driver as CR LF, and '
      'every frame boundary is still found', () async {
    final s = await start(arguments: ['--inline']);
    for (var i = 1; i <= 3; i++) {
      await s.press('up');
      expect(s.screenText, contains('Count: $i'));
    }
    expect(String.fromCharCodes(s.output), contains('\r\n'));
  });
}
