@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'package:test/test.dart';
import 'package:twk_test/driver.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  driverTest('the counter counts on Up and quits on q', (d) async {
    // the real program in a pseudo-terminal, on time the test moves
    final app = await d.start('../twk/example/counter.dart', size: (40, 7));
    expect(app.screen, containsLine(contains('Count: 0')));
    await app.press('up');
    expect(app.screen, containsLine(contains('Count: 1')));
    // the app's exit, and the terminal it gave back, are checked
    final step = await app.press('q');
    expect(step.exit!.code, 0);
  });
}
