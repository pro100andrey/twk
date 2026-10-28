// Three frames of an app on HeadlessTerminal, for timeline_test.dart,
// which runs it with the VM's timeline recorded to a file; first a mark
// of its own on the Dart stream, there whatever twk puts on it.
import 'dart:developer';

import 'package:twk_core/twk_core.dart';

Future<void> main() async {
  Timeline.instantSync('timeline_app');
  final app = TwkApp(HeadlessTerminal(width: 20, height: 3), maxFps: 1000);
  final text = RenderText('frame 1', app.screen.styles.pen(const Pen()));
  var frames = 0;
  await app.run(
    text,
    (_) {},
    beforeLayout: () {
      if (++frames == 3) {
        app.quit();
      } else {
        text.text = 'frame ${frames + 1}';
        app.requestFrame();
      }
    },
  );
}
