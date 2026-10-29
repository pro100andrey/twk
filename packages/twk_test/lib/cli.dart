/// Test support for programs that write through `package:twk/cli.dart`: a
/// [FakeCliTerminal] that captures what is written and replays what is
/// typed, to hand a `Cli`, or `Cli.run` through its `open:`, in place of
/// the process's terminal; and the `FakeClock` it can be timed by.
library;

import 'src/cli/fake_cli_terminal.dart';

export 'src/cli/fake_cli_terminal.dart';
export 'twk_test.dart' show FakeClock, Vt;
