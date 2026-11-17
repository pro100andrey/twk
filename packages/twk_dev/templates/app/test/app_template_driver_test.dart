@Tags(['process'])
library;

import 'package:test/test.dart';
import 'package:twk_test/driver.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  // the app as a user's terminal runs it: a real process, keys as bytes, the
  // screen read back through an emulator
  driverTest('Down chooses the next note, Ctrl+Q quits the process', (
    d,
  ) async {
    final app = await d.start('bin/main.dart', size: (60, 12));
    expect(app.screen, containsLine(contains('╭ Welcome ')));
    await app.press('down');
    expect(app.screen, containsLine(contains('╭ Keys ')));

    final step = await app.press('ctrl+q');
    expect(step.exit!.code, 0);
  }, tags: 'process');
}
