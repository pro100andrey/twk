---
title: "twk documentation"
about: "Guides, the widget catalog and the API of twk, Flutter-like widgets for terminal UIs in Dart."
---
# twk documentation

twk is Flutter's widget model for terminal UIs in Dart, on
[twk_core](https://pub.dev/packages/twk_core), a rendering core that
writes only the cells that changed.

![The twk gallery's Table page](../packages/gallery/doc/shots/screens/table-dark.svg)

## Guides

1. [Getting started](guides/getting-started.md): install, a first app,
   running it full screen or inline, debugging it.
2. [Layout](guides/layout.md): rows, columns, boxes and the room each
   child gets, in cells.
3. [Input and focus](guides/input-and-focus.md): keys, the focus Tab
   moves, the keys hinted where it is, the mouse.
4. [Theming](guides/theming.md): colors and styles from a theme, dark or
   light as the terminal is.
5. [Screen modes](guides/screen-modes.md): full screen, inline below the
   prompt, or a fixed rectangle of the screen.
6. [State](guides/state.md): `setState`, controllers, hooks and Provider.
7. [Testing](guides/testing.md): an app tested on a terminal in memory
   with twk_test.

## Widget catalog

[Every widget](widgets/README.md), by group: its pictures dark and light,
the Dart that builds it, its options in the gallery and its API.

## API

- [twk](https://pub.dev/documentation/twk/latest/): the widgets.
- [twk_core](https://pub.dev/documentation/twk_core/latest/): the
  rendering core, for render objects of your own or a terminal without
  widgets.
- [twk_test](https://pub.dev/documentation/twk_test/latest/): the tester.

## In depth

- [twk's reference](../packages/twk/doc/reference.md): every topic,
  widget and parameter, and how the package is tested.
- [twk_core's design](../packages/twk_core/doc/design.md): the cells, the
  presenter, Unicode, input, the screen modes, and the core's limits.
- [The gallery](../packages/gallery/README.md): every widget live,
  `dart run packages/gallery/bin/gallery.dart` in a checkout.
