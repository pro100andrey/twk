# A walkthrough

`example/tally.dart` is an app to try the tools on: Up and Down choose a line,
`+` and `-` count it, `q` quits; each count goes to the app's log (`log()`).
Each command runs from this directory, in a terminal of its own.

1. Run the app with hot reload:

   ```bash
   TWK_DEBUG=logs dart run twk_dev:twk run example/tally.dart
   ```

   Count a few, then change the bar's `'■'` to `'●'` in `_Line.build` and
   save: the bars are drawn with dots, the counts as they were. A name added
   to the list in `main` shows once the app starts again, since `main` ran
   already: Ctrl+G H restarts it, the counts back to 0. Leave out a semicolon
   and save: the app's console opens with the compiler's error, the app going
   on with the code it had; Escape closes it, and the fix saved is reloaded.

2. The inspector, in a second terminal:

   ```bash
   dart run twk_dev:twk inspect
   ```

   It finds the app `twk run` runs and shows its widget tree, from `Tally`
   down to a `_Line` for each line and the `Text`s in its `Row`. The node
   selected is outlined on the app's screen, its properties and layout on the
   right. `s`, then a click on a bar in the app's terminal: that bar's `Text`
   is selected (`picked Text at 17, 2`), `pen green` among its properties.
   After an edit, `r` loads the tree again.

3. The log, in a third terminal:

   ```bash
   dart run twk_dev:twk logs
   ```

   Each count as it comes (`tea: 3`), and what `twk run` says: what it
   watches, each reload (`hot reload: 1 library in 90 ms`), why one failed.
   `TWK_DEBUG=logs` in step 1 has the app serve its log; without it `twk logs`
   waits. Ctrl+C stops it.

4. Under a debugger: quit the app (`q`), start the shell in its terminal

   ```bash
   dart run twk_dev:twk shell
   ```

   and the app under the IDE's debugger, whose console is not a terminal, or
   in another terminal, its stdout a pipe as in such a console:

   ```bash
   dart run --observe example/tally.dart | cat
   ```

   The app draws in the shell's terminal and gets the keys typed there.
   Stopped at a breakpoint, in `_count` as `+` is pressed, it leaves the
   screen as it was; keys typed meanwhile wait for it to go on. Given the
   address the VM prints, `twk inspect` inspects it there too (`dart run
   twk_dev:twk inspect http://127.0.0.1:8181/…=/`). As it ends, `--observe`
   pauses the app for the debugger: resumed there, or with Ctrl+C in its
   terminal, it exits. The shell waits for the next app; Ctrl+C stops it.

5. A recording: quit the shell, and record a session with the app

   ```bash
   dart run twk_dev:twk record --out=tally.cast -- dart run example/tally.dart
   ```

   Count a few and quit: `tally.cast` has the session, which plays back in
   this terminal, twice as fast:

   ```bash
   dart run twk_dev:twk play --speed=2 tally.cast
   ```

   and in a test twk_test's `screenFrames` over its `writes` gives the screens
   it showed, the last one the app's last.
