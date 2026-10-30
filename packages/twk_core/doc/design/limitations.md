# twk_core design: §3 Limitations

[The design](README.md)

* **Not run on Windows** — the kernel32 code follows the documentation and
  is only checked by the analyzer. It needs a run on Windows Terminal and
  conhost. Ctrl+Break can't be watched from Dart (only CTRL_C_EVENT and
  the console closing are), so it ends the process without restoring the
  console. Older conhost builds read non-ASCII input as NUL bytes under the
  UTF-8 input code page that is set; reading through `ReadConsoleW` would
  need a Windows input backend of its own.
* **macOS**: every package's tests and the end to end runs in a
  pseudo-terminal run on it (`ci-os`); the POSIX path is the same as on
  Linux except the `struct termios` layout used to turn ISIG off.
  Terminal.app has 256 colors (by its `TERM_PROGRAM`), no styled or
  coloured underlines and, of desktop notifications, only its bell
  ([§1.11](components.md)); the last two also where its secondary device
  attributes tell it ([§1.7](terminal.md)).
* Raw mode beyond what `dart:io` does (ISIG, IXON, ICRNL off) needs the
  `struct termios` layout, known here for Linux and macOS only; elsewhere
  Ctrl+C arrives as a signal and is turned into a key, Ctrl+\ / Ctrl+Z act
  on the process and Ctrl+S may freeze output.
* `Terminal` can be opened on the process's terminal once per process:
  `close()` cancels the stdin subscription, which closes stdin. To hand the
  terminal to another program and come back there is `suspend`/`resume`
  ([§1.7](terminal.md)), which keep it paused. Over a socket
  (`Terminal.connect`) it can be opened as often as wanted.
* `twk shell` and the sockets ([§1.7](terminal.md)): not run on Windows; on
  macOS by their tests (`ci-os`). On Windows the socket is TCP on the
  loopback interface, which any local user can reach (the token in the
  project's address file guards it). Ctrl+C reaches the shell only while no
  app has the terminal; to stop it meanwhile, stop the app. `TwkApp.suspend`
  on a served terminal gives the shell's console back, but the other program
  runs in the app's own stdio; `suspendToShell` stops the app with no shell
  to continue it.
* `twk run` (hot reload, [`packages/twk_dev`](../../../twk_dev/README.md)):
  not run on Windows; on macOS by its tests (`ci-os`). On Windows, which has
  no SIGTERM, a restart (Ctrl+G H) kills the app without the terminal put
  back. A reload leaves what `main` built and code that ran already as they
  were: that takes a restart.
* Handing the terminal over: on a terminal that answers no queries, input
  the other program read can leave the app waiting for the next key once it
  takes the terminal back (dart:io's blocking read, [§1.7](terminal.md)).
  Ctrl+\ while the other program has the terminal ends the app (SIGQUIT
  can't be watched from Dart); the terminal is in cooked mode by then. Not
  run on Windows, where `suspendToShell` throws (no job control). On macOS
  dart:io takes a read that gets less input than it noted for the end of
  stdin, which input the other program read could cause (not run there).
* The widget layer, [`packages/twk`](../../../twk/doc/reference/README.md),
  covers part of what an app needs: `runApp` (full screen, inline or in a
  fixed viewport), the framework (widgets, elements, state, keys, inherited
  widgets, parent data, notifications, building in the layout), listenables,
  futures and streams and the builders over them, animations (tickers,
  controllers, tweens and curves), spinners and progress bars, style values
  and themes, text, the layout widgets over the core's boxes, borders,
  flexes, stacks, grids and wraps, a dot canvas, charts, heatmaps, a
  calendar, tables of a million rows, tree views, a file tree, task lists
  and lists of many tasks with their rate and time left, description lists,
  output written to the terminal's history, desktop notifications, the focus
  tree, key bindings and key sequences, the mouse by hit test and gestures,
  text selection with the mouse, drag and drop, an overlay with dialogs,
  toasts, tooltips, popovers, a menu bar, context menus and a command
  palette, a navigator of routes that slide in, breadcrumbs, pagination, a
  stepper of steps that validate, sections that fold, scrolling a child,
  lazy lists and scrollbars, split panes, a one-line text field and a
  multi-line text area with undo and suggestions, buttons, segmented
  buttons, checkboxes, switches, radio groups, selection lists, selects and
  confirmations, sliders, number inputs and date pickers, forms of fields
  that validate, tabs, a key hints bar, a status bar, status messages,
  callouts, badges and links, dumps of the element and render trees, a log
  console, a frame overlay, and service extensions for tools over the VM
  service, hot reload (`twk run`) and an inspector (`twk inspect`) among
  them; also floating windows and docked panels, named slots that plugins
  fill, implicit animations and transitions, skeletons that shimmer while
  content loads, effects over a subtree, drop shadows and gradients,
  semantics and a screen-reader mode, a file picker, and the pointer's shape
  and the program's progress in the terminal's tab.
  [`packages/twk_rich`](../../../twk_rich/README.md) parses Markdown and
  shows it, also as it streams in, inline a block at a time into the
  terminal's history, reads program output with ANSI sequences into styled
  spans or strips them, highlights source code (Dart, JSON, YAML, Bash,
  JavaScript, TypeScript, Python, Rust, Go and diffs), shows diffs unified
  or side by side with line numbers, draws big text and QR codes, and shows
  JSON and Dart values as a tree that folds.
  twk's [`package:twk/cli.dart`](../../../twk/doc/reference/cli.md) is
  the console of a command-line tool that is no app: where somebody answers at a terminal,
  its prompts, progress and widgets are live in one inline app, the output
  committed above them; elsewhere they are lines.
* Desktop notifications are told apart by the environment only: a
  terminal started from another may inherit its variables (a
  `TERM_PROGRAM` of its own guards against that), and tmux keeps the
  variables of the terminal it was started in, not of the one attached
  now. Inside tmux they need `allow-passthrough on`; a multiplexer inside
  another gets them wrapped once, which the outer one drops.
* Rectangle scrolling is done in hardware only where the terminal answers
  DECRQM `?69` (DECLRMM); otherwise it is a plain diff. Joining of adjacent
  cells by a grapheme-clustering terminal is broken by explicit
  positioning; a terminal that joins across a repositioned cursor can't be
  protected against (the behaviour is unspecified).
* Images ([§1.14](images.md)): inside tmux, kitty's and iTerm2's go through
  its passthrough, which takes `allow-passthrough on`; tmux drops a sequence
  over 1 MB (an iTerm2 image is one) and puts an image where it left the
  outer terminal's cursor, which can be off in a split pane (kitty's Unicode
  placeholders would place it right; they are not used). GNU screen passes
  none on. Where terminals move sixel and iTerm2 pixels within scroll
  margins is not known, so no hardware scroll passes over them. Still images
  only. `Canvas.reserve` hands cells to anything else drawn outside the cell
  model the same way: the presenter never writes, erases or compares them.
* Bidirectional text is ordered by who the terminal is taken to leave it to
  ([§1.7](terminal.md)), told by its answer or its name: a terminal
  misjudged (Konsole with its bidi rendering turned off, one of another name
  that reorders) shows right-to-left text reversed unless
  `TerminalOptions.bidi` says otherwise, and an outer terminal that
  reorders, inside tmux, which drops BDSM, reorders what the app ordered
  already. Where the terminal reorders text itself it does so a whole row at
  a time, which can mix up text in columns side by side. In visual order
  `RenderText`, and what a widget draws with `Canvas.text` itself, stay as
  stored; Arabic is not shaped (no presentation forms), which a terminal
  that leaves the reordering to the app needs; kitty, unless its `force_ltr`
  is on, reverses the letters of right-to-left words it is given in visual
  order.
* The web build ([§1.7](terminal.md)) is dart2wasm's only, and runs where
  WasmGC is (Chrome and Edge 137, Firefox 134, Safari 26.2 and later). It
  has no file system, environment or signals: `Terminal.overLink` is its
  terminal, and a `LogSink` writing a file or serving a socket throws
  `UnsupportedError`.
* Plain output ([§1.7](terminal.md)) reads input only where stdin is a
  terminal: an app that a key ends, run with no terminal at all (CI), runs
  until it ends itself or a signal ends it.
* An uncertain glyph's width error is contained, but the glyph itself may
  render clipped on a disagreeing terminal — a property of the terminal.
* Inline mode: a terminal that reflows the region's own rows on a resize (a
  narrower window wrapping them) may leave pieces of the old region above
  the repainted one; the history isn't written, but those pieces stay.
  SIGTERM restores the terminal without leaving the region: the cursor
  stays where the last frame put it. The ambiguous width is not measured
  (that would draw on the normal screen) and is taken as 1. Committed
  text is wrapped by the app into lines of their own, so a terminal that
  reflows its history on a resize doesn't join them again; the rows of a
  commit still being written when the width changes are cut or padded.
