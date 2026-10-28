// An app on a headless terminal that logs in its first frame, then says
// on stdout that it runs, and quits when stdin closes: run by
// served_log_test.dart in a process of its own, in a project of the
// test's.
import 'dart:io';

import 'package:twk_core/twk_core.dart';

Future<void> main() async {
  final app = TwkApp(HeadlessTerminal(width: 20, height: 3));
  final root = RenderText('app', app.screen.styles.pen(const Pen()));
  stdin.listen((_) {}, onDone: app.quit);
  var first = true;
  await app.run(
    root,
    (_) {},
    beforeLayout: () {
      if (first) {
        first = false;
        log('first frame');
        stdout.writeln('running');
      }
    },
  );
}
