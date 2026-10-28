// An app run by frame_overlay_test.dart in a process of its own, under the
// TWK_DEBUG the test sets: once it has run for a while it prints which
// debug aids are on, then the rows of its screen that are not blank.
//
// Its time is a fake clock's, as in a widget test: how long "a while" is
// does not hang on how busy the machine is. On the real clock a loaded
// machine left the frame the overlay is shown in for after the print.
// ignore_for_file: avoid_print
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show FakeClock, Vt;

import '../binding/harness.dart' show Label;

Future<void> main() async {
  final clock = FakeClock();
  final term = HeadlessTerminal(width: 50);
  final binding = clock.run(
    () => AppBinding(term, maxFps: 1000, clock: clock.stopwatch),
  );
  final done = clock.run(() => binding.run(const Label('app')));
  await clock.elapse(const Duration(milliseconds: 300));
  final debug = binding.debug;
  print(
    'keys ${debug.keys}, overlay ${debug.overlay}, '
    'console ${debug.console.isOpen}, rainbow ${debug.rainbow}, '
    'relayout ${debug.relayout}',
  );
  final vt = Vt(term.width, term.height);
  term.frames.forEach(vt.feed);
  for (final line in vt.lines) {
    if (line.isNotEmpty) {
      print(line);
    }
  }
  clock.run(binding.quit);
  await clock.elapse(Duration.zero);
  await done;
}
