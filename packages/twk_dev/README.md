# twk_dev — the `twk` command

Developer tools for apps built on [twk](../twk/README.md), as one
executable, `twk`, with a subcommand per tool. From this directory:

```bash
dart run twk_dev:twk --help
```

`--help`, `help <command>` and no arguments print the usage and exit with
0; an unknown subcommand or option exits with 64.

| subcommand                       | does |
|----------------------------------|------|
| `twk create <dir> [-t <template>]` | writes a new app into `<dir>` from a template (`app`, `inline`, `form`, `dashboard`): a package that runs, analyzes and passes its tests as it is |
| `twk shell [-C <dir>]`           | owns this terminal and serves it over a local socket to an app of the project started without a terminal (from the IDE, under the debugger) |
| `twk logs [-C <dir>] [--[no-]color]` | tails the log an app of the project serves over a local socket, with levels and colours |
| `twk run <file> [<arguments>...]` | runs the app in `<file>` in this terminal with hot reload: watches the package's `lib/` and `<file>` and reloads them as they change, each State kept; Ctrl+G h in the app reloads, Ctrl+G H restarts |
| `twk inspect [<vm-service-uri>] [-C <dir>]` | shows a running app's widget tree, or its render tree, the selected node's properties and layout, the node outlined on the app's screen, and selects the node under a cell clicked on the app's screen; the app at the address given, or the one `twk run` runs from the project |
| `twk record [--out=<file>] [--idle-limit=<s>] [--title=<text>] [--keys] -- <command>` | runs `<command>` in a pseudo-terminal of this terminal's size, this terminal passed through in raw mode, and records the session as asciicast v2 |
| `twk play [--speed=<factor>] [--idle-limit=<s>] <file>` | plays a recording back in this terminal |
| `twk tape <file.tape>` | runs a tape, a script of what to type into a program and when, in a pseudo-terminal, and writes the session as asciicast v2, as an animated SVG and as still SVGs of the screens it names |

`shell`, `logs` and `inspect` work for the project of the current
directory, or of `-C <dir>`: the nearest directory from there up that
holds a `pubspec.yaml`. `<dir>` is made absolute and normalised first,
so `-C a/b/..` goes up to `a`, and the project's path they print has no
`.` or `..` in it. They find each other's ends by address files in
its `.dart_tool/twk/` (`LocalAddress` in twk_core): `shell` and `logs`,
each the socket's address (`unix:<path>`, or `tcp:127.0.0.1:<port>` on
Windows, which has no Unix domain sockets) and a token on a line of its
own, which a client sends first; `run`, the WebSocket address of the VM
service of the app `twk run` runs, a line. A Unix domain socket lives
beside its address file (`shell.sock`, `logs-<pid>-<n>.sock`), or in a
new temporary directory when that path is longer than a socket's path
may be (103 bytes).

## A walkthrough

`example/tally.dart` is an app to try the tools on: Up and Down choose a
line, `+` and `-` count it, `q` quits; each count goes to the app's log
(`log()`). Each command runs from this directory, in a terminal of its
own.

1. Run the app with hot reload:

   ```bash
   TWK_DEBUG=logs dart run twk_dev:twk run example/tally.dart
   ```

   Count a few, then change the bar's `'■'` to `'●'` in `_Line.build` and
   save: the bars are drawn with dots, the counts as they were. A name
   added to the list in `main` shows once the app starts again, since
   `main` ran already: Ctrl+G H restarts it, the counts back to 0. Leave
   out a semicolon and save: the app's console opens with the compiler's
   error, the app going on with the code it had; Escape closes it, and
   the fix saved is reloaded.

2. The inspector, in a second terminal:

   ```bash
   dart run twk_dev:twk inspect
   ```

   It finds the app `twk run` runs and shows its widget tree, from
   `Tally` down to a `_Line` for each line and the `Text`s in its `Row`.
   The node selected is outlined on the app's screen, its properties and
   layout on the right. `s`, then a click on a bar in the app's terminal:
   that bar's `Text` is selected (`picked Text at 17, 2`), `pen green`
   among its properties. After an edit, `r` loads the tree again.

3. The log, in a third terminal:

   ```bash
   dart run twk_dev:twk logs
   ```

   Each count as it comes (`tea: 3`), and what `twk run` says: what it
   watches, each reload (`hot reload: 1 library in 90 ms`), why one
   failed. `TWK_DEBUG=logs` in step 1 has the app serve its log; without
   it `twk logs` waits. Ctrl+C stops it.

4. Under a debugger: quit the app (`q`), start the shell in its terminal

   ```bash
   dart run twk_dev:twk shell
   ```

   and the app under the IDE's debugger, whose console is not a terminal,
   or in another terminal, its stdout a pipe as in such a console:

   ```bash
   dart run --observe example/tally.dart | cat
   ```

   The app draws in the shell's terminal and gets the keys typed there.
   Stopped at a breakpoint, in `_count` as `+` is pressed, it leaves the
   screen as it was; keys typed meanwhile wait for it to go on. Given the
   address the VM prints, `twk inspect` inspects it there too
   (`dart run twk_dev:twk inspect http://127.0.0.1:8181/…=/`). As it
   ends, `--observe` pauses the app for the debugger: resumed there, or
   with Ctrl+C in its terminal, it exits. The shell waits for the next
   app; Ctrl+C stops it.

5. A recording: quit the shell, and record a session with the app

   ```bash
   dart run twk_dev:twk record --out=tally.cast -- dart run example/tally.dart
   ```

   Count a few and quit: `tally.cast` has the session, which plays back
   in this terminal, twice as fast:

   ```bash
   dart run twk_dev:twk play --speed=2 tally.cast
   ```

   and in a test `castFrames(Cast.read('tally.cast'))`, of
   `package:twk_dev/cast_frames.dart`, gives the screens it showed, the
   last one the app's last.

## `twk create`

```bash
dart run twk_dev:twk create ~/my_app --template=dashboard
cd ~/my_app && dart pub get && dart run bin/main.dart
```

`twk create <dir>` writes a package into `<dir>`, made if it is not
there, with the directories on the way to it: `pubspec.yaml`, `analysis_options.yaml` (pro_lints' recommended
rules, twk_lints' recommended set — the plugin with all its rules on,
[twk_lints](../twk_lints/README.md) — strict casts, inference and raw
types), `bin/main.dart`, which runs
the app, the app in `lib/<name>.dart`, its `testTwk` tests in
`test/<name>_test.dart`, a `README.md` that says how to run, hot reload,
inspect and test it, and a `.gitignore`. As written it gets its
dependencies, analyzes with no issue, passes its tests and is formatted.
`--template` (`-t`) picks the app, `--list` names them:

| template    | the app |
|-------------|---------|
| `app` (the default) | full screen: notes in a `SelectionList` beside the one chosen, a `StatusBar` above them and a `KeyHintsBar` below; Enter opens a note, Escape goes back, Tab and a click move the focus between the panes, Ctrl+Q quits |
| `inline`    | inline, below the shell's prompt: each line sent goes to the scrollback (`Static`) with the app's answer under it, a `Spinner` while it thinks; the `TextField` and the keys alone stay in the app's rows |
| `form`      | full screen: a `Form` of a name, an email, an age (`NumberInput`) and a `Checkbox`, each field's error under it; Enter goes to the next field and from the last submits, as Ctrl+S and the button do |
| `dashboard` | full screen: readings taken every second, the CPU in a `Chart` of the last minute, the memory in a `LineGauge` and the requests to each service in a `BarChart`; `p` pauses |

The package is named after `<dir>`, in lower case, other characters than
letters, digits and `_` as `_` (`My-App` gives `my_app`), or as
`--name=<package>` says: a lower case letter first, none of the words pub
refuses (Dart's reserved words, `inline`, `type`, …) and none of the
packages it depends on, or the command exits with 64.
The pubspec takes twk, and twk_test, twk_dev and twk_lints as dev
dependencies (so that `dart run twk_dev:twk run bin/main.dart` hot reloads
the app, and its analysis options include twk_lints' set), by
path from the checkout of the twk repository `--path-to-twk=<dir>` names,
or else the one the command runs from: the nearest directory from the
command's package up that holds `packages/twk`, `packages/twk_test`,
`packages/twk_dev` and `packages/twk_lints`. Without either, from pub at `^0.1.0`, which twk is
not published at yet. A `--path-to-twk` that is no checkout exits with 1,
as does a `<dir>` that is a file or under one, `--force` or not, and a
directory that is not empty unless `--force`, which writes the template's files over those of the same paths
and leaves the others: a file already as the template has it is left
alone, and named `(the same there)`, one it writes over
`(over the one there)`. `--dry-run` names the files it would write, so
marked, and writes none, nor any directory, after the same checks of
`<dir>` as the run. Both are mold's: `twk create` plans the unpack with
mold's `Unbundler.plan` (with `overwrite` for `--force`) and writes that
plan with `Unbundler.apply`, which checks the directory again, makes the
directories not there and undoes its writes, and those, when one fails.
What mold refuses is printed as mold says it, with `--force writes into
it.` after a directory that is not empty, which mold's library leaves to
its caller.

Each template is a package of this repository, `templates/<name>/`, named
`<name>_template`, which runs, analyzes and passes its tests where it is,
taking twk, twk_test, twk_dev and twk_lints by path in the repository. Its
`mold.yaml` makes it a template of [mold](https://pub.dev/packages/mold):
the variable `package_name` replaces `<name>_template` in each casing mold
derives (`app_template`, `app-template`, `APP_TEMPLATE`, `AppTemplate`), in
the paths and the text, and leaves `pubspec.lock` and itself out.
`tool/pack_templates.dart` packs each with mold's library into
`lib/src/templates/<name>.g.dart`, the archive in base64 as
`mold pack -f base64` writes it, under a doc comment (`EmbedSource`'s
`doc`), with mold's `// ignore_for_file: type=lint` (so `dart analyze --fatal-infos` takes
them as they are), which `twk create` unpacks, so the command needs no
checkout of the repository. Packing them warns of nothing. After a
template changed:

```bash
dart run tool/pack_templates.dart
```

The pubspec's dependencies on twk, twk_test, twk_dev and twk_lints are
rewritten as
mold plans the unpack, by its `rewrite` hook (`withTwkFrom` in
`lib/src/templates/templates.dart`, `createPlan` in
`lib/src/create.dart`), so whether the pubspec there is the same is about
the one written. Not by a mold variable: whether they are taken by path
or by version is a choice of the command, each a YAML of another shape,
while mold's substitutions put a value in place of a literal; and the
template's pubspec takes them by paths in the repository, which a
`{{ … }}` in their place would break, so a path is no value of the
template for mold's `yamlString` to quote, and `withTwkFrom` quotes it.

## `twk shell`

Run it in a second terminal, then start the app from the IDE: its
`Terminal.open()` finds no terminal on stdin and stdout, finds the
project's shell instead, and draws in the shell's terminal over the
socket (twk_core's `TerminalShell`, `Terminal.connect`). The app is
paused at a breakpoint, the screen stays as it was; the app does its
capability probe, its modes and its frames over the socket as it does on
its own terminal, and its stdout and stderr stay the IDE's.

The shell holds what the app can't from its own process: raw mode while
an app has the terminal (input passed on byte for byte, Ctrl+C
included), each change of size (SIGWINCH, polled on Windows), and
putting the terminal back: the app tells the shell the bytes that undo
its modes as it sets them, and when it goes away without writing them —
killed, or restarted by the debugger — the shell writes them and turns
the console back to cooked mode. Output is written a whole frame at a
time, so a killed app leaves no sequence cut short. One app at a time:
a newer one takes the terminal over and the older one is disconnected
(its `run()` ends with a `TerminalException`), as when the shell goes
away. Between apps the shell is in cooked mode and drops input; Ctrl+C
then stops it (exit 0), as do SIGTERM (143) and SIGHUP (129), each
putting the terminal back and removing the address file. A second shell
for the same project, or one started without a terminal, exits with 1.

## `twk logs`

An app serves its log with `LogSink.serve()` (twk_core), until
`LogSink.close()`: `TwkApp.logs`, where `print`, `log()` and uncaught
errors go while the app owns the screen. A `TwkApp` does so itself while
it runs when `TWK_DEBUG` names `logs`, so an app needs no code for it:

```bash
TWK_DEBUG=logs dart run packages/twk_core/example/chat_demo.dart  # from the root
dart run twk_dev:twk logs -C ../..    # here, in another terminal
```

`twk logs` connects to the app
the project's address file `logs` names (the last one that started
serving), sends the token, prints the records the sink kept and then each
one as it comes, `09:05:07.042 warning message: error` and the stack
below, on stdout; with colours (the time and the stack dim, the level
and the error dim, cyan, yellow or bold red by level) when stdout is a
terminal that takes escape sequences and `NO_COLOR` is not set, or as
`--[no-]color` says. While no app
serves, and after one ends, it says so on stderr and waits for the next.

## `twk run`

```bash
# from the repository's root: packages/twk's counter, hot reloaded
dart run packages/twk_dev/bin/twk.dart run packages/twk/example/counter.dart
```

The app in `<file>` has this terminal to itself: `twk run` starts it with
`dart run` and the VM service on (on a port the OS picks, with
`-DSILENT_VM_SERVICE=true`, so that the VM says nothing of it on the
app's screen), gives it its own stdin, stdout and stderr, and writes
nothing to them while the app runs. The arguments after `<file>` are the
app's (`twk run bin/main.dart --inline`). The app's debug keys are on:
`keys` is added to the `TWK_DEBUG` it gets.

`twk run` connects to the VM service (`package:vm_service`) and watches
the `lib/` of the package `<file>` is in, the nearest directory from it
up that holds a `pubspec.yaml`, and `<file>`. When a `.dart` file there
changes, or is moved there as editors that save safely do, it reloads
the sources 100 ms after the last change (`reloadSources`) and calls the
binding's `ext.twk.reassemble` (twk's `AppBinding.reassemble`): every
element is rebuilt, each State kept, every render object laid out and
painted again and the whole screen written again, so the code changed
shows. A file elsewhere, a sibling of `<file>` or one of another package,
is reloaded by hand: Ctrl+G h in the app. What `main` built, and code
that ran already, a reload leaves as it was: Ctrl+G H restarts the app —
SIGTERM, on which the app puts the terminal back and exits, SIGKILL if it
has not after 5 s — and starts it again, its state new. The app is
reloaded once its binding runs (its first `runApp`), which registers the
extensions: a change seen before is reloaded then, newer as it may be than
the sources the app was compiled from.

What `twk run` says goes to the app's log (`ext.twk.log`), which the
app's console lists (Ctrl+G c) and `twk logs` tails (with
`TWK_DEBUG=logs`): what it watches, each reload
(`hot reload: 2 libraries in 61 ms`), and why one failed — the compiler's
errors, at the error level, which opens the console. The app goes on
with the code it had.

The keys are the app's because the app has stdin: `twk run` reads no
keys of its own. Ctrl+G h and Ctrl+G H are debug keys of the binding,
which post an event, `twk.reload` or `twk.restart`, on the VM service's
`Extension` stream (`dart:developer`'s `postEvent`) that `twk run` listens
to: they work in the terminal the app is in, the same on every platform,
with nothing to type elsewhere and no process to find; an app run
without `twk run` says in its log that no tool listens.

While the app runs, the WebSocket address of its VM service is in
`.dart_tool/twk/run` of the project of the current directory, where
`twk inspect` finds it: written whole once the VM says where it listens,
again for an app restarted, and removed as `twk run` ends, unless another
`twk run` of the project wrote it since.

`twk run` ends when the app does, with its exit code, or 128 and the
signal's number when a signal ended it, as a shell gives it. SIGINT,
SIGTERM and SIGHUP end the app as a restart does, then `twk run`, with 128
and the signal's number; Ctrl+C reaches `twk run` only while no app has
the terminal in raw mode, as while one starts. On Windows, which has no
SIGTERM, a restart kills the app without the terminal put back; `twk run`
has not been run on Windows or macOS.

## `twk inspect`

The inspector is an app of its own, made of twk's widgets, in a second
terminal; it inspects the app over the binding's service extensions
(`ext.twk.*`, twk's `AppBinding.callServiceExtension`), as a client of
the app's VM service (`package:vm_service`):

```bash
dart run packages/twk_dev/bin/twk.dart run packages/twk/example/counter.dart  # one terminal
dart run packages/twk_dev/bin/twk.dart inspect                                # another, same directory
```

Without an address it reads `.dart_tool/twk/run` of the project
(`twk run` above), waits while no app is there, and once one has gone
waits for the next, so it follows `twk run`'s restarts. With
`<vm-service-uri>`, the address the VM prints
(`http://127.0.0.1:8181/token=/`, as `dart run --observe` says) or its
WebSocket one (`ws://…/token=/ws`), it inspects that app alone: nothing
answering there
exits with 1, as does no terminal (its output piped or in CI included:
it takes no [plain output](../twk_core/doc/design.md#17-terminal-and-platforms));
more than one address with 64. The app
is the isolate that registered `ext.twk.tree`, its first `runApp`; one
answering in another version of the extensions' JSON than this twk's
(`AppBinding.serviceExtensionsVersion`) is said so.

The screen: the widget tree in a `TreeView` on the left, from the app's
widget (the binding's own nodes above it left out), each node's type,
key and first unnamed property (a text's string), `error` and `overflow`
flags in red; on the right the selected node's properties
(`ext.twk.properties`: id, key, its render object or element, the
properties, flags) and layout (`ext.twk.layout`: constraints as
`w 0..80, h 24`, size, offset in its parent, place on the screen); a
status row and
the keys (`KeyHintsBar`) below, in a `SplitView` whose divider drags. The
arrows, the mouse and the tree's keys select; the node selected is
outlined on the app's screen (`ext.twk.highlight`) until `h` turns that
off. `s` has the app pick a node (`ext.twk.flags` `select`, twk's
`DebugAids.select`): the app's terminal reports the mouse, the node under
it outlined; a click there selects that node here (`ext.twk.select`), its
ancestors expanded, and Escape there, or `s` here again, cancels; an app
that runs inline, whose terminal keeps the mouse, cannot pick. `t` shows
the render tree from its root, and back, the node's counterpart (an
element's render object, a render object's element) selected. The tree is
loaded as the app comes, on `r`, when this terminal gets the focus back
(a focus report) and after a pick, again shortly while the app has drawn
no frame; nodes are kept expanded and selected by id, those not seen
before expanded. `q` quits, the pick and the outline taken off the app.

## `twk record` and `twk play`

```bash
dart run packages/twk_dev/bin/twk.dart record --keys --out=s.cast -- \
    dart run packages/twk/example/counter.dart     # from the repository's root
dart run packages/twk_dev/bin/twk.dart play --speed=2 s.cast
```

`twk record` runs `<command>` in a pseudo-terminal (twk_term's `Pty`) of
this terminal's size, with this terminal's `TERM`, and passes this
terminal through to it until the command ends: raw mode (`cfmakeraw`,
through `dart:ffi`), so every byte typed reaches the command as it is,
Ctrl+C and Ctrl+Z included, and what the command writes comes out
unchanged; a change of this terminal's size resizes the command's.
Options go before `<command>`; what follows it is the command's, `--`
or not. The recording, `--out` (`session.cast` by default), is written
as the session goes, so one cut short is read up to there:

```text
{"version":2,"width":100,"height":30,"timestamp":1792427943,"idle_time_limit":2.0,"command":"dart run example/tally.dart","title":"dart run example/tally.dart","env":{"TERM":"xterm-256color","SHELL":"/usr/bin/zsh"}}
[2.000000, "o", "\u001b[?2026$p…"]
[2.009538, "i", "\u001b[?2026;2$y…"]
[3.512113, "r", "120x40"]
```

an `o` event for each piece the command wrote, an `i` event for each
piece typed with `--keys` (the terminal's answers to the app's queries
among them), an `r` event for each change of size, at its time since
the start: a pause longer than `--idle-limit` seconds (2; 0 keeps each)
is cut to it, and the header says so (`idle_time_limit`). UTF-8 is
decoded a stream each, a character split between two pieces put
together. The header has the size, the time, `TERM` and `SHELL`, the
command line and `--title` (the command line by default).

It ends with the command's exit code, once the command has ended and
its terminal hung up (what it left running is hung up 2 s after it
ended); with 128 and the signal's number on SIGINT, SIGTERM or SIGHUP,
which hang the command's terminal up (SIGKILL after 2 s more). Then the
terminal is put back: what the command left turned on — the alternate
screen, mouse or paste reports, a hidden cursor, autowrap off, kitty
keyboard flags, a cursor shape — is turned off (written to the terminal,
not to the recording), and the modes raw mode changed are restored, also
when the recording failed (a write to the file did: the command is hung
up, exit 1). Stopped (SIGSTOP, SIGTSTP from elsewhere: Ctrl+Z goes to
the command) it can't put the terminal back, which the shell does as it
takes it; continued, SIGCONT can't be watched from Dart, so the
terminal's modes are checked every 200 ms and raw mode is entered again
once they changed. No command, or an `--idle-limit` that is no number,
exits with 64; a recording that can't be written with 1, a command that
can't be started with 127, neither leaving a file. Without a terminal it
records at 80 by 24 and passes stdin on.

`twk play` writes what the program wrote (the `o` events) at its times
divided by `--speed`, a pause longer than the idle limit (the header's,
or `--idle-limit`; 0 plays each) cut to it; the terminal is not resized,
so a recording plays in a terminal of its size. Raw mode meanwhile, so
what is typed is not echoed, but dropped, as are the terminal's answers
to the queries the recording has; Ctrl+C stops (exit 130; 128 and the
number on SIGINT, SIGTERM, SIGHUP), turning off what the recording left
on. At the end it waits 100 ms for answers still on their way and drops
what was not read (`TCSAFLUSH`), so none reaches the shell. A recording
it can't read, or that is not asciicast v2, exits with 1; no file, or a
`--speed` not above 0, with 64.

`package:twk_dev/cast_frames.dart` makes a recording a regression test:
`castFrames(cast)` feeds its output to twk_test's emulator (`Vt`) of the
recording's size, resizes it as an `r` event says (keeping what it shows,
as xterm does), and gives a `CastFrame` after each output event that
leaves no synchronized update (DEC 2026) open: its time, size, rows, the
cursor, and what the emulator could not take up to it.

```dart
final frames = castFrames(Cast.read('test/tally.cast'));
expect(frames.last.lines[1], startsWith('│ › coffee     1 ■'));
expect(frames.last.errors, isEmpty);
```

## `twk tape`

```bash
dart run twk_dev:twk tape example/tally.tape     # from this directory
```

A tape is a script, VHS's language: a statement a line, `#` to the end
of a line a comment (not in a quoted word or a Wait's pattern). It runs
a program in a pseudo-terminal (twk_term's `Pty`, as `twk record` does)
whose screen twk_term's emulator keeps, types into it, waits, and writes
what the program showed. `example/tally.tape` records the walkthrough's
app: hidden while it compiles and draws its first frame, then counted.

```text
Output build/tally.cast          # asciicast v2, for twk play
Output build/tally.svg           # the session, animated
Set Width 44                     # cells
Set Height 7
Set TypingSpeed 250ms
Run dart example/tally.dart
Hide
Wait /q quit/
Show
Type "++"
Down
Type "+++"
Sleep 1s
Screenshot build/tally-counted.svg
```

| statement | does |
|-----------|------|
| `Output <file>` | writes the session, once the tape has run, to a `.cast` file (asciicast v2) or an `.svg` file (an animated SVG); as many as wanted |
| `Set Width <cells>`, `Set Height <cells>` | the terminal's size: 80 by 24 |
| `Set Theme <name>` | the terminal's colours: `dark` (the default), `light`, `xterm`, or a JSON object of `#rrggbb` colours, VHS's and iTerm2's keys (`background`, `foreground`, `cursor`, `black` to `white`, `brightBlack` to `brightWhite`, `purple` for `magenta`), dark's for those left out |
| `Set FontSize <px>`, `Set FontFamily "<css>"`, `Set Padding <px>` | the SVG's text (16 px, monospace fonts) and the space around the screen (the font size) |
| `Set Framerate <n>` | the most frames a second the animated SVG takes: 50 |
| `Set TypingSpeed <time>` | the pause after each character typed and each key: 50 ms; anywhere in the tape |
| `Set WaitTimeout <time>` | how long a Wait waits: 15 s; anywhere |
| `Env <name> <value>` | in the program's environment |
| `Run <program> [<argument>...]` | the program, looked for in `PATH`, its arguments words or quoted; `sh` when there is none, with `PS1='$ '` |
| `Type[@<time>] "<text>"` | types the text, a character at a time, the typing speed (or `@<time>`) after each |
| `<key>[@<time>] [<count>]` | presses a key, `count` times: `Enter`, `Tab`, `Space`, `Backspace`, `Escape`, `Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`, `Insert`, `Delete`, `F1` to `F12`, and with `Ctrl+`, `Alt+`, `Shift+` before it those and a character (`Ctrl+C`, `Alt+Shift+Tab`) |
| `Sleep <time>` | waits |
| `Wait[+Screen\|+Line][@<time>] /<regexp>/` | waits until the screen's text (rows a line each; `+Line`, the cursor's row) matches, or `"<text>"` shows; past the timeout the tape fails |
| `Hide`, `Show` | the time between them is cut from the recording; at the Show the screen is drawn as it is then |
| `Screenshot <file.svg>` | writes the screen as it is to a still SVG |

A time is a number of seconds, or of `ms`, `s` or `m` (`500ms`, `1.5s`,
`2`, `1m`); strings are quoted with `"`, `'` or `` ` ``, without escapes
(a quote of another kind goes inside); in a pattern `\/` is a slash. A
statement other than Output, TypingSpeed and WaitTimeout comes before
the first that does something. Paths are the current directory's, a
file's directory made when missing; the program runs in it too.

The program's terminal is `xterm-256color` with `COLORTERM=truecolor`,
of the theme's colours: the emulator answers the program's queries
(the cursor's position, the colours by OSC 10, 11 and 4, the modes) as
a terminal does, and what the tape types goes through it too, encoded
as the program's modes want it (an arrow as `ESC O A` once the program
asked for application cursor keys; the kitty keyboard protocol). A
Wait looks at the screen after each piece the program writes, not while
a synchronized update (DEC 2026) is open.

What the program writes is recorded at its real time since the start,
without the time between a Hide and its Show (a tape that hides before
anything was recorded, from the start): in the `.cast` file an `o`
event for each piece, and at a Show one that draws the screen as it is
then (the alternate screen entered when the program is on it, each cell
in its style, the cursor where it is, shown or hidden). The animated
SVG has a frame after each piece that leaves no synchronized update
open, a frame within 1/`Framerate` s of the last taking its place and
one that shows the same as the last none; it plays them at their times
to the end of the tape, then again, as svg-term does: the frames side
by side in a strip that a CSS animation moves under a window of a
screen's size, a step a frame; each row is drawn once (`<defs>`) and
used by every frame that shows it. A row is a `<text>` a run of cells
of a style, as long as its cells (`textLength`), a wide character one
of its own, and a `<rect>` a run of cells of a background; box-drawing
lines (light and heavy, rounded corners) are paths and block elements
rectangles, so that they meet the next cell's and the next row's as a
terminal draws them; double and dashed lines are text. Colours 0 to 15
are the theme's, the rest xterm's.

When the tape has run, the recording ends, the program is hung up
(`Pty.close`: SIGHUP as its terminal goes) and, still running 2 s
later, killed through its terminal (`Pty.kill`), then the outputs are
written; a Screenshot is written when the tape gets to it. A Wait that
timed out ends the tape with 1 and the screen, writing no output; so
does an output that can't be written; SIGINT, SIGTERM and SIGHUP end it
with 128 and the signal's number, writing nothing. A tape that can't be
read or is wrong (the line is said) exits with 1, a program that can't
be started with 127, no tape with 64.

## Layout and tests

`bin/twk.dart` only sets the exit code from `runTwk` in `lib/src/cli.dart`,
which builds the subcommands with `package:args`; `lib/src/shell.dart`
and `lib/src/logs.dart` are two commands over twk_core, which the
package takes by path, and `lib/src/run.dart` is `twk run`, a client of
the app's VM service (`package:vm_service`). `twk inspect` is
`lib/src/inspect.dart`, the command and `RunningApps`, the apps found by
the service file; `lib/src/app_client.dart`, `AppClient`, what the
inspector asks an app, and `VmAppClient`, over the VM service; and
`lib/src/inspector_view.dart`, `InspectorView`, the screen, on twk, which
the package takes by path. `twk create` is `lib/src/create.dart`, over
mold's `Unbundler`; its templates are packages in `templates/`, packed by
`tool/pack_templates.dart` into `lib/src/templates/`, which
`templates.dart` names. `twk record` is `lib/src/record.dart`, over
twk_term's `Pty`, which the package takes by path; `twk play`
`lib/src/play.dart`; both write and read asciicast v2 with
`lib/src/cast.dart` (`Cast`, `CastWriter`, exported by
`package:twk_dev/twk_dev.dart`), put the terminal in raw mode with
`lib/src/raw_tty.dart` and turn off what the output left on with
`lib/src/modes.dart`. `lib/cast_frames.dart` plays a recording through
twk_test's emulator, which the package takes by path for it. `twk tape`
is `lib/src/tape.dart`, the command, `TapeRunner` (its pauses those of
a `TapeClock`, the real time by default) and `redraw`, over
twk_term's `Pty` and `TerminalEmulator`; its language is
`lib/src/tape/script.dart`, its themes `theme.dart`, the SVG
`svg.dart` (`screenSvg`, `SvgFilm`) and the characters it draws as
shapes `glyphs.dart`. `example/tally.tape` is the walkthrough's app
recorded.
`example/tally.dart` is the walkthrough's app.

`test/command_test.dart` runs `dart run twk_dev:twk` the way a developer
does, and `runTwk` in the test's process where a command does not get as
far as the terminal: `--help` must list exactly the eight subcommands, `twk inspect` with
two addresses must exit with 64, with one nothing answers at and without
a terminal with 1, `twk run` without a file must exit with 64
and with a file that is not there with 1, `twk shell` without a terminal
must say so and exit with 1, `twk record` and `twk play` must exit as
above on what they can't do, `twk record` without a terminal record at 80
by 24, `twk tape` exit as above on what it can't do (a statement there
is not with its line), and an unknown subcommand must exit with 64.
`test/tape_test.dart` parses a tape of every statement, the errors with
their lines, the times and the themes; draws a known screen as a still
SVG, to the byte (runs of a style, a background, box lines, a wide
character, escaping), the theme's colours, a reversed cell, dim text,
blocks and the cursor; plays frames at their times, a row drawn once,
a frame within the gap taking the last one's place and one that shows
the same none; and draws a screen with `redraw` into a second emulator,
which must then show the same cells in the same styles, the cursor and
the alternate screen. `test/tape_run_test.dart` runs tapes in a
pseudo-terminal: typed at the typing speed through `cat`, a Sleep, the
time between a Hide and its Show cut and the screen drawn at the Show,
the animation's frames at the recording's times, these on a clock that
moves by the tape's pauses alone, so that the times are the tape's
however loaded the machine; a Wait for the screen
and for the cursor's line, one that times out failing with the screen
and writing nothing; a tape stopped ending at once; the program gone
after each; keys encoded as the program's modes want them; and the
walkthrough's app through a tape, its recording played through
`castFrames` to the screen it showed, its screenshot and animation
written.
`test/record_test.dart` runs `twk record` in a pseudo-terminal (twk_term's
`Pty`) shown by twk_term's emulator, which answers the app's queries,
the tty's modes read and set through a descriptor the test holds
(`test/terminal.dart`): the walkthrough's app recorded with `--keys`,
counted and resized, must give the header, the keys, the resize and
pauses of 2 s at most, the tty must be raw meanwhile and as before at
the end, and the recording's last frame must be the screen the terminal
showed; without `--keys` no `i` event, the command's exit code the
command's; what a command left on turned off but not recorded; a
recording that can't be written (a FIFO whose reader went away) must
end with 1 and the tty put back, as must SIGTERM with 143; stopped, the
tty put back by the test as a shell does, and continued, it must be raw
again. `test/play_test.dart` plays recordings written by the test so:
the `o` events alone, at their times by `--speed` with the pauses cut;
Ctrl+C stopping with 130 and what was left on turned off; what is typed
meanwhile not reaching the shell after it. `test/cast_test.dart` reads
and writes asciicast v2 (the pauses cut, a character split between two
pieces), follows the modes an output leaves on, and plays recordings
through the emulator, a frame each.
`test/run_test.dart` runs `twk run` on an app of a package it makes in a
temporary directory, which draws on a terminal in memory and writes each
frame to stdout as base64 for the test's emulator, its stdin the
terminal's input: an edit of `lib/` and of the app's `main`, one saved by
a move, must show with the count kept, Ctrl+G h must reload a file not
watched, a syntax error must open the console with the compiler's error
while the app goes on, Ctrl+G H must start the app again and the new one
be reloaded; the arguments after the file must reach the app, and a
change made while it starts must be reloaded once its binding runs; an
app that does not compile, one a signal ends, and `twk run` stopped by
SIGTERM must end as above. The binding's side (`ext.twk.reassemble`,
`ext.twk.log`, the keys) is tested in twk's
`test/binding/hot_reload_test.dart`.
`test/inspect_test.dart` runs `twk run` in a package it makes, on an app
that draws on a terminal in memory whose input is stdin, and finds it as
`twk inspect` does, by the service file: its tree must be read, the node
at a cell selected, a click the app picks (the mouse report written to
its stdin) come as that cell, the node outlined, an id of no node
answered with the app's message, and after Ctrl+G H the restarted app be
found again; once `twk run` has ended, the file must be gone.
`test/inspector_view_test.dart` runs the screen with `testTwk` on canned
answers of a fake app: the tree from the app's widget with the details of
its node and the outline, the keys moving both, `h`, a pick selecting a
node below a collapsed one, a pick cancelled or stopped, an app inline,
the render tree with the counterpart selected, a load again on `r` and
on the focus with new nodes expanded, a tree loaded again until the app
has drawn its first frame, an error said, and apps that come and go.
The app's side of the pick is tested in twk's
`test/binding/service_extensions_test.dart`.
`test/create_test.dart` runs `twk create` in the test's process
(`runTwk`): each template, written
with `--path-to-twk` at this checkout, must make a package of exactly its
files that `dart pub get --offline`, `dart analyze` (no issues),
`dart test` and `dart format --set-exit-if-changed` pass; by default the
`app` template must be written, the package named after the directory and
twk taken by path from this checkout; a pubspec without a checkout must
take the packages from pub at twk's version, a path YAML would misread
quoted; `--dry-run` must name the files and write none, and with
`--force` which it would write over; into a directory whose parents are
not there `--dry-run` must make none of them and the run must make them;
a directory that is not empty must be refused with 1, saying `--force`,
and written into with `--force`, the other files kept and the one
written over named so; `--force` over the package it made must name each
file the same there and write none of them; the pubspec must be
rewritten in mold's plan, one there as the template has it written over
and one as `twk create` writes it the same there; no directory, two, a
bad name and an unknown template must exit with 64, a `--path-to-twk`
that is no checkout with 1, and a file for the directory or on the way
to it with 1, with `--force` and `--dry-run` too, and no word of
`--force`. `--list` must name the
templates. `test/templates_test.dart` packs each template in `templates/`
as `tool/pack_templates.dart` does and fails when mold warns of anything
or its packed source is not what that gives, until the script is run again; `twk create` must
offer each, and each must take twk, twk_dev, twk_lints and twk_test by
path and
nothing else.
`test/example_test.dart` runs the walkthrough's app with `testTwk`: a
line for each name, the keys counting the line chosen and choosing,
`-` stopping at 0, each count in the log, `q` quitting, and the counts
and the line chosen kept by `AppBinding.reassemble`, which a hot reload
calls.
`test/logs_test.dart` checks how a record is printed (padding, colours,
the stack), and a line of the log that is one, and runs `twk logs`
against sinks served in the test: waiting for an app, the records kept
and live, the next app after one ended. `test/project_test.dart` checks
the project a directory is in.
The shell's ends are tested in twk_core (`test/terminal/socket_test.dart`);
`twk shell` itself in a pseudo-terminal, from the repository's root:

```bash
python3 tool/pty_run.py --input '6:hello,16:\x03' --out /tmp/shell.bin -- \
    dart run packages/twk_dev/bin/twk.dart shell &
sleep 4; dart packages/twk_core/example/chat_demo.dart --seconds=3 </dev/null; wait
```

and `twk run` too, with the counter: Up counts, Ctrl+G H restarts it, q
quits; an edit of `packages/twk/example/counter.dart` meanwhile shows
with the count kept:

```bash
python3 tool/pty_run.py --input '2:\x1b[A,4:\x07H,9:q' --out /tmp/run.bin -- \
    dart run packages/twk_dev/bin/twk.dart run packages/twk/example/counter.dart
dart run tool/replay.dart --fullscreen /tmp/run.bin 100 30
```

and `twk inspect` beside it, in a pseudo-terminal of its own: the
counter counts to 2; the inspector selects two nodes down, has the app
pick one (`s`), which the click written to the counter's terminal does,
shows the render tree and the widget tree again (`t`, `t`) and quits:

```bash
python3 tool/pty_run.py --timeout 60 --size 40x8 \
    --input '2:\x1b[A,3:\x1b[A,18:\x1b[<0;4;3M,18.1:\x1b[<0;4;3m,30:q' \
    --out /tmp/app.bin -- \
    dart run packages/twk_dev/bin/twk.dart run packages/twk/example/counter.dart &
sleep 1; python3 tool/pty_run.py --timeout 60 --size 100x24 \
    --input '9:\x1b[B,10:\x1b[B,12:s,20:t,24:t,26:q' --out /tmp/inspect.bin -- \
    dart run packages/twk_dev/bin/twk.dart inspect; wait
dart run tool/replay.dart --fullscreen /tmp/app.bin 40 8           # Count: 2
dart run tool/replay.dart --fullscreen /tmp/inspect.bin 100 24     # picked Text at 3, 2
```

and `twk record` and `twk play` with the walkthrough's app, the
recording played through the test emulator by `replay.dart` as the
terminal got it, and back:

```bash
python3 tool/pty_run.py --input '3:+,3.5:\x1b[B,4:+,5:q' --out /tmp/rec.bin -- \
    dart run packages/twk_dev/bin/twk.dart record --keys --out=/tmp/s.cast -- \
    dart run packages/twk_dev/example/tally.dart
dart run tool/replay.dart --fullscreen /tmp/rec.bin 100 30         # coffee 1, tea 1
python3 tool/pty_run.py --input none --out /tmp/play.bin -- \
    dart run packages/twk_dev/bin/twk.dart play --speed=2 /tmp/s.cast
dart run tool/replay.dart --fullscreen /tmp/play.bin 100 30        # the same
```

The checks, from this directory:

```bash
dart pub get
dart analyze
dart test
dart format --output=none --set-exit-if-changed lib test bin example
```

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](LICENSE).
