/// A console for command-line tools on twk: messages by channel and level,
/// styled as the terminal takes them, any twk widget shown in the output,
/// and, in the interactive mode, one inline twk app that prompts and
/// progress are live in while finished output is committed above them.
///
/// Its prompts ([Cli.prompt], [Cli.promptAny], [Cli.confirm],
/// [Cli.chooseOne], [Cli.chooseAny]) ask as the mode allows: a widget in
/// the inline session, a line read, or the default taken where nobody can
/// answer ([PromptException] where there is none). Its progress
/// ([Cli.progress], [Cli.tasks]) is a spinner or a list of tasks with
/// bars, rate and time left where the terminal redraws, lines where it
/// does not, the outcome alone in a log.
///
/// What [Cli.run]'s body throws ends the run with its [traceback] and an
/// exit code, as [Cli.error] shows an error the program caught, its source
/// as [Cli.sourceLines] gives it.
///
/// [Cli] is the console, [Cli.run] and [Cli.runWithArgs] its front door;
/// [CliTerminal] is what it talks through and [CliMode] how. A fake
/// terminal for tests is twk_test's, in `package:twk_test/cli.dart`. The
/// library is apart from `package:twk/twk.dart`, which it builds on: a
/// program imports both.
///
/// @docImport 'twk.dart';
library;

import 'src/cli/capabilities.dart';
import 'src/cli/cli.dart';
import 'src/cli/prompt_exception.dart';
import 'src/cli/terminal.dart';

export 'src/cli/capabilities.dart';
export 'src/cli/cli.dart';
export 'src/cli/lines.dart' show messageLines;
export 'src/cli/progress.dart' show CliProgress;
export 'src/cli/prompt_exception.dart';
export 'src/cli/session.dart' show CliLive, CliSession;
export 'src/cli/terminal.dart';
export 'src/cli/theme.dart';
