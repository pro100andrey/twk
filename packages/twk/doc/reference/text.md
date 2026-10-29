# twk reference: `text`

[The reference](README.md) · `lib/src/text/`, `test/text/`

## `Text`

`Text` (a string) and `Text.rich` (`Span`s), in their `style` merged onto
that of the `DefaultTextStyle` above (each span's merged onto that), broken
into lines, cut off and aligned by the core's `RenderParagraph` (`TextWrap`,
`TextOverflow`, `maxLines`, `TextAlign`, whose `start` and `end` are the
left and the right edge, or in visual order those a line's paragraph starts
and ends at);

## `DefaultTextStyle`

`DefaultTextStyle`, merged onto the one above it. A rebuild with the same
text and styles does no work; new styles only repaint. Right-to-left text is
drawn in the order the terminal needs, `AppBinding.textOrder` (a
`TextOrder`; the core's,
[§1.7](../../../twk_core/doc/design/terminal.md) and
[§1.8](../../../twk_core/doc/design/render.md)): in visual
order, each line in the order UAX #9 gives it, its brackets mirrored, where
the app orders it, on a terminal that does no bidi or is not known, inside
tmux, on a `HeadlessTerminal` by default, and on one that honours BDSM (VTE,
WezTerm, iTerm2 3.7.5+, mintty), which is put in its explicit mode while the
app runs; as stored (logical order) where the terminal reorders it itself
and can't be told not to (Konsole, mlterm, Terminal.app, PuTTY) and on plain
output. `runApp(bidi: BidiReordering.app)` (or `.terminal`) chooses instead,
for the terminal it opens (the core's `TerminalOptions.bidi`); a terminal
given has to be ordered so. Below a `SelectionArea` (`gestures`) a `Text`
can be selected with the mouse, what is selected drawn in the area's style
merged onto its own. `onLinkTap(url)`, on either, is told the link of the
text clicked on (a span whose style links it, `Style.link`: the left button
pressed and released on the same cell; beside the text, on text that links
nowhere or with another button, nothing); the text is still written as a
hyperlink, which a terminal that knows them may open itself as well, and
while it is set the terminal reports the mouse's buttons
