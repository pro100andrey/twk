# `twk decode`

```bash
dart run twk_dev:twk decode session.cast
TWK_TRACE_OUTPUT=out.trace TWK_TRACE_INPUT=in.trace dart run bin/app.dart
dart run twk_dev:twk decode out.trace in.trace --frames --grep=DECSET
```

`twk decode` reads what a terminal and an app said to each other and names it,
as the sequence log of the VS Code extension does: each text run, control
character and escape sequence (CSI, OSC, DCS, APC, PM, SOS, ESC and SS3) the
app wrote, and each key, mouse event and answer to a query the terminal sent.
It reads:

- a recording, `twk record`'s or a tape's `.cast` (the `o` events are what the
  app wrote, the `i` events what was typed, resizes and markers are notes);
- the byte traces a `Terminal` writes where `TWK_TRACE_OUTPUT` and
  `TWK_TRACE_INPUT` name a file (the format is in
  `packages/twk_core/lib/src/terminal/trace.dart`), nothing else reads today.
  The two files of one run share a clock, so `twk decode out.trace in.trace`
  merges them by time and an answer is read after the query it answers.

A row is the time in seconds, the direction (`out` the app's, `in` the
terminal's, `--` a note of the session), the name, and the bytes as the
sequence log shows them (`ESC` for the escape character, `^M` for a control
character, bytes above 0x7E in hex):

```text
    0.000  --  recording 100x30
    0.012  out CUP cursor to row 3, column 5                         ESC [3;5H
    0.040  in  key Ctrl+Up                                           ESC [1;5A
```

A synchronized update (`CSI ? 2026 h` to `CSI ? 2026 l`) is a frame: a row
`frame 3: 12 CUP, 9 text, ..., 4 ms` with the bytes it holds, and its own rows
indented below it. `--frames` keeps the frame rows only. A frame still open
where the traffic ends (a truncated trace, a crash before `?2026l`) is a row
ending `not closed`, and a string or sequence the app's last write left
unfinished is a note `output cut short: ...`; a `?2026l` with no update open is
ignored, with a note.

Every row is shown, however many, and every name and byte string is printed
escaped (`^[` for ESC, `\x9b` for a C1 control), so a title or notification a
file holds never acts on the terminal it is shown in.

`CSI 1 ; n R` is the F3 key with modifiers n, or the cursor-position answer
for row 1: it is the answer when the app's output asked `CSI 6 n` and it has
not been answered, else the key; with no output to tell by, the name gives
both.

| Option | Meaning |
| --- | --- |
| `--frames` | A synchronized update as one row, not opened. |
| `--only=output` or `--only=input` | Only what the app wrote, or only what the terminal sent (notes are left out). |
| `--grep=<regexp>` | Only rows whose name or bytes match; a frame is kept when it or any of its rows does, and opened it shows the rows that match (all of them when the frame's own row does). |

It ends with 0; 1 when a file cannot be read or is neither a recording nor a
trace; 64 for a wrong command line (no file, a `--grep` that is no regular
expression).

## One specification for two decoders

The names exist twice, in Dart (`lib/src/decode.dart`) and in TypeScript
(`editors/vscode/src/core/sequences.ts` and `seqlog.ts`), as the extension runs
without Dart. Both are held to `test/decode.golden.json`: bytes (as chunks, the
way reads cut them) with the tokens and names they must give, for the app's
output and for the terminal's input, and sequences of timed events with the
entries and frames of the log they must make. `decode_golden_test.dart` checks
the Dart side and the extension's `sequences_golden.test.ts` the other; a
change to a name is made in the golden, and fails both until both follow.
