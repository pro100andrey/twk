---
title: "Coming from Flutter"
about: "What is the same as Flutter, what is spelled differently, and what twk does not have."
order: 10
---
# Coming from Flutter

twk keeps Flutter's widget model: `StatelessWidget`, `StatefulWidget`,
`State`, `setState`, `BuildContext`, `InheritedWidget`, keys, constraints
going down and sizes going up, `Navigator`, `Overlay`, `Focus`. What you
know of how a tree builds, rebuilds and lays out holds. What does not hold
is the unit and the catalog: the screen is a grid of character cells, and
there is no Material.

If you write twk from Flutter's names, these are the mistakes that come
first.

## Cells, not pixels

Every size, offset, padding and gap is a whole number of cells: an `int`,
not a `double`. A cell is one column wide and one row tall, and it is about
twice as tall as it is wide, so `SizedBox(width: 20, height: 10)` looks
about square. There are no fractions of a cell, no device pixel ratio and no
rounded corners other than the border characters of a `Box`.

<!-- file: packages/twk/example/guides/flutter_cells.dart -->
```dart
import 'package:twk/twk.dart';

const sized = SizedBox(width: 20, height: 3);
const insets = EdgeInsets.only(left: 2, right: 2);
const loose = BoxConstraints(maxWidth: 40);
```

- `BoxConstraints` has `minWidth`, `maxWidth`, `minHeight` and
  `maxHeight`, as in Flutter, in cells. `BoxConstraints.tight(w, h)` and
  `loose(w, h)` take the two sizes, not a `Size`, and `tightFor` and `expand`
  are there; so are `copyWith`, `loosen`, `enforce`, `tighten`, `deflate`, the
  `hasBounded`, `hasTight` and `hasInfinite` getters, and `biggest` and
  `smallest`, which are `({int width, int height})` records.
- `EdgeInsets` has `all`, `only`, `symmetric`, `fromLTRB`, and `x` (left and
  right) and `y` (top and bottom), which are shorter than
  `symmetric(horizontal:)` and `symmetric(vertical:)`.
- A `double` is still a `double` where it is a proportion: `Slider`'s
  value, `Opacity.opacity`, `ProgressBar.value`.
- The screen's size is not in a `MediaQuery`: there is none. A widget
  reads the room it was given, in cells, from a `LayoutBuilder`'s
  constraints.

## Spacing is a parameter, as in Flutter

`Row`, `Column`, `Flex` and `Wrap` take `spacing` (and `Wrap` a
`runSpacing`), as in Flutter, so the `SizedBox(height: 8)` between children
is not written; here it is an `int` of cells. `StatusBar` and
`DescriptionList` name the space between their parts `spacing` too. `Spacer` and
`Expanded(flex: ...)` are as in Flutter.

## Text is a string with a `Style`

There is no `TextStyle`, `TextSpan`, `RichText`, `Colors` or `Icon`.

- `Text('hi', style: ...)` takes a `Style`: `fg` and `bg` colors and
  attributes (`Attr.bold`, `Attr.dim`, `Attr.italic`, underlines, `Attr.reverse`,
  `Attr.strike`). A `Style` has no font, size or weight: the terminal draws
  one font.
- A `Color` is one of the terminal's sixteen (`Color.red`, `Color.blue`),
  an indexed one or a `Color.rgb(r, g, b)`. There is no `Colors.red[500]`
  and no opacity on a color other than the alphas of a `Style`.
- Styled runs are `Span`s: `'error: '.bold.fg(.red)` is a `Span`, and
  `Text.rich` takes a list of them where Flutter's takes a `TextSpan` tree.
- `DefaultTextStyle(style:, child:)` merges `style` onto the one above, field
  by field, where Flutter's plain constructor replaces it: a field the style
  leaves unset keeps the value from above. `DefaultTextStyle.merge` is there
  and does the same, so code brought over from Flutter that used `.merge`
  runs as it did. To start from nothing, set every field, or put the style on
  the `Text`.
- `style.copyWith(fg: Color.red)` changes a field of a `Style`; a field passed
  as null stays, as it does in Flutter's `TextStyle.copyWith`.
- An icon is a character, `Text('✉')`, or the glyphs of the theme.
- `Text` wraps at words by default and clips (`TextOverflow.clip`);
  `Text.line` is one row with an ellipsis. A width is counted in cells, so
  a wide character (CJK, most emoji) is two.

<!-- file: packages/twk/example/guides/flutter_text.dart -->
```dart
import 'package:twk/twk.dart';

const warn = Style(fg: Color.yellow, attrs: Attr.bold);
final rich = Text.rich(['error: '.bold.fg(.red), 'disk full'.dim]);
```

The colors an app draws with come from a `Theme`: `Theme.of(context)`
gives `text`, `muted`, `primary`, `border`, `error` and the other `Style`s
of [Theming](theming.md), which follow the terminal's own colors by
default. Writing a `Style` with a fixed color is the exception, not the
way a Flutter app writes `Theme.of(context).colorScheme`.

## No Material, and what is there

twk has no `MaterialApp`, `AppBar`, `Card`, `FloatingActionButton`,
`Drawer`, `SnackBar`, `Hero`, `InkWell`, `Dismissible`, `GridView`,
`PageView`, `Image.network`, `AnimatedContainer`, `SafeArea`,
`ClipRRect`, `AspectRatio`, `FittedBox`, `IndexedStack`,
`ReorderableListView`, `RefreshIndicator`, `ScaffoldMessenger`,
`FocusTraversalGroup` or `showModalBottomSheet`. Each has a counterpart or
none:

| Flutter | twk |
| --- | --- |
| `runApp(MaterialApp(...))` | `runApp(const App(child: ...))`; `App` gives a theme and an overlay, `runApp` alone gives neither |
| `Scaffold(appBar, body, drawer)` | `Scaffold(header:, body:, sidebar:, statusBar:)` |
| `Container(decoration: BoxDecoration(border: ...))` | `Box(border:, titles:, padding:, style:)`; `Container` exists too, with `color`, `decoration`, `margin` |
| `Card`, `Material` | `Panel` |
| `ElevatedButton`, `TextButton`, `OutlinedButton` | `Button`, `Button.filled`, `Button.outlined` (a label and `onPressed`, no `child`) |
| `IconButton`, `InkWell` | `Pressable`, `GestureDetector` |
| `Checkbox`, `Switch`, `Slider` | the same names; `Checkbox` and `Switch` take a `label`, and a null `onChanged` disables them |
| `Radio`, `RadioListTile` | `RadioGroup<T>` |
| `DropdownButton` | `Select<T>` |
| `TextField(decoration: InputDecoration(...))` | `TextField`, with `placeholder` and an `InputDecoration` whose parts are `labelText`, `helperText`, `errorText`, `prefixIcon` |
| `Form`, `TextFormField` | the same names |
| `AlertDialog`, `showDialog` | `Dialog`, `showDialog<T>(context: context, builder: builder)`, as Flutter's |
| `SnackBar` | `showToast(context: context, message: message)`, with `alignment:` and `duration:` |
| `Tooltip` | `Tooltip(message:, child:)` |
| `CircularProgressIndicator`, `LinearProgressIndicator` | `Spinner`, `ProgressBar` (`value: null` is indeterminate) |
| `TabBar`, `TabBarView`, `TabController` | `TabBar`, `TabBarView`, `TabController` |
| `DataTable` | `Table<T>` (rows and columns, selection, sorting) |
| `GridView` | `Grid` with column and row tracks |
| `SelectableText` | `SelectionArea` |
| `WillPopScope` | `PopScope` |
| `Image` | `Image` in `twk_rich`, in the terminal's graphics or block characters |

The [widget catalog](../widgets/README.md) lists what twk has that Flutter
does not: `Sparkline`, `Chart`, `Gauge`, `Calendar`, `TreeView`,
`SplitPane`, `CommandPalette`, `Stepper`, `Breadcrumbs`, `Console`,
markdown and diff views and a terminal in a widget.

## The keyboard is first

A terminal has a keyboard before it has a mouse, and a widget that can be
acted on is reached with Tab. A `Button` does nothing until it has the
focus (Tab, or the mouse) and Enter or Space is pressed; a `TextField`
takes characters only when focused, so a single-letter binding such as `q`
above a focused field is typed into the field.

- Keys are named by strings: `KeyBindings({'ctrl+s': save, 'g g': top},
  child: ...)`. `Shortcuts(shortcuts:, child:)`, `Actions(actions:, child:)` and
  `Intent` are Flutter's and are there as well, and an `Action.invoke` returns
  an `Object?`; the string form is how an app usually binds. See
  [Input and focus](input-and-focus.md).
- The mouse is a plain `GestureDetector`, `MouseRegion`, `Draggable` and
  `Listener`, with Flutter's callbacks: `onTap`, `onDoubleTap` and
  `onLongPress` take none, `onTapDown` and `onTapUp` take `TapDownDetails` and
  `TapUpDetails`, `onPanStart`, `onPanUpdate` and `onPanEnd` take
  `DragStartDetails`, `DragUpdateDetails` and `DragEndDetails`, and a
  `Listener` has `onPointerDown`, `onPointerUp`, `onPointerHover` and
  `onPointerMove`. The details have `localPosition` and `globalPosition` in
  cells, and `delta` for an update, and also an `event`, which has the button
  and the modifiers; they have no `kind`, `sourceTimeStamp` or `velocity`,
  which a terminal does not report. Not every terminal reports the mouse, so
  an action reachable only by the mouse is a bug here.
- `hints:` on `KeyBindings` lists the keys on the bar at the bottom, which
  the widgets fill in too.

## A screen, ported

A Flutter form, as it is written here:

<!-- file: packages/twk/example/guides/flutter_form.dart -->
```dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const App(child: Profile()));

final class Profile extends StatefulWidget {
  const Profile({super.key});

  @override
  State<Profile> createState() => _ProfileState();
}

final class _ProfileState extends State<Profile> {
  final _name = TextEditingController();
  var _news = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const .all(1),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 1,
        children: [
          Text('Profile', style: theme.primary),
          SizedBox(
            width: 30,
            child: TextField(controller: _name, semanticsLabel: 'Name'),
          ),
          Checkbox(
            value: _news,
            label: 'Send me the news',
            onChanged: (value) => setState(() => _news = value),
          ),
          Row(
            spacing: 2,
            children: [
              Button.filled(
                'Save',
                onPressed: () => showToast(context: context, message: 'saved'),
              ),
              Button.outlined(
                'Delete',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => const Dialog(
                    title: 'Delete?',
                    child: Text('This cannot be undone.'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

What changed from the Flutter version: the sizes and the `spacing:` are ints of cells, the label belongs to the
`Checkbox`, and the buttons take a string. `showDialog(context:, builder:)`,
the `State`, its controller and its `dispose` are the same, and so is a
controller you must dispose.

Dart's dot shorthands (`.all(1)`, `.start`, `.stretch`) are used
throughout, as in the other guides; `EdgeInsets.all(1)` and
`CrossAxisAlignment.start` mean the same and compile as well.

## Spelled another way, on purpose

A few names are not Flutter's, and are meant not to be:

- A `Style` has `fg` and `bg`, not `color` and `backgroundColor`; there is no
  `TextStyle`.
- The theme presets are values, `ThemeData.dark`, `ThemeData.light` and
  `ThemeData.nord`, to take `copyWith` of, where Flutter calls
  `ThemeData.dark()`.
- There is no `Size` and no `Offset`: a size is a width and a height, and a
  position in a gesture's details is a `(dx:, dy:)` record of cells, a
  `CellOffset`.
- `Scaffold` has a `header` and a `statusBar` where Flutter's has an `appBar`
  and a `bottomNavigationBar`, and `Select` has `choices` where a
  `DropdownButton` has `items`.
- `Semantics` takes `checked`, `selected`, `expanded` and `enabled` flat, with
  Flutter's sense (`enabled: false` reads `disabled`), and `role` and `nodes`
  besides; its `child` is optional, as in Flutter.
- `TweenAnimationBuilder(tween:, builder:, duration:)` takes a `Tween` as
  Flutter's does. A `Tween` here is immutable, so one of your own overrides
  `withEnds` to make another of its kind.
- `Localizations` is Flutter's, for a `Locale`; the words twk writes itself are
  in `TwkLocalizations`.

## Lists and navigation

`ListView` takes `children`; `ListView.builder` takes `itemCount` and
`itemBuilder`, and builds only the rows in view. A `ListView` is focusable
and scrolls with the arrow keys, Page keys and the wheel, and a `ListTile`'s
`onTap` runs on Enter, Space or a click.

`Navigator` takes `home` and a `routes` map, and `Navigator.push`,
`pushNamed`, `pop`, `popUntil`, `pushAndRemoveUntil`, `pushNamedAndRemoveUntil` and `popAndPushNamed` are static as in Flutter. A route is a
`PageRoute(builder:)`, not a `MaterialPageRoute`. Escape pops by default
(`backKey`), as a back button does.

<!-- file: packages/twk/example/guides/flutter_list.dart -->
```dart
import 'package:twk/twk.dart';

final class Items extends StatelessWidget {
  const Items({super.key});

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: 100,
    itemBuilder: (context, i) => ListTile(
      title: Text('Item $i'),
      onTap: () => Navigator.push<void>(
        context,
        PageRoute(builder: (context) => Text('Item $i')),
      ),
    ),
  );
}
```

Scrolling has `ScrollPhysics` for its bounds and, as in Flutter,
`ScrollConfiguration` and a `ScrollBehavior` for its input: what the wheel
and a trackpad do, for the app (`App(scrollBehavior:)`) or a subtree.

## State

`ChangeNotifier`, `ValueNotifier`, `ListenableBuilder`,
`ValueListenableBuilder`, `FutureBuilder`, `StreamBuilder` and
`AnimationController` with `TickerProviderStateMixin` or
`SingleTickerProviderStateMixin` are as in Flutter. `forward`, `reverse`,
`animateTo`, `repeat` and `toggle` return a `Future<void>` that completes when
the run ends, and also when something stops it (`stop`, a new run, `dispose`),
where Flutter's `TickerFuture` then stays pending for ever and has `orCancel`
to tell: an `await controller.forward()` here does not hang on a stop, and
`controller.status` and `value` say how it ended.
`package:twk/provider.dart` is Provider's API (`ChangeNotifierProvider`,
`Consumer`, `Selector`, `MultiProvider`), and `package:twk/hooks.dart` is
flutter_hooks'. Riverpod and bloc are the packages `twk_riverpod` and
`twk_bloc`. [State](state.md) has them.

<!-- file: packages/twk/example/guides/flutter_state.dart -->
```dart
import 'package:twk/twk.dart';

final counter = ValueNotifier<int>(0);
final built = ValueListenableBuilder<int>(
  valueListenable: counter,
  builder: (context, n, _) => Text('$n'),
);
```

There is no `AnimatedContainer`; `AnimatedBox`,
`AnimatedPadding`, `AnimatedAlign`, `AnimatedPositioned`, `AnimatedOpacity`,
`AnimatedSize`, `AnimatedSwitcher`, `AnimatedTheme` and
`TweenAnimationBuilder` are there. Animation is cell by cell: a size
animates in whole steps, at most 60 frames a second by default (`maxFps`);
frames that input asks for come up to 120 (`maxInputFps`).

## Runs differently

- `runApp(app, mode:)` runs full screen on the alternate screen or inline
  below the prompt ([Screen modes](screen-modes.md)). Nothing is a window.
- `print` goes to the app's log, not the screen ([Getting
  started](getting-started.md)). Hot reload and the inspector are the
  `twk` command, not `flutter run`.
- Tests are `package:twk_test`, with a tester (`pumpWidget`, `pump`),
  finders and a terminal in memory, whose screen a test reads as text:
  no golden pictures of pixels ([Testing](testing.md)).
- `package:twk/twk.dart` imports every widget, and some names are words an
  app defines too (`Table`, `Step`, `Chip`, `Window`, `Gauge`): hide them
  or import your own with a prefix.

## Where to go next

- [Layout](layout.md) for `Box`, `Grid`, `Stack` and the constraints in
  cells.
- [Input and focus](input-and-focus.md) for keys, focus and the mouse.
- [Theming](theming.md) for `Theme` and the `Style`s it gives.
- [State](state.md) and [Testing](testing.md).
- [The widget catalog](../widgets/README.md).
