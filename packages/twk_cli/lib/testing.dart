/// Test support for programs that write through `package:twk_cli`: a
/// [FakeCliTerminal] that captures what is written and replays what is
/// typed, to hand a `Cli`, or `Cli.run` through its `open:`, in place of
/// the process's terminal; and the `FakeClock` it can be timed by.
library;

import 'src/testing/fake_cli_terminal.dart';

export 'package:twk_test/twk_test.dart' show FakeClock, Vt;

export 'src/testing/fake_cli_terminal.dart';
