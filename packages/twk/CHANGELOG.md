# Changelog

## Unreleased

- `FocusNode.takesText` (and `Focus(takesText:)`) says that a node takes the
  keys that are characters as text: `TextField` and `TextArea` say it unless
  read-only. `FocusManagerKeys.activeKeys`, so a `KeyHintsBar` and
  `showKeyHelp`, no longer list a binding of a layer above such a node on a
  character key (`q`), which the field takes, and a click on a hint cannot
  type it into the field; keys with Ctrl or Alt stay.
- `KeyBindings(unmatched: UnmatchedKeys.replay)` replays the held first keys
  to the nodes a key walks, past what a dialog's `keysSkip` skips, where it
  gave them to the app's bindings between the navigator and the dialog.
- A cell's style id is a `StyleId` (package:twk_core, exported by
  package:twk), apart from a pen id, which stays an int: the effect cell's
  `EffectCell.style`, `childStyle` and `underStyle` are one, and so are
  the style arguments of a `RenderEffect`'s `effectCell`.
- `Scrollbar` and the bar of `Box` read the axis from the scrollable
  inside, as Flutter's `Scrollbar` does. `Scrollbar(axis:)` is nullable and
  null by default: the outermost scrollable of either axis, where it was
  vertical by default. So `Scrollbar()` around content whose outermost
  scrollable is horizontal now shows that one, in a row at the bottom; to
  keep the column around content that scrolls both ways, give
  `axis: Axis.vertical`. A given axis picks that axis's scrollable, the
  bar to each axis of content that scrolls both. An inner scrollable of the
  other axis never takes the bar of an outer one.
- `Box(scrollbar:)` takes a `ScrollbarVisibility?`, as `LogView` does,
  where it took an `Axis?`: `.always`, `.onScroll` (the border's own line
  shows while the thumb is hidden) or `.never`; null for none. The bar is on
  the right side for a vertical scrollable and on the bottom for a
  horizontal one; the border must have that side and a bottom title cannot
  share it with a horizontal bar, as asserted.

## 0.1.0

The first release.

- The framework: `Widget`, `StatelessWidget`, `StatefulWidget` and
  `State`, `InheritedWidget`, keys and `GlobalKey`, `LayoutBuilder`,
  `BuildContext`; `ChangeNotifier`, `ValueNotifier` and `Listenable`.
- `runApp`: fullscreen, inline below the shell's history (`Static`
  commits finished lines into the scrollback) or in a fixed viewport;
  `AppBinding` with frame callbacks, notifications, the window title and
  hot reload through `twk run`.
- Style and text: `Style` with colors, attributes, underline colors and
  links; `Text` and `Text.rich`, wrapping, ellipsis and bidirectional
  text; `Theme` with built-in dark and light themes, the default ones
  picked by the terminal's background, `Theme.adaptive` to choose them
  and `Theme.terminal` for the terminal's own colors.
- Layout: `Row`, `Column`, `Flex`, `Stack`, `Grid`, `Wrap`, `Box` with
  borders that merge, `Padding`, `Align`, `SizedBox`, `SplitView`.
- Focus and input: the focus tree, `Focus`, `KeyBindings`, `Shortcuts`
  and hinted keys; the mouse by hit test (`Listener`, `MouseRegion`).
- Scrolling and data: `ListView`, `Scrollbar`, `Table` (also over a data
  source), `TreeView`, `DirectoryTree`, charts, sparklines and gauges.
- Editing: `TextField`, `TextArea`, `Form` and `FormField`.
- Overlays: dialogs, menus, `MenuBar`, `ContextMenu`, toasts, tooltips,
  `CommandPalette`.
- Navigation and controls: `Navigator` and routes, tabs, buttons,
  switches, checkboxes, radio groups, sliders, `Stepper`, progress bars
  and spinners.
- Animation: tickers, `AnimationController`, implicit animations.
- Semantics and a screen-reader mode; debug aids: the frame overlay, the
  repaint rainbow, the log console, tree dumps and VM service extensions.
- Program output with ANSI sequences as styled text: `parseAnsi`,
  `AnsiStream` as it arrives, and `stripAnsi`.
- `package:twk/hooks.dart`, hooks in the flutter_hooks style, and
  `package:twk/provider.dart`, Provider's API.
- `package:twk/cli.dart`, the console of a command-line tool that is no
  app: messages by level, any widget printed, prompts, progress and a
  traceback, as a terminal, a pipe or CI takes them.
- A dart2wasm build for the web.
