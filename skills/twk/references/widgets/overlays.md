<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Overlays

Dialogs, toasts, tooltips, popovers, menus and the command palette, over the app.

[All widgets](../widgets.md)

## Overlay

A layer over the app that dialogs, toasts, menus and tooltips go in; an entry of its own goes in it too.

API: [`Overlay`](https://pub.dev/documentation/twk/latest/twk/Overlay-class.html).

### Code

```dart
final _entries = <OverlayEntry>[];

@override
void dispose() {
  for (final entry in _entries) {
    entry.remove();
  }
  super.dispose();
}

void _insert() {
  final n = _entries.length + 1;
  final entry = OverlayEntry(
    builder: (context) => Positioned(
      right: 4 * n - 3,
      top: 2 * n - 1,
      child: Panel(
        padding: const .x(1),
        child: Text.rich([
          'Entry $n'.bold,
          Span(' of the overlay', Theme.of(context).muted),
        ]),
      ),
    ),
  );
  Overlay.of(context).insert(entry);
  setState(() => _entries.add(entry));
}

void _remove() => setState(() => _entries.removeLast().remove());

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    Row(
      mainAxisSize: .min,
      spacing: 2,
      children: [
        Button(
          'Insert an entry',
          onPressed: _entries.length < 3 ? _insert : null,
        ),
        Button('Remove one', onPressed: _entries.isEmpty ? null : _remove),
      ],
    ),
    Text.rich([
      Span('entries: ', Theme.of(context).muted),
      Span('${_entries.length}'),
      Span(' of the overlay', Theme.of(context).muted),
    ]),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| positioned | topRight, topLeft, bottomLeft | topRight |
| shadow | on, off | true |
| look | raised, bordered | raised |

## App

The root of an app: its theme over the Overlay its dialogs show in, over the app and its own keys.

API: [`App`](https://pub.dev/documentation/twk/latest/twk/App-class.html).

### Code

```dart
@override
Widget build(BuildContext context) => SizedBox(
  // room for the dialog: the Overlay it shows in is the App's size
  width: 32,
  height: 9,
  child: App(
    theme: ThemeData.nord,
    // a context below the App: its Overlay is the one the dialog shows in
    child: Builder(
      builder: (context) => Center(
        child: Button(
          'Ask',
          onPressed: () => unawaited(
            showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                title: 'In the theme',
                child: Button(
                  'OK',
                  autofocus: true,
                  onPressed: () => closeDialog(context),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| theme | nord, light, dark | nord |

## Dialog

A box over the app, the rest dimmed behind a barrier; Tab stays in it, Escape closes it.

API: [`Dialog`](https://pub.dev/documentation/twk/latest/twk/Dialog-class.html).

### Code

```dart
String? _answer;

void _ask() => unawaited(
  showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      title: 'Delete',
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 1,
        children: [
          const Text('Delete 3 files?'),
          Row(
            mainAxisSize: .min,
            spacing: 2,
            children: [
              Button(
                'Delete',
                autofocus: true,
                onPressed: () => closeDialog(context, true),
              ),
              Button('Keep', onPressed: () => closeDialog(context, false)),
            ],
          ),
        ],
      ),
    ),
    alignment: .center,
  ).then(
    (delete) => setState(
      () => _answer = switch (delete) {
        true => 'deleted',
        false => 'kept',
        null => 'dismissed',
      },
    ),
  ),
);

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    Button('Ask', onPressed: _ask),
    Text.rich([
      Span('answer: ', Theme.of(context).muted),
      switch (_answer) {
        null => Span('nothing', Theme.of(context).muted),
        final answer => Span(answer),
      },
    ]),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| alignment | center, topCenter, bottomRight | center |
| shadow | on, off | false |
| look | raised, bordered | raised |
| dismissible | on, off | true |

## Toast

A message that shows for a while and goes, over a corner of the app.

### Code

```dart
var _n = 0;

void _show() {
  final theme = Theme.of(context);
  final (message, style) = [
    ('Saved 3 files.', theme.success),
    ('Copied the path.', theme.info),
    ('Disk nearly full.', theme.warning),
    ('Upload failed.', theme.error),
  ][_n++ % 4];
  showToast(
    context: context,
    message: message,
    alignment: .bottomRight,
    style: style,
  );
}

@override
Widget build(BuildContext context) => Button('Show a toast', onPressed: _show);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| alignment | bottomRight, topRight, bottomCenter | bottomRight |
| duration | 1 s, 3 s, 5 s | 3 s |
| look | raised, bordered | raised |

## Tooltip

A message by a widget while the mouse or the keyboard focus rests on it, or while a TooltipController says, centred under it by an AnchorFollower in the overlay; above it where there is no room below.

API: [`Tooltip`](https://pub.dev/documentation/twk/latest/twk/Tooltip-class.html).

### Code

```dart
final _share = TooltipController();

@override
void dispose() {
  _share.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    Row(
      mainAxisSize: .min,
      spacing: 2,
      children: [
        for (final (label, message, done) in const [
          ('Save', 'Saves the file', 'Saved'),
          ('Open', 'Opens a file', 'Opened'),
          ('Share', 'Copies a link to it', 'Link copied'),
        ])
          Tooltip(
            message: message,
            controller: label == 'Share' ? _share : null,
            child: Button(
              label,
              onPressed: () => showToast(
                context: context,
                message: done,
                style: Theme.of(context).success,
              ),
            ),
          ),
      ],
    ),
    // shows the Share message at once, until it is pressed again
    ListenableBuilder(
      listenable: _share,
      builder: (context, _) => Button(
        _share.isShown ? 'Hide the tip' : 'Show the tip',
        onPressed: _share.isShown ? _share.hide : _share.show,
      ),
    ),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| wait | 100 ms, 500 ms, 1 s | 500 ms |
| on hover | on, off | true |
| on focus | on, off | true |
| look | raised, bordered | raised |

## Popover

A widget by another while the app says so, placed by an AnchorTarget around it and an AnchorFollower in the overlay; Escape or a click outside closes it.

API: [`Popover`](https://pub.dev/documentation/twk/latest/twk/Popover-class.html).

### Code

```dart
var _open = false;

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Popover(
    open: _open,
    onDismiss: () => setState(() => _open = false),
    popover: Panel(
      padding: const .x(1),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          const Text('The popover, by the button.'),
          Text('Escape or a click outside closes it.', style: theme.muted),
        ],
      ),
    ),
    child: Button(
      _open ? 'Close' : 'Open',
      onPressed: () => setState(() => _open = !_open),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| dismissible | on, off | true |
| look | raised, bordered | raised |

## MenuBar

Menus in a bar: F10 or a click opens one, Alt and a mnemonic too, or a MenuController from the app; the arrows, Enter and the mnemonics choose.

API: [`MenuBar`](https://pub.dev/documentation/twk/latest/twk/MenuBar-class.html).

### Code

```dart
final _menus = MenuController();
String? _chosen;
var _wrap = true;
var _numbers = false;

@override
void dispose() {
  _menus.dispose();
  super.dispose();
}

void _choose(String what) => setState(() => _chosen = what);
void _open() => _choose('Open');
void _save() => _choose('Save');
void _undo() => _choose('Undo');

@override
Widget build(BuildContext context) {
  final child = Padding(
    padding: const .all(1),
    child: Column(
      crossAxisAlignment: .start,
      spacing: 1,
      children: [
        Text.rich([
          Span('chosen: ', Theme.of(context).muted),
          switch (_chosen) {
            null => Span('nothing', Theme.of(context).muted),
            final chosen => Span(chosen),
          },
        ]),
        Row(
          spacing: 2,
          children: [
            Checkbox(
              value: _wrap,
              label: 'wrap lines',
              onChanged: (value) => setState(() => _wrap = value),
            ),
            // File › Open recent, opened from outside the bar
            Button(
              'Recent files',
              onPressed: () => _menus.open([0, 2]),
            ),
          ],
        ),
      ],
    ),
  );
  return SizedBox(
    width: 48,
    height: 8,
    child: MenuBar(
      controller: _menus,
      menus: [
        Menu(
          '&File',
          items: [
            MenuItem('&New', onSelected: () => _choose('New')),
            MenuItem('&Open…', onSelected: _open),
            Menu(
              'Open &recent',
              items: [
                for (final file in const [
                  'main.dart',
                  'page.dart',
                  'overlay.dart',
                ])
                  MenuItem(file, onSelected: () => _choose(file)),
              ],
            ),
            const MenuDivider(),
            MenuItem('&Save', onSelected: _save),
            const MenuItem('&Print'),
          ],
        ),
        Menu(
          '&Edit',
          items: [
            MenuItem('&Undo', onSelected: _undo),
            const MenuItem('&Redo'),
            const MenuDivider(),
            for (final what in const ['Cu&t', '&Copy', '&Paste'])
              MenuItem(
                what,
                onSelected: () => _choose(what.replaceAll('&', '')),
              ),
          ],
        ),
        Menu(
          '&View',
          items: [
            MenuItem(
              '&Wrap lines',
              checked: _wrap,
              onSelected: () => setState(() {
                _wrap = !_wrap;
                _chosen = 'Wrap lines';
              }),
            ),
            MenuItem(
              'Line &numbers',
              checked: _numbers,
              onSelected: () => setState(() {
                _numbers = !_numbers;
                _chosen = 'Line numbers';
              }),
            ),
          ],
        ),
      ],
      // the items show the keys bound to what they call
      child: KeyBindings(
        {'ctrl+o': _open, 'ctrl+s': _save, 'ctrl+z': _undo},
        child: child,
      ),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| keys bound | on, off | true |
| look | raised, bordered | raised |

## ContextMenu

A menu at the mouse on a right click, under the focus on Shift+F10, or where a MenuController opens it.

API: [`ContextMenu`](https://pub.dev/documentation/twk/latest/twk/ContextMenu-class.html).

### Code

```dart
final _menu = MenuController();
String? _chosen;
var _copied = false;

@override
void dispose() {
  _menu.dispose();
  super.dispose();
}

void _choose(String what) => setState(() {
  _chosen = what;
  _copied |= what == 'Cut' || what == 'Copy';
});

@override
Widget build(BuildContext context) => ContextMenu(
  controller: _menu,
  items: [
    MenuItem('Cu&t', onSelected: () => _choose('Cut')),
    MenuItem('&Copy', onSelected: () => _choose('Copy')),
    MenuItem('&Paste', onSelected: _copied ? () => _choose('Paste') : null),
    const MenuDivider(),
    MenuItem('Select &all', onSelected: () => _choose('Select all')),
  ],
  child: SizedBox(
    width: 40,
    height: 5,
    child: Box(
      border: .all(type: .rounded, style: Theme.of(context).border),
      padding: const .x(1),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          const Text('Right click in here.'),
          Row(
            spacing: 2,
            children: [
              Button('Or focus me', onPressed: () {}),
              // at a cell of the child, as a right click there
              Button(
                'Open the menu',
                onPressed: () => _menu.open(null, (22, 1)),
              ),
            ],
          ),
          Text.rich([
            Span('chosen: ', Theme.of(context).muted),
            switch (_chosen) {
              null => Span('nothing', Theme.of(context).muted),
              final chosen => Span(chosen),
            },
          ]),
        ],
      ),
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| look | raised, bordered | raised |

## CommandPalette

What can be done, found by typing: Tab to a button, then Ctrl+K, or press Dart files, whose CommandPaletteController opens it with dart typed; commandsFor adds the files that match. The gallery's own, Ctrl+P, goes to a page.

API: [`CommandPalette`](https://pub.dev/documentation/twk/latest/twk/CommandPalette-class.html).

### Code

```dart
final _palette = CommandPaletteController();
String? _ran;

@override
void dispose() {
  _palette.dispose();
  super.dispose();
}

void _run(String what) => setState(() => _ran = what);
void _build() => _run('Build');
void _test() => _run('Run tests');
void _save() => _run('Save');

// the files whose path matches what is typed, none while nothing is
Iterable<Command> _files(String query) => [
  if (query.isNotEmpty)
    for (final file in const [
      'lib/main.dart',
      'lib/src/app.dart',
      'lib/src/theme.dart',
      'test/app_test.dart',
      'README.md',
      'pubspec.yaml',
    ])
      if (fuzzyMatch(query, file) != null)
        Command(file, onSelected: () => _run('open $file')),
];

@override
Widget build(BuildContext context) => CommandPalette(
  controller: _palette,
  openKey: 'ctrl+k',
  width: 40,
  commands: [
    Command('Build', onSelected: _build),
    Command('Run tests', onSelected: _test),
    Command('Format', onSelected: () => _run('Format')),
    Command('Deploy', onSelected: () => _run('Deploy')),
  ],
  // listed after the commands that match
  commandsFor: _files,
  // listed after the commands: the keys bound with a hint where the
  // focus is, the Button's Enter (press) and Ctrl+S (Save); by each the
  // key bound to what it calls
  child: KeyBindings(
    {'ctrl+b': _build, 'f8': _test, 'ctrl+s': _save},
    hints: {'ctrl+s': 'Save'},
    child: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 1,
      children: [
        Row(
          mainAxisSize: .min,
          spacing: 2,
          children: [
            Button('Focus me', onPressed: () => _run('press')),
            // opens the palette with dart typed
            Button(
              'Dart files',
              onPressed: () => _palette.open(query: 'dart'),
            ),
          ],
        ),
        Text.rich([
          Span('ran: ', Theme.of(context).muted),
          switch (_ran) {
            null => Span('nothing', Theme.of(context).muted),
            final ran => Span(ran),
          },
        ]),
      ],
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| width | 40, 60 | 40 |
| rows | 3, 10 | 10 |
| files | on, off | true |
| rule | on, off | false |
| bar | on, off | false |
| thumb | on, off | false |
| placeholder | on, off | false |
| look | raised, bordered | raised |

## OptionList

Options in rows, one highlighted, the characters a query matched standing out and a detail at the right edge: what an autocomplete, a Select and a command palette list.

API: [`OptionList`](https://pub.dev/documentation/twk/latest/twk/OptionList-class.html).

### Code

```dart
const _commands = [
  ('Open file', 'ctrl+o'),
  ('Save', 'ctrl+s'),
  ('Save as…', 'ctrl+shift+s'),
  ('Close tab', 'ctrl+w'),
  ('Find', 'ctrl+f'),
  ('Replace', 'ctrl+h'),
  ('Go to line', 'ctrl+g'),
  ('Toggle theme', 'ctrl+t'),
  ('Quit', 'ctrl+q'),
];

var _highlighted = 0;
String? _ran;

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final options = [
    for (final (label, keys) in _commands) Option(label, detail: keys),
  ];
  final highlighted = _highlighted.clamp(0, options.length - 1);
  void highlight(int i) => setState(() => _highlighted = i);
  void move(int by) =>
      highlight((highlighted + by).clamp(0, options.length - 1));
  void run(int i) => setState(() => _ran = options[i].label);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      // the list takes no keys: a Pressable around it
      // does, its border primary while it has the focus
      Pressable(
        bindings: {
          'up': () => move(-1),
          'down': () => move(1),
          'enter': () => run(highlighted),
        },
        hints: const {'up': 'select', 'down': 'select', 'enter': 'run'},
        builder: (context, focused) => Box(
          border: .all(
            type: .rounded,
            style: focused ? theme.primary : theme.border,
          ),
          child: OptionList(
            options: options,
            highlighted: highlighted,
            rows: 5,
            onHighlight: highlight,
            onSelected: run,
          ),
        ),
      ),
      Text.rich([
        Span('ran: ', theme.muted),
        if (_ran case final ran?)
          Span(ran)
        else
          Span('nothing', theme.muted),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| marks of | none, o, sa | none |
| rows | 3, 5, 8 | 5 |
| details | on, off | true |
| bar | on, off | true |
| thumb | on, off | true |

## ModalBarrier

What dims the app under a dialog and keeps the mouse from it.

API: [`ModalBarrier`](https://pub.dev/documentation/twk/latest/twk/ModalBarrier-class.html).

### Code

```dart
var _pressed = 0;
var _dismissed = 0;

@override
Widget build(BuildContext context) => SizedBox(
  width: 40,
  height: 8,
  child: Stack(
    fit: .expand,
    children: [
      Column(
        crossAxisAlignment: .start,
        spacing: 1,
        children: [
          const Text(
            'The text under the barrier, dimmed by it: the mouse does not '
            'reach it.',
          ),
          Button('Press me', onPressed: () => setState(() => _pressed++)),
          Text.rich([
            Span('pressed ', Theme.of(context).muted),
            Span('$_pressed'),
            Span(', the barrier ', Theme.of(context).muted),
            Span('$_dismissed'),
          ]),
        ],
      ),
      ModalBarrier(
        onDismiss: () => setState(() => _dismissed++),
      ),
      const Center(
        child: Panel(
          padding: .x(1),
          shadow: false,
          child: Text('over it'),
        ),
      ),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| barrier | on, off | true |
| alpha | ¼, ½, ¾ | ½ |
| fade | on, off | false |

## WindowLayer

Windows over the app: a title bar drags one, an edge resizes it, its buttons minimise, maximise and close it; Tab to a title bar, then the arrows move it.

API: [`WindowLayer`](https://pub.dev/documentation/twk/latest/twk/WindowLayer-class.html).

### Code

```dart
final _notes = WindowController(left: 2, top: 3, width: 30, height: 6);
final _counter = WindowController(left: 24, top: 5, width: 26, height: 6);
final _closed = <String>{};
var _count = 0;

@override
void dispose() {
  _notes.dispose();
  _counter.dispose();
  super.dispose();
}

void _close(String title) => setState(() => _closed.add(title));

@override
Widget build(BuildContext context) => SizedBox(
  width: 50,
  height: 12,
  child: WindowLayer(
    windows: [
      if (!_closed.contains('Notes'))
        Window(
          key: const ValueKey('Notes'),
          title: 'Notes',
          controller: _notes,
          onClose: () => _close('Notes'),
          shadow: Panel.shadowOf(Theme.of(context)),
          child: const Padding(
            padding: .x(1),
            child: Text('Drag me by the title bar, or resize me by an edge.'),
          ),
        ),
      if (!_closed.contains('Counter'))
        Window(
          key: const ValueKey('Counter'),
          title: 'Counter',
          controller: _counter,
          onClose: () => _close('Counter'),
          shadow: Panel.shadowOf(Theme.of(context)),
          child: Padding(
            padding: const .x(1),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text('count: $_count'),
                Button('Add one', onPressed: () => setState(() => _count++)),
              ],
            ),
          ),
        ),
    ],
    child: Column(
      crossAxisAlignment: .start,
      children: [
        const Text('The app, under its windows.'),
        Button(
          'Open the windows closed',
          onPressed: _closed.isEmpty ? null : () => setState(_closed.clear),
        ),
      ],
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| frame | raised, bordered | raised |
| shadow | on, off | true |
| resizable | on, off | true |
| minimisable | on, off | true |
| maximisable | on, off | true |
