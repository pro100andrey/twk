# twk: reference

The widget layer for terminal UIs in Dart, on top of
[twk_core](../../../twk_core/README.md), the rendering core in
`packages/twk_core` of this repository (and `package:meta` for the
framework's annotations): every topic, widget and parameter, how the
package is tested, and its demos. The package's
[README](../../README.md) is the short introduction.

`lib/twk.dart` exports one library per topic, `lib/src/<topic>/<topic>.dart`,
each with a doc comment naming what it is for. Widgets lay out and paint
through the core's render tree
([§1.8](../../../twk_core/doc/design/render.md) of its design); a topic's
tests are in `test/<topic>/`. Those that check what reaches a terminal
feed it to the emulator of [twk_test](../../../twk_test/README.md), a dev
dependency by path: `package:twk_test/vt.dart`, and `VtTerminal`
(`package:twk_test/vt_terminal.dart`) for an app in the inline mode. Those
of every topic but the framework, foundation, style and text, and those of
the demos (`test/example/`), run apps with its `testTwk`: keys and mouse
reports go in as the bytes a terminal sends, through the core's parser,
under a fake clock, and the screen is read back through the emulator.

An app imports `package:twk/twk.dart` and no library of twk_core: besides
the topics, that library exports the declarations of twk_core that the API
here takes and returns, those a render object of an app's own is written
with, and a terminal in memory for tests. The render objects the widgets
create and the parent data they put on them, the frame loop and the
terminal's machinery stay in `package:twk_core`; the library comment of
`lib/twk.dart` gives the rule. `log` is also a function of `dart:math`
and `dart:developer`: an app that imports either prefixes it.

Two libraries of the package are not in `lib/twk.dart`, so that an app
that uses neither carries neither: `package:twk/hooks.dart`, hooks in the
flutter_hooks style ([its page](hooks.md)), and
`package:twk/provider.dart`, Provider's API
([its page](provider.md)), on which
[twk_bloc](../../../twk_bloc/README.md) builds. An app that uses one imports it
besides `package:twk/twk.dart`; each builds on twk's public API alone,
its sources in `lib/src/hooks/` and `lib/src/provider/`, its tests in
`test/hooks/` and `test/provider/`, its example in `example/hooks/` and
`example/provider/`.

The package builds for the web with dart2wasm, where
[twk_web](../../../twk_web/README.md) runs an app on xterm.js: what it takes
from dart:io goes through `lib/src/platform/`, as the core's does
([§1.7](../../../twk_core/doc/design/terminal.md)), and there the
environment is empty, so `TWK_DEBUG` and `TWK_SCREEN_READER` turn
nothing on, a `FilePicker` lists nothing (`cannot list: no file system
on the web`) and finds no path, a `DirectoryTree` shows `(no file
system on the web)` below its root, the console's `save` fails with an
`UnsupportedError`, and a `WidgetError` shows no source.
`test/platform/web_check_test.dart` builds an app with `runApp` there and
runs it in node (`tool/web_check.dart twk`).

[SKILL.md](../../SKILL.md) is a skill for coding agents that build apps with
twk: the mental model, setting an app up, the widgets by need, recipes,
tests with twk_test, debugging and the pitfalls.
`test/skill_test.dart` writes its code blocks into a package of their
own, which must analyze, format and pass its tests as written, checks
that every name its prose gives is exported, and that its pitfalls are
what twk does.

## Topics

A page a topic, a section a widget or a class:

- [`framework`](framework.md): `Widget`, `InheritedWidget`, `ParentDataWidget`, `ProxyWidget`, `Notification`, `BuildContext`, `Builder`, `LayoutBuilder`, …
- [`foundation`](foundation.md): `Listenable`, `ListenableBuilder`, `FutureBuilder`, `ControllerHost`
- [`style`](style.md): `Style`, `ThemeData`, `ThemeData.lerp`, `Theme`, `Theme.of`, `TerminalBrightness`, `Gradient`, `GradientBackground`, …
- [`text`](text.md): `Text`, `DefaultTextStyle`
- [`ansi`](ansi.md): `parseAnsi`, `AnsiStream`, `stripAnsi`
- [`layout`](layout.md): `Padding`, `FractionallySizedBox`, `IntrinsicWidth`, `IntrinsicHeight`, `Box`, `Flex`, `Flexible`, `Stack`, …
- [`data`](data.md): `DotCanvas`, `Gauge`, `BarChart`, `Chart`, `Calendar`, `RenderCalendar.dateAt`, `Sparkline`, `Table<T>`, …
- [`binding`](binding.md): `InputListener`, `ErrorWidget`, `WidgetError`, `Static<T>`, `AppBinding.debug`, `TerminalProgress`, `WindowTitle`, `TerminalStatus.of`
- [`animation`](animation.md): `Ticker`, `TickerProviderStateMixin`, `AnimationController`, `Animatable<T>`, `Spinner`, `ProgressBar`, `EdgeInsetsTween`, `StyleTween`, …
- [`focus`](focus.md): `Focus`, `Focus.of`, `FocusScope.of`, `FocusBuilder`, `ExcludeFocus`, `KeyBindings`, `FocusManager.activeKeys`, `ActiveKey.label`, …
- [`gestures`](gestures.md): `Listener`, `MouseRegion`, `IgnorePointer`, `AbsorbPointer`, `GestureDetector`, `SelectionArea`, `Draggable<T>`, `DragTarget<T>`
- [`scroll`](scroll.md): `Scrollable`, `Scrollable.of`, `Scrollable.ensureVisible`, `SingleChildScrollView`, `ListView`, `ListView.separated`, `Scrollbar`, `ScrollbarVisibility.always`, …
- [`editing`](editing.md): `TextField`, `TextEditingController`, `TextBoundaries`, `TextArea`, `Autocomplete`
- [`overlay`](overlay.md): `Overlay`, `Overlay.of`, `OverlayState.insert`, `ModalBarrier`, `AnimatedModalBarrier`, `Dialog`, `Panel`, `OptionList`, …
- [`navigation`](navigation.md): `Navigator`, `Navigator.of`, `PopScope<T>`, `Scaffold`, `Breadcrumbs`, `Pagination`, `Stepper`, `Axis.vertical`
- [`controls`](controls.md): `TabController`, `KeyHintsBar`, `StatusMessage`, `Badge`, `Link`, `StatusBar`, `ListTile`, `Button.outlined`, …
- [`debug`](debug.md): `Console`
- [`semantics`](semantics.md): `Semantics`, `BlockSemantics`, `ExcludeSemantics`, `SemanticsNode.of`, `AppBinding.screenReader`

[How the package is tested, and its demos](testing.md); [hooks](hooks.md),
`package:twk/hooks.dart`; [Provider](provider.md), `package:twk/provider.dart`.

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](../../LICENSE). The colors of
`ThemeData.nord` are those of Nord (https://www.nordtheme.com), Copyright
(c) 2016-present Sven Greb, and those of `ThemeData.catppuccinMocha` and
`ThemeData.catppuccinLatte` those of the Catppuccin palette
(https://catppuccin.com), Copyright (c) 2021 Catppuccin, each under the
MIT License in the same words as this package's. twk_core, which twk
takes, carries Unicode data under the Unicode License v3: its
[NOTICE](../../../twk_core/NOTICE).
