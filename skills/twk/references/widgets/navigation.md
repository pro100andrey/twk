<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Navigation

Routes, a scaffold of panes, steppers, breadcrumbs and pages.

[All widgets](../widgets.md)

## Navigator

Screens on a stack: a route pushed covers the one under it and takes the focus, Escape or Back pops it.

API: [`Navigator`](https://pub.dev/documentation/twk/latest/twk/Navigator-class.html).

### Code

```dart
@override
Widget build(BuildContext context) => SizedBox(
  width: 44,
  height: 9,
  child: Box(
    border: .all(type: .rounded, style: Theme.of(context).border),
    padding: const .x(1),
    child: Navigator(
      home: const _Home(),
      onGenerateRoute: (settings) => settings.name == '/settings'
          ? _Slide.route((_) => const _Settings(), settings)
          : null,
    ),
  ),
);

/// The routes of the screens: each slides in from the right over the one
/// under it, which dims, and out again as it is popped.
abstract final class _Slide {
  static PageRoute<void> route(
    WidgetBuilder builder, [
    RouteSettings settings = const RouteSettings(),
  ]) => PageRoute(
    builder: builder,
    settings: settings,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
  );
}

/// The first route: buttons that push the others.
final class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      const Text('Home'),
      Button(
        'Open item 7',
        onPressed: () =>
            Navigator.push(context, _Slide.route((_) => const _Item(7))),
      ),
      Button(
        'Open /settings',
        onPressed: () => Navigator.pushNamed<void>(context, '/settings'),
      ),
    ],
  );
}

/// Item [n], with a button that pops it and one that pushes the next.
final class _Item extends StatelessWidget {
  const _Item(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Text('Item $n', style: Theme.of(context).primary),
      Row(
        spacing: 2,
        children: [
          Button(
            'Back',
            autofocus: true,
            onPressed: () => Navigator.pop(context),
          ),
          Button(
            'Open item ${n + 1}',
            onPressed: () =>
                Navigator.push(context, _Slide.route((_) => _Item(n + 1))),
          ),
        ],
      ),
    ],
  );
}

/// The route named /settings, with a button that pops it.
final class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Text('Settings', style: Theme.of(context).primary),
      Button(
        'Back',
        autofocus: true,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| back key | escape, backspace, none | escape |

## PopScope, NavigatorObserver

A route that asks before it is popped, by Escape or by the back key, a dialog too; and an observer told of every push, pop and removal.

API: [`PopScope`](https://pub.dev/documentation/twk/latest/twk/PopScope-class.html), [`NavigatorObserver`](https://pub.dev/documentation/twk/latest/twk/NavigatorObserver-class.html).

### Code

```dart
final _heard = _Heard();

@override
void dispose() {
  _heard.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    SizedBox(
      width: 44,
      height: 9,
      child: Box(
        border: .all(type: .rounded, style: Theme.of(context).border),
        padding: const .x(1),
        child: Navigator(
          observers: [_heard],
          home: const _Notes(),
          routes: {'/edit': (_) => const _Edit()},
        ),
      ),
    ),
    ListenableBuilder(
      listenable: _heard,
      builder: (context, _) => Text.rich([
        Span('heard: ', Theme.of(context).muted),
        Span(_heard.last),
      ]),
    ),
  ],
);

/// Hears of each route pushed, popped and removed, the last of them
/// [last].
final class _Heard extends NavigatorObserver with ChangeNotifier {
  var last = '';

  String _name(Route<Object?> route) => route.settings.name ?? 'a dialog';

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    last = 'pushed ${_name(route)}';
    notifyListeners();
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {
    last = 'popped ${_name(route)}';
    notifyListeners();
  }

  // a dialog closeDialog closes
  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) {
    last = 'removed ${_name(route)}';
    notifyListeners();
  }
}

/// The first route: a button that pushes the editor.
final class _Notes extends StatelessWidget {
  const _Notes();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      const Text('Notes'),
      Button(
        'Edit the note',
        onPressed: () => Navigator.pushNamed<void>(context, '/edit'),
      ),
    ],
  );
}

/// The note's editor: Back pops it, asking first while it is changed.
final class _Edit extends StatefulWidget {
  const _Edit();

  @override
  State<_Edit> createState() => _EditState();
}

final class _EditState extends State<_Edit> {
  var _changed = false;

  Future<void> _ask() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        title: 'Discard the changes?',
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          spacing: 1,
          children: [
            const Text('The note was changed.'),
            Row(
              mainAxisSize: .min,
              spacing: 2,
              children: [
                Button(
                  'Discard',
                  autofocus: true,
                  onPressed: () => closeDialog(context, true),
                ),
                Button('Keep', onPressed: () => closeDialog(context, false)),
              ],
            ),
          ],
        ),
      ),
    );
    if ((discard ?? false) && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_changed,
    // a pop it kept: Back or the back key while the note is changed
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        unawaited(_ask());
      }
    },
    child: Column(
      crossAxisAlignment: .start,
      spacing: 1,
      children: [
        Text('Edit the note', style: Theme.of(context).primary),
        Checkbox(
          value: _changed,
          label: 'changed',
          onChanged: (v) => setState(() => _changed = v),
        ),
        Button(
          'Back',
          autofocus: true,
          onPressed: () => Navigator.maybePop(context),
        ),
      ],
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| PopScope | on, off | true |
| esc in the dialog | closes it, is kept | closes it |

## Breadcrumbs

Where a screen is in a hierarchy, each level a link up: the arrows and Enter or a click go to one, and the middle collapses into … where the row does not fit.

API: [`Breadcrumbs`](https://pub.dev/documentation/twk/latest/twk/Breadcrumbs-class.html).

### Code

```dart
static const _path = ['twk', 'packages', 'gallery', 'lib', 'src', 'pages'];
var _at = _path.length - 1;

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    SizedBox(
      width: 36,
      child: Breadcrumbs(
        items: _path,
        current: _at,
        onSelected: (index) => setState(() => _at = index),
      ),
    ),
    Text.rich([
      Span('at: ', Theme.of(context).muted),
      Span(_path.take(_at + 1).join('/')),
    ]),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| width | 12 cells to 50 cells | 36 |
| leading kept | 1, 0, 2 | 1 |
| separator | ›, / | › |

## Pagination

The pages of a long list on one row, the current one among its siblings: the arrows, PageUp and PageDown, a page number typed or a click go to another.

API: [`Pagination`](https://pub.dev/documentation/twk/latest/twk/Pagination-class.html).

### Code

```dart
var _page = 1;

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      SizedBox(
        width: 56,
        child: Pagination(
          page: _page,
          pageCount: 42,
          onChanged: (page) => setState(() => _page = page),
        ),
      ),
      Text.rich([
        Span('page: ', theme.muted),
        Span('${_page + 1} of 42'),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| width | 16 cells to 56 cells | 56 |
| siblings | 1, 0, 2 | 1 |
| first and last | on, off | true |
| previous and next | on, off | true |
| range | on, off | false |

## Stepper

A wizard of steps under their headers, each left forward once its validation takes it: Next or PageDown validates, Back or PageUp goes back, a header clicked goes to it.

API: [`Stepper`](https://pub.dev/documentation/twk/latest/twk/Stepper-class.html).

### Code

```dart
final _name = TextEditingController(text: 'my_app');
final _packages = {'args'};
var _created = '';

@override
void dispose() {
  _name.dispose();
  super.dispose();
}

Widget _package(String name) => Checkbox(
  value: _packages.contains(name),
  label: name,
  onChanged: (on) => setState(() {
    if (!on) {
      _packages.remove(name);
    } else {
      _packages.add(name);
    }
  }),
);

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      SizedBox(
        width: 50,
        child: Stepper(
          steps: [
            Step(
              title: 'Name',
              subtitle: 'What the package is called',
              content: TextField(
                controller: _name,
                semanticsLabel: 'Name',
              ),
              validate: () =>
                  _name.text.isEmpty ? 'The package needs a name' : null,
            ),
            Step(
              title: 'Packages',
              subtitle: 'What it depends on',
              content: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  _package('args'),
                  _package('http'),
                  _package('path'),
                ],
              ),
              // as a server that looks them up would
              validate: () async {
                await Future<void>.delayed(
                  const Duration(milliseconds: 800),
                );
                return _packages.isEmpty ? 'Pick one at least' : null;
              },
            ),
            Step(
              title: 'Confirm',
              content: Text(
                'Create ${_name.text} with ${_packages.join(', ')}?',
              ),
            ),
          ],
          onFinished: () => setState(() => _created = _name.text),
        ),
      ),
      Text.rich([
        Span('created: ', theme.muted),
        if (_created.isEmpty)
          Span('nothing', theme.muted)
        else
          Span(_created),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| direction | horizontal, vertical | horizontal |
| linear | on, off | true |
| back and next | on, off | true |
| packages disabled | on, off | false |
