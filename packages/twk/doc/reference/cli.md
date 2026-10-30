# twk reference: `cli`

[The reference](README.md) · `lib/cli.dart`, `lib/src/cli/`, `test/cli/`,
`example/cli/`

The console of a command-line tool, `package:twk/cli.dart`, a library of
twk apart from `package:twk/twk.dart`, which a program imports beside it:
messages by
channel and level, styled as the terminal takes them, and any twk widget
printed in the output, so a CLI gets boxes, tables, task lists and
highlighted code without writing an app. Where somebody answers at a
terminal that redraws, prompts and progress are twk widgets live in one
inline twk app, with finished output committed to the terminal's history
above them. Its surface follows
[mason_logger](https://pub.dev/packages/mason_logger).

```dart
import 'package:twk/cli.dart';
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => Cli.runWithArgs(args, (cli, rest) async {
  cli.info(['Deploying ', 'staging'.bold]);
  await cli.show(
    const Box(
      border: Border.all(type: BorderType.rounded),
      child: Text('api  3/3 ready\nweb  2/2 ready'),
    ),
  );
  cli.success('Deployed.');
});
```

It builds on twk's public API alone: a string's escapes are read with
twk's `parseAnsi`, the error a run ends on is twk's `traceback`. It reaches
the process's stdio through `lib/src/platform/`, as the rest of twk does,
so that a web app, which imports `package:twk/twk.dart` alone, compiles
none of it. The fake terminal for tests is twk_test's,
`package:twk_test/cli.dart`, which reads its screen through twk_test's
emulator.

## The modes

How the console talks follows the terminal's `CliMode`, detected once
(`CliCapabilities.detect`):

| Mode             | When                                                        | Output                                                                                                                         |
| ---------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `interactive`    | somebody can answer, output takes ANSI on a terminal         | lines as they are until something needs the inline session (`show`, a prompt, a progress); then committed above what is live    |
| `plain`          | somebody can answer, output takes no ANSI or is a pipe       | lines; a widget as the lines of its text                                                                                        |
| `nonInteractive` | stdin is not a terminal, the environment says CI, `--no-input` | lines; a widget as the lines of its text; nothing is read                                                                    |

The environment is read as twk_core reads it where it opens a terminal
(`plainAsked`, `runsInCi`, `colorModeFor`), with `FORCE_COLOR`,
`--no-color` and `--no-input` on top:

- **ANSI**: `TWK_PLAIN=1` switches it off; then `FORCE_COLOR` wins
  (`0`/`false` off, anything else on); then an environment that takes no
  colors (a non-empty `NO_COLOR`, `TERM=dumb`) switches it off; otherwise
  stdout must be a terminal that supports escapes. `--no-color` wins over
  all of it.
- **Somebody can answer**: stdin is a terminal and the environment does
  not say CI (`CI`, `CONTINUOUS_INTEGRATION`, `BUILD_NUMBER` or `RUN_ID`
  set to anything but empty, `0` or `false`, unless `CI` is `0` or
  `false`); `--no-input` refuses.
- **Hyperlinks** (OSC 8): styled output on a terminal.
- **Colors**: the core's: 24-bit where `COLORTERM`, `TERM` or
  `TERM_PROGRAM` (iTerm, WezTerm, ghostty) say so and on Windows, 256
  where `TERM` does or in Terminal.app, 16 otherwise.
- **Width**, where stdout is no terminal: `COLUMNS` where it is a
  positive number, else 80.

The inline session opens the terminal as never plain, so that under CI,
where input was asked for anyway, its prompts still draw.

`CliTerminal.system()` is the process's stdio; `reserveStdout: true`
writes the output to stderr, for a program whose stdout is another's.

## Messages

| Method    | Level             | Sink   | Default style                      |
| --------- | ----------------- | ------ | ---------------------------------- |
| `detail`  | `LogLevel.debug`  | stdout | the theme's muted (dim)            |
| `info`    | `LogLevel.info`   | stdout | unstyled                           |
| `success` | `LogLevel.info`   | stdout | the theme's success (green)        |
| `warn`    | `LogLevel.warning`| stderr | the theme's warning (yellow)       |
| `err`     | `LogLevel.error`  | stderr | the theme's error (red)            |
| `alert`   | `LogLevel.error`  | stderr | bold white on red                  |
| `write`   | —                 | stdout | verbatim, no line break            |

The levels are the core's `LogLevel`; a channel is written when the
console's `level` is at or below it. `LogLevel.error` is the quiet
threshold: `--quiet` shows `err` and `alert` only, since a person who
silenced the output still needs to see the run fail.

A message is a `String`, styled text — twk's `Span`s, `'x'.bold.fg(Color.red)`
— or a list of both. A string is read as a terminal would show it: its SGR
sequences and OSC 8 links become styles, every other sequence is dropped,
and a carriage return writes over its line. So a string styled elsewhere
(a subprocess's colors, `cli.link(...)`) follows `--no-color` too, and a
string cannot move the cursor under the inline session. The channel's
style goes under the message's own; `CliTheme` restyles a channel and
carries the `ThemeData` widgets are shown in, and the styles of the
prompts' lines (`question`, bold; `answer` and the `?`, the primary color;
`hint`, muted; the `✔` in `success` and a refusal in `error`):

```dart
final cli = Cli(
  level: LogLevel.debug,
  theme: CliTheme(warning: const Style(fg: Color.yellow, attrs: Attr.bold)),
);
```

`delayed(message)` keeps a line until `flush()` writes it through `info`.
`link(uri, [text])` is an OSC 8 hyperlink where the terminal takes them, the
label alone elsewhere.

## Widgets in the output

`await cli.show(widget, width: 60)` lays the widget out at the terminal's
width (or the one given), as tall as it is there, and writes it once:

- interactive: committed to the terminal's history above what is live,
  through the inline session (twk's `Static`); the future completes once
  its rows are written;
- plain and non-interactive: built and painted once, outside an app, its
  rows written as lines of text, with the styles' escapes where the output
  takes them (`FORCE_COLOR` into a pipe), 80 columns wide where the output
  is no terminal and `COLUMNS` says nothing.

A widget built outside an app shows its first frame: what waits for focus,
a frame callback or an animation shows as it starts.

## The inline session

stdin is single-subscription, so the interactive mode opens one inline twk
app (`AppBinding` on the process's terminal, the normal screen) the first
time something needs it, and keeps it for the console's life. A host
widget at its root mounts what is live — the prompt being asked, the
progress running — in the inline region, and commits finished output above
it; lines logged while something is live land above it, and with nothing
live the region is empty. `close()` ends the app once what is committed is
written: the region cleared, the terminal restored, the cursor below the
output. `Cli.run` calls it on its way out, on an error too.

Ctrl+C that nothing live takes ends the session, the terminal restored, and
then sends the process SIGINT: it ends as it would at a cooked terminal,
unless the program watches the signal. After that the console writes lines
again, and no session opens: stdin is closed.

A program that uses `Cli.current` outside `Cli.run` and shows a widget in
the interactive mode has to `close()` it itself, or the session keeps stdin
open.

## Prompts

```dart
final name = await cli.prompt('Project name?', defaultValue: 'my_app', validate: check);
final token = await cli.prompt('Registry token?', hidden: true);
final tags = await cli.promptAny('Tags?', separator: ',');
final env = await cli.chooseOne('Target environment?', choices: ['dev', 'stage', 'prod']);
final features = await cli.chooseAny('Features?', choices: ['Linter', 'Docker', 'Tests']);
final ok = await cli.confirm('Proceed with installation?');   // no default
```

and in the history afterwards, at a terminal:

```text
✔ Project name? my_app
✔ Target environment? prod
✔ Features? Linter, Docker
✔ Proceed with installation? yes
```

How a prompt asks follows the mode:

| Mode             | How it asks                                                                                                                                                                                                                                          |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `interactive`    | a widget mounted in the inline session: a `TextField` after the question and the default, a `ConfirmInput`, a `SelectionList` (Space toggles in `chooseAny`); once answered it goes and `✔ question answer` is committed in its place |
| `plain`          | a line read as the terminal reads it: `? question (default) `; choices numbered (`1) dev`), any of them as `1,3`; asked again until the answer is one                                                                                   |
| `nonInteractive` | nothing is read: the default is the answer, written as `? question answer` so a log shows what was assumed                                                                                                                                     |

- **Defaults.** An empty answer is the default: the empty string or no
  values without one, the first choice in `chooseOne`. Where nobody can
  answer, a prompt without a default — or with one its `validate`, or
  `chooseAny`'s `min` and `max`, refuse — throws
  `PromptAnswerRequiredException` naming the question: the place to tell
  the user which flag answers it.
- **`confirm` without a default never agrees on anybody's behalf**: Enter
  answers nothing until yes or no is chosen (`y`, `n`, or Left/Right and
  Enter), and where nobody can answer it throws; a question that changes
  something wants a `--yes` flag for unattended runs. On a plain terminal
  anything but `y`, `yes`, `n` or `no` is asked again.
- **Validation.** `validate` answers null for an answer it takes, else a
  message: shown under the field (until the text changes) or as `✗ message`
  on a plain terminal, and the question is asked again. `chooseAny`'s
  `min` and `max` refuse so too.
- **Hidden answers** (`hidden: true`) are masked with one `*` per character
  in the interactive mode and not echoed on a plain terminal; written back
  they read `******` whatever their length.
- **Lists** show seven choices at once, scrolled to the cursor, which starts
  on the default. `filter: true` narrows the list as the user types
  (fuzzy, as a command palette matches; Backspace takes it back); left
  null, a list of more than seven is filtered. On a plain terminal a choice
  is also answered by its label.
- **Suggestions.** `prompt(suggest: (typed) => [...])` shows what fits the
  text before the caret under the field (twk's `Autocomplete`): Up and Down
  choose, Enter or Tab put it in, Escape hides them. The function may
  answer in a future.
- **One at a time.** A prompt asked while another is waits for it; lines
  logged meanwhile land above the one asked.

### Leaving a prompt

`PromptCancelledException` says why (`reason`), both exceptions extending
the sealed `PromptException`:

- **Ctrl+C** in the interactive mode is the prompt's: `✗ question` is
  committed in its place and the reason is `interrupt`; the session stays,
  for the next prompt. On a plain terminal Ctrl+C is the terminal's, SIGINT,
  as on any line a program reads; a hidden prompt switches echo back on
  before it is passed on.
- **Ctrl+D** at an empty field (with nothing typed to filter a list), or the
  end of input on a plain terminal, is `endOfInput`. So is a prompt asked
  after the session ended.

`close()` lets go of stdin once a plain prompt read it: a program that
prompts through `Cli.current` outside `Cli.run` closes it, or the process
does not end.

## Progress

```dart
final progress = cli.progress('Resolving dependencies');
progress.update('Resolving dependencies (12 of 24)');
progress.complete('Resolved 24 dependencies'); // or fail(...), or cancel()

final count = await cli
    .progress('Writing files')
    .run(writeFiles, done: (n) => 'Wrote $n files', failed: (e) => '$e');

await cli.tasks((tracker) => Future.wait([
  tracker.run('Downloading assets.zip', (t) => download(t.advance),
      total: size, unit: ProgressUnit.bytes),
  tracker.run('Building binary', (_) => build()),
]), hideFinished: false);
```

What a progress shows follows what the output can do:

| Output                                                       | `progress`                                                                                                   | `tasks`                                                                                        |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| redraws, somebody at it (`interactive`)                      | a spinner, the message and the time so far, live in the inline session; the closing line committed with the time it took, `✓ Built in 3.1 s` | twk's `ProgressList` live (bars, percent, rate, ETA); the list as it ends committed in its place |
| a terminal that does not redraw, or where nobody answers     | the message on start, each changed message, the closing line `✓ Built`                                      | each task's label as it starts, its summary as it ends                                          |
| not a terminal (a pipe, a file, a CI log)                    | the closing line alone                                                                                       | each task's summary as it ends: `✓ Downloading assets.zip • 3.4/3.4 MB • 2.1 s`                  |

- **Above it.** Lines logged and prompts asked while a progress is live
  land above it: a progress is mounted at the bottom of the region.
- **Closed once.** The first of `complete`, `fail` and `cancel` closes it
  (`cancel` writes no line); later calls, and `update`, are ignored.
  `run` closes it on its body's outcome, rethrowing an error, so an
  exception cannot leave a spinner, or the frames it asks for, going.
- **The tab.** Where the terminal shows a program's progress in its tab
  or taskbar (OSC 9;4: Windows Terminal, Ghostty, kitty, …), a spinner
  shows one going on and `tasks` how much of all of it is done — the mean
  of the tasks' fractions, a task without a total counted once it ends —
  in the error state once a task failed.
- **`tasks`** takes the `columns` of the list (twk's `ProgressColumn`s;
  the mark, label, bar, percent, rate and ETA by default) and
  `hideFinished`, which takes a task done or skipped out of the list and
  commits its summary above it. Its tracker (`ProgressTracker`) times the
  tasks on the terminal's clock, and is disposed once the body ends.
- **Levels.** Progress is written whatever the level, as prompts are.
- **Where nobody answers** (`CI`, `--no-input`) at a terminal that redraws,
  a progress writes lines, not a spinner: the inline session that
  draws a spinner takes the keyboard, and is opened only where somebody
  answers.

## Errors

```dart
Future<void> main(List<String> args) => Cli.runWithArgs(args, (cli, rest) {
  final config = Config.load(rest.first); // throws: a traceback, exit 1
  cli.success('Loaded ${config.name}.');
});
```

What the body of `Cli.run` throws, and what is thrown in it that nothing
catches (a future nobody awaits), ends the run as a command line ends: the
traceback on stderr, the terminal restored, the exit code set.

```text
✗ StateError: Bad state: the config has no "name"

  lib/src/config.dart:13:7
    11 │     final map = jsonDecode(text) as Map<String, Object?>;
    12 │     if (map['name'] == null) {
  ▶ 13 │       throw StateError('the config has no "name"');
    14 │     }
    15 │     return Config(map['name']! as String);

  lib/src/config.dart:13:7   Config.load
  lib/src/config.dart:20:12  Config.fetch
  bin/tool.dart:13:7         main.<fn>
  … 1 frame of twk
```

- **The traceback** is the error's type and text, the lines around the
  first frame of the app's own code (twk's `SourceExcerpt`), as
  `sourceLines:` gives them (on `Cli`, `Cli.run`, `Cli.runWithArgs`):
  highlighted as Dart with twk_rich's `dartSourceLines`, their text
  without; then the frames, the runs of the SDK's, twk's and its packages' and
  the pub cache's folded between the app's (twk's `stackLines`, as the log
  console folds them); `-v` shows every frame. The places are paths from
  the working directory, linked to their files (OSC 8) where the terminal
  takes links; without escapes where it takes none. The VM keeps no local
  variables to show.
- **The exit code** is `errorExitCode` (1); a prompt cancelled with Ctrl+C
  ends with 130. The run completes with null where its result may be null,
  as a `void` body's is, and with the error otherwise.
- **A prompt nobody answered** ends quietly: `✗ question`, and for one
  nobody could answer why (`nobody can answer, and it has no default`),
  without a traceback.
- **`handleErrors: false`** leaves what the body throws to the caller, as
  it is.
- **`cli.error(error, stack)`** writes the same traceback for an error the
  program caught; twk's `traceback(error, stack, allFrames:, context:)`
  gives its lines of spans, for a program that writes them itself.
- **A value** as twk_rich's `JsonView` shows it: its `jsonLines(value)`
  are lines of spans, which `cli.info` writes a line each.

## Flags

```dart
Future<void> main(List<String> args) => Cli.runWithArgs(args, (cli, rest) {
  // rest: args without -v/--verbose, -q/--quiet, --no-color, --no-input
});
```

`Cli.run(body, verbose:, quiet:, color:, input:)` takes them already
parsed. `-v` shows everything (`LogLevel.debug`), `-q` errors only
(`LogLevel.error`); given both, `-v` wins (`levelFromFlags`): `-q` tends to
sit in an alias, `-v` is added by hand to see what went wrong. The console
is `Cli.current` for the whole body, its asynchronous continuations
included. `open:` makes the terminal from what the flags decide, for a
test of the program.

## Testing

twk_test's `package:twk_test/cli.dart` has `FakeCliTerminal`:

```dart
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk/cli.dart';
import 'package:twk_test/cli.dart';

void main() {
  test('reports to stderr', () {
    final terminal = FakeCliTerminal();
    Cli(terminal: terminal).err('failed');
    expect(terminal.err.toString(), 'failed\n');
  });

  test('commits a widget above the region', () async {
    final terminal = FakeCliTerminal.interactive(width: 40, height: 10);
    final cli = Cli(terminal: terminal);
    await cli.show(const Text('shown'));
    await cli.close();
    expect(terminal.screenLines, ['shown']);
  });
}
```

`FakeCliTerminal()` is the non-interactive mode, `.plain(lines: [...])`
answers `readLine` with its lines, `.interactive(input: [...])` types its
input, keys as a terminal sends them (`'\x1B[B'`, `'\r'`, `'\x03'`), into
the inline session, which runs on a terminal in memory (`backend`); the
full constructor sets every capability. `out` and `err` keep what was
written outside a session; `screenLines` is the screen, the scrollback
first, as twk_test's emulator shows what reached it, the session's frames
included; `interrupts` counts the Ctrl+C passed on, `reads` the lines a
plain prompt read, `closed` whether `close()` let go of the input,
`exitCode` what `Cli.run` set, which the system terminal sets on the
process instead. A lone
Escape typed into the session is the Escape key once
`backend!.timeOutInput()` says no more input follows it. A `FakeClock` given as
`fakeClock:` times the session and the progress (`.plain` takes one too),
which then move only as the test moves the clock; `progressReports: true`
is a terminal that shows a progress in its tab, whose OSC 9;4 the session
then writes to `backend!.frames`. `Cli.run` takes one through `open:`:

```dart
await Cli.run(
  program,
  input: false,
  open: ({ansi, interactive}) => FakeCliTerminal(ansi: ansi ?? false),
);
```

## Examples

```sh
dart run example/cli/create.dart                   # prompts at a terminal
dart run example/cli/create.dart --no-color        # the plain prompts
dart run example/cli/create.dart --no-input --yes  # nobody asked: defaults
dart run example/cli/errors.dart                   # a traceback
dart run example/cli/errors.dart -v                # with every frame
dart run example/cli/progress.dart                 # a spinner, then many tasks
dart run example/cli/progress.dart --no-color      # their lines
dart run example/cli/progress.dart | cat           # their outcomes
dart run example/cli/deploy.dart                   # at a terminal
dart run example/cli/deploy.dart -v                # with the details
dart run example/cli/deploy.dart --no-color        # plain lines
dart run example/cli/deploy.dart | cat             # a pipe
```

The gallery's App › Cli page (`packages/gallery`) runs programs of its
own, prompts, progress and a traceback, on `FakeCliTerminal`, and draws
the fake terminal's screen as a terminal shows it.

## Tests

Each mode is tested through `FakeCliTerminal`, in `test/cli/`: what reaches the output
and the error output where the console writes lines, and the screen of
the emulator, the scrollback first, where it runs the inline session.

- `capabilities_test.dart`: the detection, `TWK_PLAIN`, `FORCE_COLOR`,
  `NO_COLOR`, `TERM=dumb`, `--no-color` and `--no-input` against each
  other, `CI`, `BUILD_NUMBER` and the core's other CI variables, and a
  pipe, the mode each gives, hyperlinks and the color modes, the core's
  `TERM_PROGRAM` rules among them.
- `system_terminal_test.dart`: the process's terminal on a pipe, in a
  process of its own: its width by `COLUMNS`, a positive number only.
- `cli_test.dart`: the channels and their sinks, styles and themes, no
  escapes where the terminal takes none (the strings too), `write`,
  `delayed`, the levels and the flags (`-v` over `-q`, `runWithArgs`),
  `link`, and `Cli.current`.
- `lines_test.dart`: a string read as a terminal shows it (a carriage
  return writing over its line), spans and lists of them, a line encoded
  in each color mode, and a widget's lines as tall as it is.
- `show_test.dart` and `session_test.dart`: a widget shown in each mode
  and under the console's theme; the inline session opened by what needs
  it and not by lines, the lines logged above what is live, Ctrl+C that
  nothing took ending it and passed on, `Cli.run` closing it, on an error
  too, and its fake clock.
- `prompts/`: each prompt in each mode (`interactive_test.dart`,
  `plain_test.dart`, `non_interactive_test.dart`): the answer committed
  or read, defaults, validation, hidden answers, suggestions, seven
  choices in view and the filter, numbers and labels on a plain
  terminal, `min` and `max`, Ctrl+C and Ctrl+D, the end of input, a
  prompt nobody can answer throwing and one asked while another is
  waiting for it.
- `progress_test.dart`: a progress where the output is no terminal, at
  one that does not redraw and in the session (the spinner and its time,
  the closing line, a message updated and cut short, lines and prompts
  above it, the tab's OSC 9;4, nothing left behind an error); `run`; and
  `tasks` with their bars, rate and ETA and `hideFinished`.
- `traceback_test.dart`, `run_errors_test.dart` and
  `traceback_process_test.dart`: the traceback's lines, frames folded or
  all, styles and links, past an asynchronous gap; what `Cli.run` does
  with an error the body throws or nothing catches, the exit codes, a
  prompt nobody answered; and programs run in a process of their own,
  their stderr and exit code.
