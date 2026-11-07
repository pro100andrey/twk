<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Controls

Buttons, checkboxes and switches, choices, sliders, forms, tabs and status bars.

[All widgets](../widgets.md)

## Button

A label pressed by a click, or by Enter or Space while it has the focus; disabled with no onPressed.

API: [`Button`](https://pub.dev/documentation/twk/latest/twk/Button-class.html).

### Code

```dart
var _saved = 0;
var _sent = 0;

// Button, as each control here, stands on
// Pressable: a node that Tab stops at unless it
// is disabled, the keys it binds while it has
// the focus (Enter, Space), a press that focuses
// it and a click.
@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Row(
        mainAxisSize: .min,
        spacing: 2,
        children: [
          Button('Save', onPressed: () => setState(() => _saved++)),
          Button('Send', onPressed: () => setState(() => _sent++)),
          const Button('Disabled', onPressed: null),
        ],
      ),
      // a key and its caption, each in its own style
      // on the one chip
      Button.rich(
        ['Enter'.bold.fg(Color.yellow), const Span(' send')],
        onPressed: () => setState(() => _sent++),
      ),
      Text.rich([
        Span('saved: ', theme.muted),
        Span('$_saved'),
        Span('  sent: ', theme.muted),
        Span('$_sent'),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| style | primary, accent, success, warning, error, info | primary |
| look | chip, outlined, filled, plain | chip |
| tall | on, off | false |

## Pressable

What the controls are built of: a node of the focus tree that Tab passes by while it is disabled, the keys it takes while it has the focus, a press that focuses it and a tap; it builds its look by whether it has the focus.

API: [`Pressable`](https://pub.dev/documentation/twk/latest/twk/Pressable-class.html).

### Code

```dart
final _starred = {'twk'};

void _toggle(String name) => setState(() {
  if (!_starred.remove(name)) {
    _starred.add(name);
  }
});

// A row that stars [name], made of a Pressable: Tab
// stops at it unless it is disabled, its bindings
// are the keys it takes while it has the focus, a
// press focuses it and a tap calls onTap; it
// builds its look by whether it has the focus.
Widget _star(String name, {bool enabled = true}) => Pressable(
  enabled: enabled,
  bindings: {'space': () => _toggle(name)},
  hints: const {'space': 'star'},
  onTap: enabled ? () => _toggle(name) : null,
  builder: (context, focused) {
    final theme = Theme.of(context);
    final on = _starred.contains(name);
    return Text.rich(
      [
        Span(
          on ? '★' : '☆',
          on ? theme.primary.merge(const .new(attrs: Attr.bold)) : theme.muted,
        ),
        Span(' $name'),
      ],
      style: !enabled
          ? theme.muted
          : focused
          ? theme.selection
          : const .new(),
    );
  },
);

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          _star('twk'),
          _star('gallery'),
          _star('archive', enabled: false),
        ],
      ),
      Text.rich([
        Span('starred: ', theme.muted),
        if (_starred.isEmpty)
          Span('nothing', theme.muted)
        else
          Span(_starred.join(', ')),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| style | primary, accent, success, warning, error, info | primary |

## Checkbox, Switch

What is on or off: a click, or Space or Enter, flips it.

API: [`Checkbox`](https://pub.dev/documentation/twk/latest/twk/Checkbox-class.html), [`Switch`](https://pub.dev/documentation/twk/latest/twk/Switch-class.html).

### Code

```dart
var _wrap = true;
var _dark = false;

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    Checkbox(
      value: _wrap,
      label: 'wrap lines',
      onChanged: (value) => setState(() => _wrap = value),
    ),
    Switch(
      value: _dark,
      label: 'dark mode',
      onChanged: (value) => setState(() => _dark = value),
    ),
    const Checkbox(value: true, label: 'disabled', onChanged: null),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| switch | pill, brackets | pill |

## RadioGroup

One of several choices: the arrows or a click choose one.

API: [`RadioGroup`](https://pub.dev/documentation/twk/latest/twk/RadioGroup-class.html).

### Code

```dart
const _fruit = [
  Choice('apple', 'apple'),
  Choice('banana', 'banana'),
  Choice('cherry', 'cherry'),
  Choice('durian', 'durian', enabled: false),
];

String? _chosen;

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      RadioGroup<String>(
        choices: _fruit,
        value: _chosen,
        direction: .vertical,
        onChanged: (value) => setState(() => _chosen = value),
      ),
      Text.rich([
        Span('chosen: ', theme.muted),
        if (_chosen case final chosen?)
          Span(chosen)
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
| direction | vertical, horizontal | vertical |
| mark | ●, *, ✓ | ● |
| theme | (●) ( ), ◉ ○ | (●) ( ) |

## SegmentedButton

A few values joined in one row, one on at a time or any of them: the arrows, a digit or a click turn one on.

API: [`SegmentedButton`](https://pub.dev/documentation/twk/latest/twk/SegmentedButton-class.html).

### Code

```dart
var _shown = {'all'};

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      SegmentedButton<String>(
        segments: const [
          Choice('all', 'All'),
          Choice('errors', 'Errors (3)'),
          Choice('warnings', 'Warnings (12)'),
          Choice('info', 'Info', enabled: false),
        ],
        selected: _shown,
        onSelectionChanged: (shown) => setState(() => _shown = shown),
      ),
      Text.rich([
        Span('shown: ', theme.muted),
        if (_shown.isEmpty)
          Span('nothing', theme.muted)
        else
          Span(_shown.join(', ')),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| multiple | on, off | false |
| allow none | on, off | false |
| selected icon | on, off | false |
| caps | square, round | square |

## Chip, ChipList

Tags on one row that wraps, with a cursor: the arrows move it, Space or a click toggles a chip, Delete or a click on its × removes it.

API: [`Chip`](https://pub.dev/documentation/twk/latest/twk/Chip-class.html), [`ChipList`](https://pub.dev/documentation/twk/latest/twk/ChipList-class.html).

### Code

```dart
static const _all = [
  'dart',
  'tui',
  'terminal',
  'widgets',
  'beta',
  'mouse',
  'keyboard',
];

var _tags = _all;
var _on = {'tui'};

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final shown = _on.where(_tags.contains);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      SizedBox(
        width: 34,
        child: ChipList<String>(
          chips: [
            for (final t in _tags) Choice(t, t, enabled: t != 'beta'),
          ],
          selected: _on,
          onSelectionChanged: (now) => setState(() => _on = now),
          onDeleted: (tag) {
            setState(() => _tags = [..._tags]..remove(tag));
          },
        ),
      ),
      Text.rich([
        Span('on: ', theme.muted),
        if (shown.isEmpty)
          Span('nothing', theme.muted)
        else
          Span(shown.join(', ')),
      ]),
      Button(
        'Bring them back',
        onPressed: _tags.length == _all.length
            ? null
            : () => setState(() => _tags = _all),
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| toggle | on, off | true |
| removable | on, off | true |
| width | 20 cells to 50 cells | 34 |

## ValueStepper

One of a few values between ‹ and ›: Left and Right or a click on an arrow step to the one before or after, stopping at the ends (`wrap: true` goes round).

API: [`ValueStepper`](https://pub.dev/documentation/twk/latest/twk/ValueStepper-class.html).

### Code

```dart
var _mode = 'dark';

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      ValueStepper<String>(
        values: const [
          Choice('dark', 'dark'),
          Choice('light', 'light'),
          Choice('sepia', 'sepia', enabled: false),
          Choice('auto', 'auto-switching'),
        ],
        value: _mode,
        onChanged: (mode) => setState(() => _mode = mode),
      ),
      Text.rich([Span('mode: ', theme.muted), Span(_mode)]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| enabled | on, off | true |

## SelectionList

Items selected by their keys: in a single selection the cursor selects, in a multiple one Space does.

API: [`SelectionList`](https://pub.dev/documentation/twk/latest/twk/SelectionList-class.html).

### Code

```dart
static const _planets = [
  'Mercury',
  'Venus',
  'Earth',
  'Mars',
  'Jupiter',
  'Saturn',
  'Uranus',
  'Neptune',
];

late final _selection = SelectionController<String>(selected: ['Earth'])
  ..addListener(() => setState(() {}));

@override
void dispose() {
  _selection.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final selected = _selection.selected;
  return SizedBox(
    width: 29,
    height: 8,
    child: Row(
      crossAxisAlignment: .start,
      spacing: 2,
      children: [
        SizedBox(
          width: 18,
          // the border primary while the list has the focus
          child: FocusBuilder(
            builder: (context, hasFocus, list) => Box(
              border: .all(
                type: .rounded,
                style: hasFocus ? theme.primary : theme.border,
              ),
              child: list,
            ),
            child: SelectionList<String>(
              itemCount: _planets.length,
              keyOf: (i) => _planets[i],
              itemBuilder: (context, i) => Text(_planets[i]),
              itemEnabled: (i) => _planets[i] != 'Venus',
              controller: _selection,
            ),
          ),
        ),
        Expanded(
          child: Text.rich([
            Span('selected\n', theme.muted),
            if (selected.isEmpty)
              Span('nothing', theme.muted)
            else
              Span(selected.join('\n')),
          ]),
        ),
      ],
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| multiple | on, off | false |
| cursor bar | on, off | true |

## Select, MultiSelect

A field that opens its choices to pick one, or several, from, or a PopupController from the app; typing filters them.

API: [`Select`](https://pub.dev/documentation/twk/latest/twk/Select-class.html), [`MultiSelect`](https://pub.dev/documentation/twk/latest/twk/MultiSelect-class.html).

### Code

```dart
const _fruit = [
  Choice('apple', 'apple'),
  Choice('apricot', 'apricot'),
  Choice('banana', 'banana'),
  Choice('blueberry', 'blueberry'),
  Choice('cherry', 'cherry'),
  Choice('durian', 'durian', enabled: false),
  Choice('fig', 'fig'),
  Choice('grape', 'grape'),
  Choice('lemon', 'lemon'),
];

final _popup = PopupController();
String? _one;
var _some = <String>{};

@override
void dispose() {
  _popup.dispose();
  super.dispose();
}

// Open, each shows its choices in an OptionList,
// as Autocomplete and CommandPalette do: the
// letters typed lit, the highlighted one on the
// selection.
@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    Row(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 4,
      children: [
        Select<String>(
          choices: _fruit,
          value: _one,
          hint: 'a fruit',
          rows: 4,
          controller: _popup,
          onChanged: (value) => setState(() => _one = value),
        ),
        MultiSelect<String>(
          choices: _fruit,
          values: _some,
          hint: 'some fruit',
          rows: 4,
          onChanged: (values) => setState(() => _some = values),
        ),
      ],
    ),
    // opens the fruit's list, the focus in its field
    Button('Choose a fruit', onPressed: _popup.open),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| inline | on, off | false |
| rows | 4, 8 | 4 |
| popup look | raised, bordered | raised |

## ConfirmInput

A question answered by y, n or Enter.

API: [`ConfirmInput`](https://pub.dev/documentation/twk/latest/twk/ConfirmInput-class.html).

### Code

```dart
bool? _answer;

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    ConfirmInput(
      'Delete 3 files?',
      // it reads defaultValue once: another is a new input
      key: const ValueKey(true),
      defaultValue: true,
      onConfirmed: (yes) => setState(() => _answer = yes),
    ),
    Text.rich([
      Span('answer: ', Theme.of(context).muted),
      switch (_answer) {
        null => Span('nothing', Theme.of(context).muted),
        true => const Span('yes'),
        false => const Span('no'),
      },
    ]),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| default | yes, no | yes |
| answers | Yes, No, Delete, Keep | Yes, No |

## Slider

A value along a track: the arrows, a press or a drag move the thumb, which stands in eighths of a cell.

API: [`Slider`](https://pub.dev/documentation/twk/latest/twk/Slider-class.html).

### Code

```dart
var _volume = 0.5;

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    SizedBox(
      width: 30,
      child: Slider(
        value: _volume,
        semanticsLabel: 'Volume',
        onChanged: (value) => setState(() => _volume = value),
      ),
    ),
    Text.rich([
      Span('volume: ', Theme.of(context).muted),
      Span('${(_volume * 100).round()}%'),
    ]),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| divisions | none, 10, 4 | none |
| width | 10 cells to 40 cells | 30 |

## NumberInput

A number typed, or stepped by Up and Down, the wheel or a click on ▴▾; kept within its bounds.

API: [`NumberInput`](https://pub.dev/documentation/twk/latest/twk/NumberInput-class.html).

### Code

```dart
var _copies = 1.0;
var _price = 9.5;

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    Row(
      mainAxisSize: .min,
      children: [
        const SizedBox(width: 16, child: Text('copies, 1 to 99')),
        SizedBox(
          width: 10,
          child: NumberInput(
            value: _copies,
            min: 1,
            max: 99,
            onChanged: (value) => setState(() => _copies = value),
          ),
        ),
      ],
    ),
    Row(
      mainAxisSize: .min,
      children: [
        const SizedBox(width: 16, child: Text('price, by 0.25')),
        SizedBox(
          width: 10,
          child: NumberInput(
            value: _price,
            min: 0,
            step: 0.25,
            decimals: 2,
            onChanged: (value) => setState(() => _price = value),
          ),
        ),
      ],
    ),
    Text(
      '${_copies.round()} × ${_price.toStringAsFixed(2)} = '
      '${(_copies * _price).toStringAsFixed(2)}',
    ),
  ],
);
```

## DatePicker

A date typed, stepped by Up and Down, or picked from the calendar that Alt+Down, a click on ▾ or a PopupController opens.

API: [`DatePicker`](https://pub.dev/documentation/twk/latest/twk/DatePicker-class.html).

### Code

```dart
final _calendar = PopupController();
DateTime? _date;

static const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

@override
void dispose() {
  _calendar.dispose();
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
        SizedBox(
          width: 22,
          child: DatePicker(
            value: _date,
            firstDate: DateTime(2026),
            lastDate: DateTime(2026, 12, 31),
            today: DateTime(2026, 10, 19),
            controller: _calendar,
            onChanged: (date) => setState(() => _date = date),
          ),
        ),
        // opens the calendar, the focus in it
        Button('Calendar', onPressed: _calendar.open),
      ],
    ),
    Text.rich([
      Span('picked: ', Theme.of(context).muted),
      switch (_date) {
        null => Span('nothing', Theme.of(context).muted),
        final date => Span(
          '${_days[date.weekday - 1]}, ${date.day} '
          '${Calendar.englishMonthNames[date.month - 1]}',
        ),
      },
    ]),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| time of day | on, off | false |
| weeks start | monday, sunday | monday |
| popup look | raised, bordered | raised |

## FilePicker

A file picked from the directory listed under a field that names its path: the arrows and Enter go through it, Tab completes a name; a FilePickerController goes to a directory.

API: [`FilePicker`](https://pub.dev/documentation/twk/latest/twk/FilePicker-class.html).

### Code

```dart
final _files = FilePickerController();
String? _picked;

@override
void dispose() {
  _files.dispose();
  super.dispose();
}

static const _filters = [
  FileFilter('Dart', ['dart']),
  FileFilter('All files'),
];

void _show(List<String>? paths) {
  if (mounted && paths != null) {
    setState(() => _picked = paths.join(', '));
  }
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 50,
    child: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 1,
      children: [
        SizedBox(
          height: 8,
          // a picker for each mode: it reads its mode once
          child: FilePicker(
            key: const ValueKey('open'),
            controller: _files,
            filters: _filters,
            onPicked: _show,
          ),
        ),
        Row(
          crossAxisAlignment: .start,
          spacing: 2,
          children: [
            Button(
              'In a dialog',
              onPressed: () => unawaited(
                showFilePicker(context, filters: _filters).then(_show),
              ),
            ),
            // the picker above gone there, the name typed kept
            Button('lib/src', onPressed: () => _files.goTo('~/twk/lib/src')),
            Expanded(
              child: Text.rich(
                [
                  Span('picked: ', theme.muted),
                  if (_picked case final picked?)
                    Span(picked)
                  else
                    Span('nothing', theme.muted),
                ],
                maxLines: 2,
                overflow: .ellipsis,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| mode | open, open several, save, directory | open |
| show hidden | on, off | false |

## Form, FormField

Fields validated and submitted together: Enter goes on to the next field, and from the last submits the form.

API: [`Form`](https://pub.dev/documentation/twk/latest/twk/Form-class.html), [`FormField`](https://pub.dev/documentation/twk/latest/twk/FormField-class.html).

### Code

```dart
final _form = GlobalKey<FormState>();
String? _submitted;
var _name = '';

@override
Widget build(BuildContext context) => Form(
  key: _form,
  onSubmitted: () => setState(() => _submitted = _name),
  child: SizedBox(
    width: 40,
    child: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 1,
      children: [
        TextFormField(
          placeholder: 'name',
          validator: (name) => name!.isEmpty ? 'a name, please' : null,
          onSaved: (name) => _name = name!,
        ),
        TextFormField(
          placeholder: 'email',
          validator: (email) =>
              email!.contains('@') ? null : 'an email has an @ in it',
        ),
        FormField<bool>(
          initialValue: false,
          validator: (accepted) =>
              accepted! ? null : 'the terms are to be accepted',
          builder: (field) => Checkbox(
            value: field.value!,
            onChanged: field.didChange,
            label: 'I accept the terms',
          ),
        ),
        Row(
          spacing: 2,
          children: [
            Button('Submit', onPressed: () => _form.currentState!.submit()),
            Button('Reset', onPressed: () => _form.currentState!.reset()),
            Expanded(
              child: Text.rich(
                [
                  Span(' submitted: ', Theme.of(context).muted),
                  if (_submitted case final submitted?)
                    Span(submitted)
                  else
                    Span('nothing', Theme.of(context).muted),
                ],
                wrap: .none,
                overflow: .ellipsis,
              ),
            ),
          ],
        ),
      ],
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| validate | disabled, always, onUserInteraction, onUnfocus | disabled |

## TabBar, TabBarView

Tabs to pick a view by: Left and Right, or a click.

API: [`TabBar`](https://pub.dev/documentation/twk/latest/twk/TabBar-class.html), [`TabBarView`](https://pub.dev/documentation/twk/latest/twk/TabBarView-class.html).

### Code

```dart
final _tabs = TabController(length: 3);
var _wrap = true;
var _hidden = false;
var _indent = 'spaces';

@override
void dispose() {
  _tabs.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) => SizedBox(
  width: 40,
  height: 7,
  child: Column(
    crossAxisAlignment: .stretch,
    children: [
      TabBar(controller: _tabs, tabs: const ['General', 'Editor', 'Keys']),
      Expanded(
        // the view, its border primary while the focus is in it
        child: FocusBuilder(
          builder: (context, hasFocus, view) => Box(
            border: .all(
              type: .rounded,
              style: hasFocus
                  ? Theme.of(context).primary
                  : Theme.of(context).border,
            ),
            padding: const .x(1),
            child: view,
          ),
          child: TabBarView(
            controller: _tabs,
            children: [
              Column(
                crossAxisAlignment: .start,
                children: [
                  Checkbox(
                    value: _wrap,
                    label: 'wrap lines',
                    onChanged: (on) => setState(() => _wrap = on),
                  ),
                  Checkbox(
                    value: _hidden,
                    label: 'show hidden files',
                    onChanged: (on) => setState(() => _hidden = on),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: .start,
                children: [
                  const Text('Indent with'),
                  RadioGroup<String>(
                    choices: const [
                      Choice('spaces', 'spaces'),
                      Choice('tabs', 'tabs'),
                    ],
                    value: _indent,
                    direction: .horizontal,
                    onChanged: (value) => setState(() => _indent = value),
                  ),
                ],
              ),
              const Text('ctrl+s saves the file.\nctrl+q quits.'),
            ],
          ),
        ),
      ),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| tabs | 3, 7 | 3 |
| look | plain, strip | plain |

## KeyHintsBar

The keys that can be pressed now, with their hints, as the focus moves: Tab to the field to see its keys.

API: [`KeyHintsBar`](https://pub.dev/documentation/twk/latest/twk/KeyHintsBar-class.html).

### Code

```dart
String? _did;
var _autosave = false;

void _do(String what) => setState(() => _did = what);

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return KeyBindings(
    {
      'ctrl+s': () => _do('save'),
      'ctrl+x ctrl+o': () => _do('open'),
      'f2': () => _do('rename'),
    },
    hints: const {'ctrl+s': 'save', 'ctrl+x ctrl+o': 'open'},
    child: SizedBox(
      width: 44,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 1,
        children: [
          Row(
            spacing: 2,
            children: [
              // a field without a box shows the focus on the selection
              Expanded(
                child: TextField(
                  placeholder: 'a field',
                  focusedStyle: theme.selection,
                ),
              ),
              Checkbox(
                value: _autosave,
                label: 'autosave',
                onChanged: (on) => setState(() => _autosave = on),
              ),
            ],
          ),
          Text.rich([
            Span('did: ', theme.muted),
            if (_did case final did?)
              Span(did)
            else
              Span('nothing', theme.muted),
          ]),
          Box(
            border: .all(type: .rounded, style: theme.border),
            padding: const .x(1),
            child: const KeyHintsBar(),
          ),
        ],
      ),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| unhinted keys | on, off | false |
| join keys | on, off | true |
| keys named by | signs, names | signs |
| separator | blanks, dot, line | blanks |

## StatusMessage, Badge

A message of a kind after its icon, in its color; a short label on its color.

API: [`StatusMessage`](https://pub.dev/documentation/twk/latest/twk/StatusMessage-class.html), [`Badge`](https://pub.dev/documentation/twk/latest/twk/Badge-class.html).

### Code

```dart
return Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    const StatusMessage('Saving runs in the background.', kind: .info),
    const StatusMessage(
      'The disk has 120 GB free.',
      kind: .info,
      title: 'Disk',
    ),
    Row(
      mainAxisSize: .min,
      spacing: 1,
      children: [
        for (final kind in StatusKind.values) Badge(kind.name, kind: kind),
        const Badge('3'),
      ],
    ),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| kind | info, success, warning, error | info |

## Callout

A notice in a box lined in the color of its kind, its title on the top edge; [×] or Escape dismisses it, and buttons below act on it.

API: [`Callout`](https://pub.dev/documentation/twk/latest/twk/Callout-class.html).

### Code

```dart
var _shown = true;
var _did = '';

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      if (_shown)
        SizedBox(
          width: 44,
          child: Callout.text(
            'A newer version of twk is out: 0.3.0.',
            onDismissed: () => setState(() {
              _shown = false;
              _did = 'dismissed';
            }),
            actions: [
              Button(
                'Update',
                onPressed: () => setState(() => _did = 'update'),
              ),
            ],
          ),
        )
      else
        Button(
          'Show it again',
          onPressed: () => setState(() {
            _shown = true;
            _did = 'shown again';
          }),
        ),
      Text.rich([
        Span('did: ', theme.muted),
        if (_did.isEmpty)
          Span('nothing', theme.muted)
        else
          Span(_did),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| kind | info, success, warning, error | info |
| dismissible | on, off | true |
| actions | on, off | true |
| title | kind, own | kind |
| icon | kind, own, none | kind |
| border | single, rounded, heavy | single |
| width | 24 cells to 60 cells | 44 |

## Hyperlink

Text linked to a URL, which a terminal that knows hyperlinks opens.

API: [`Hyperlink`](https://pub.dev/documentation/twk/latest/twk/Hyperlink-class.html).

### Code

```dart
return const Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  spacing: 1,
  children: [
    Hyperlink('https://dart.dev', text: 'The Dart language'),
    Hyperlink('https://pub.dev'),
    Hyperlink('file:///home/user/twk/README.md', text: 'the README'),
  ],
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| style | primary, accent, info | primary |
| shows | text, url | text |

## ListTile

A row of a list: a title over a subtitle, something before and after them; tapped by a click or Enter, lit while focused or under the mouse.

API: [`ListTile`](https://pub.dev/documentation/twk/latest/twk/ListTile-class.html).

### Code

```dart
var _open = 0;

@override
Widget build(BuildContext context) {
  const files = [
    ('notes.md', '2 KB, an hour ago'),
    ('todo.md', '640 B, today'),
    ('photo.png', '1.2 MB, last week'),
    ('locked.txt', 'no access'),
  ];
  return SizedBox(
    width: 32,
    child: Column(
      mainAxisSize: .min,
      children: [
        for (final (i, (name, about)) in files.indexed)
          ListTile(
            leading: const Text('▤'),
            title: Text(name),
            subtitle: Text(about),
            trailing: const Text('›'),
            selected: i == _open,
            enabled: i != 3,
            onTap: () => setState(() => _open = i),
          ),
      ],
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| leading | on, off | true |
| subtitle | on, off | true |
| trailing | on, off | true |

## StatusBar

A row of three sections, left, centre and right; those that do not fit give way, the centre first.

API: [`StatusBar`](https://pub.dev/documentation/twk/latest/twk/StatusBar-class.html).

### Code

```dart
return SizedBox(
  width: 50,
  child: StatusBar(
    left: const Badge('NORMAL'),
    center: const Text(
      'example/widgets/main.dart',
      wrap: .none,
      overflow: .ellipsis,
    ),
    right: Text('Ln 12, Col 4', style: Theme.of(context).muted),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| width | 12 cells to 50 cells | 50 |
| spacing | 0, 1, 3 | 1 |
