# twk reference: `ansi`

[The reference](README.md) · `lib/src/ansi/`, `test/ansi/`

Text carrying ANSI escape sequences, such as the output of a command, read
into styled spans, or into the text without them.

`parseAnsi(text)`, the output of a program with ANSI escape sequences as lines of `Span`s, and `AnsiStream`, such output arriving in pieces (`add` for text, `addBytes` for UTF-8, `close`), which may end anywhere, within a sequence or a character; its `lines` are those ended, which `settled` counts and which stay the very objects they were, then the one being written. The lines are those a terminal would show: SGR sets the style (16, 256 and 24-bit colors in the `;` and the `:` form, underline colors and kinds, every attribute and its reset, a reset leaving the field unset), an OSC 8 hyperlink is a `Style.link`, a carriage return or a backspace moves back over the line for later text to replace (a progress line ends as its last state), EL (`CSI K`) erases in it, a tab moves to the next multiple of `tabWidth` (8) columns, and wide characters and combining marks take the columns the core's segmenter gives them. Every other sequence (cursor moves, erasing the screen, modes, titles, the clipboard, DCS, APC, PM, SOS strings) and every other C0 and C1 control is dropped whole, so nothing in the spans can act on the terminal they are drawn on; a CSI with over 64 parameter bytes and an OSC over 8192 code units are dropped too. `stripAnsi(text)` gives the text without the sequences `AnsiStream` reads (CSI, OSC, DCS, APC, PM, SOS and the other escapes; one not ended takes the rest of the text with it) and without the C1 controls, every other character kept as it is: tabs, line breaks, carriage returns, backspaces and the other C0 controls, also where they interrupt a sequence, and wide characters; unlike joining the spans `parseAnsi` gives, which expands tabs and applies carriage returns and backspaces

`test/ansi/` checks each SGR form and OSC 8 link (`sgr_test.dart`); how
line endings, carriage returns, backspaces, tabs, erasing and wide
characters write the lines (`lines_test.dart`); that every other
sequence and control leaves nothing, random bytes included, and that
`stripAnsi` takes out the same sequences, keeps tabs, line breaks,
carriage returns, backspaces, wide characters and the controls within a
sequence, and of random text only takes characters out, leaving no ESC
or C1 control (`strip_test.dart`); that output cut anywhere, as text or
as UTF-8, parses as it does whole, its ended lines the same objects
(`stream_test.dart`); and the output of real tools captured in
`test/ansi/fixtures` (git log and show, dart test expanded and compact,
gcc with links to its docs) against the same output without colors,
parsed and through `stripAnsi` (`fixtures_test.dart`).
