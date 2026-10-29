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
/// as [Cli.sourceLines] gives it; [Cli.inspect] shows a value as a
/// `JsonView` does.
///
/// [Cli] is the console, [Cli.run] and [Cli.runWithArgs] its front door;
/// [CliTerminal] is what it talks through and [CliMode] how. A fake
/// terminal for tests is in `package:twk_cli/testing.dart`.
///
/// @docImport 'package:twk/twk.dart';
library;

import 'src/capabilities.dart';
import 'src/cli.dart';
import 'src/prompt_exception.dart';
import 'src/terminal.dart';

export 'src/capabilities.dart';
export 'src/cli.dart';
export 'src/lines.dart' show messageLines;
export 'src/progress.dart' show CliProgress;
export 'src/prompt_exception.dart';
export 'src/session.dart' show CliLive, CliSession;
export 'src/terminal.dart';
export 'src/theme.dart';
