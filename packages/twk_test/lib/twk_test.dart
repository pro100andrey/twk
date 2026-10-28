/// Testing widgets of the twk package: `testTwk` runs a test with a
/// `TwkTester`, which runs the app on a terminal in memory under a
/// `FakeClock`, delivers input as the bytes a terminal sends and reads the
/// screen back through the emulator (`Vt`), which matchers such as
/// `containsLine` and `matchesScreen` match. Finders (`find`) look for the
/// app's widgets, and the tester records its frames (`RecordedFrame`).
/// What only real time brings (a process, a socket, a file) is waited for
/// with a bound by `waitUntil` and `waitFor`; a program a test runs in a
/// process of its own is compiled once, and kept for the runs after, by
/// `compiledProgram`, and started by `startProcess` or `runProcess`, which
/// end it, and with `group` what it started, when the test ends, however
/// it ends.
library;

export 'src/fake_clock.dart' show FakeClock;
export 'src/fake_stderr.dart' show FakeStderr;
export 'src/finders.dart' hide appRoot;
export 'src/matchers.dart';
export 'src/process.dart' show runProcess, startProcess;
export 'src/program.dart' show compiledProgram;
export 'src/recording.dart' show RecordedFrame;
export 'src/screen_text.dart';
export 'src/shot.dart' show Shot;
export 'src/tester.dart' show TwkTester, testTwk;
export 'src/wait.dart' show waitFor, waitUntil;
export 'vt.dart' show Vt, VtCell;
