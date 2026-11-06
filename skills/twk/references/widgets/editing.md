<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Editing

Text fields and what is drawn around them, text areas and completion as the user types.

[All widgets](../widgets.md)

## TextField

A line of text to edit: Tab to it and type; Enter submits it, Ctrl+Z undoes.

API: [`TextField`](https://pub.dev/documentation/twk/latest/twk/TextField-class.html).

### Code

```dart
var _submitted = '';
var _heard = '';

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      SizedBox(
        width: 30,
        // the border primary while the focus is in it
        child: FocusBuilder(
          builder: (context, hasFocus, field) => Box(
            border: .all(
              type: .rounded,
              style: hasFocus ? theme.primary : theme.border,
            ),
            child: field,
          ),
          child: TextField(
            placeholder: 'type here',
            onSubmitted: (text) => setState(() => _submitted = text),
            onEditingComplete: () =>
                setState(() => _heard = 'editing complete'),
            onPaste: (text) {
              setState(
                () => _heard = 'a paste of ${text.characterCount} characters',
              );
              return false;
            },
          ),
        ),
      ),
      Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          Text.rich([
            Span('submitted: ', theme.muted),
            if (_submitted.isEmpty)
              Span('nothing', theme.muted)
            else
              Span(_submitted),
          ]),
          Text.rich([
            Span('heard: ', theme.muted),
            if (_heard.isEmpty)
              Span('nothing', theme.muted)
            else
              Span(_heard),
          ]),
        ],
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| obscured | on, off | false |
| max length | none, 8 | none |
| cursor | bar, block, underline, terminal | bar |
| blinking | on, off | false |
| text align | left, center, right, start, end | left |
| read only | on, off | false |
| enabled | on, off | true |
| a paste | goes in, taken | goes in |

## InputDecoration

What is drawn around a field: a label, an icon, a prefix and a suffix, a helper, an error and a counter, in a box, over a line or bare, filled.

API: [`InputDecoration`](https://pub.dev/documentation/twk/latest/twk/InputDecoration-class.html).

### Code

```dart
var _theme = 'dark';
var _password = '';

@override
Widget build(BuildContext context) {
  return Row(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 2,
    children: [
      SizedBox(
        width: 24,
        child: Column(
          mainAxisSize: .min,
          spacing: 1,
          children: [
            Select<String>(
              choices: const [
                Choice('dark', 'Dark'),
                Choice('light', 'Light'),
                Choice('nord', 'Nord'),
              ],
              value: _theme,
              onChanged: (theme) => setState(() => _theme = theme),
              decoration: const InputDecoration(
                icon: Text('◐'),
                labelText: 'Theme',
                helperText: 'Enter opens it',
                border: OutlineInputBorder(),
              ),
            ),
            TextField(
              placeholder: 'twk',
              decoration: const InputDecoration(
                labelText: 'Site',
                prefixText: 'https://',
                suffixText: '.dev',
                helperText: 'where it lives',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      SizedBox(
        width: 24,
        child: Column(
          mainAxisSize: .min,
          spacing: 1,
          children: [
            TextField(
              placeholder: 'files, commands',
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Text('⌕'),
                suffixIcon: Text('↵'),
                helperText: 'by name',
                border: OutlineInputBorder(),
              ),
            ),
            // only the field builds again as its text changes
            StatefulBuilder(
              builder: (context, setState) => TextField(
                placeholder: 'secret',
                obscureText: true,
                // counted in the decoration: 0/16
                maxLength: 16,
                onChanged: (text) => setState(() => _password = text),
                decoration: InputDecoration(
                  labelText: 'Password',
                  errorText: _password.isNotEmpty && _password.characterCount < 8
                      ? 'at least 8 chars'
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| border | outline, underline, none | outline |
| filled | on, off | false |
| enabled | on, off | true |

## TextArea

Lines of text to edit, wrapped to the width: Enter breaks a line, the area grows from its least lines to its most, then scrolls.

API: [`TextArea`](https://pub.dev/documentation/twk/latest/twk/TextArea-class.html).

### Code

```dart
final _controller = TextEditingController(
  text: 'Notes wrap at the width of the area, between words.\n'
      'Enter breaks a line.',
);

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      SizedBox(
        width: 40,
        // the border primary while the focus is in it
        child: FocusBuilder(
          builder: (context, hasFocus, area) => Box(
            border: .all(
              type: .rounded,
              style: hasFocus ? theme.primary : theme.border,
            ),
            child: area,
          ),
          child: TextArea(
            controller: _controller,
            placeholder: 'notes',
            minLines: 3,
            maxLines: 6,
          ),
        ),
      ),
      Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => Text(_where(), style: theme.muted),
          ),
        ],
      ),
    ],
  );
}

/// Where the caret is: its line of the lines there are, and its
/// column, in characters.
String _where() {
  final text = _controller.text;
  final before = text.substring(0, _controller.selection.extentOffset);
  final line = '\n'.allMatches(before).length + 1;
  final lines = '\n'.allMatches(text).length + 1;
  final column = before.substring(before.lastIndexOf('\n') + 1);
  return 'line $line of $lines, column ${column.characterCount + 1}';
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| min lines | 1, 3 | 3 |
| max lines | none, 3, 6 | 6 |
| enter | breaks the line, submits | breaks the line |
| cursor | bar, block, underline, terminal | bar |
| blinking | on, off | false |
| read only | on, off | false |
| enabled | on, off | true |

## Autocomplete

Suggestions under a field as one types, after a trigger or for the whole text: Up and Down pick one, Enter or Tab puts it in.

API: [`Autocomplete`](https://pub.dev/documentation/twk/latest/twk/Autocomplete-class.html).

### Code

```dart
final _controller = TextEditingController();
String? _chosen;

static const _commands = {
  'help': 'the keys',
  'open': 'a file',
  'quit': 'the app',
  'save': 'the file',
  'search': 'in the files',
  'settings': 'of the app',
  'share': 'a link',
  'sort': 'the lines',
};

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      // the suggestions show under the box, from its left edge
      Autocomplete(
        controller: _controller,
        trigger: '/',
        suggestions: (query) => [
          for (final MapEntry(key: command, value: detail) in _commands.entries)
            if (fuzzyMatch(query, command) != null)
              Suggestion(command, detail: detail),
        ],
        onSelected: (suggestion) => setState(() => _chosen = suggestion.text),
        child: SizedBox(
          width: 30,
          // the border primary while the focus is in it
          child: FocusBuilder(
            builder: (context, hasFocus, field) => Box(
              border: .all(
                type: .rounded,
                style: hasFocus ? theme.primary : theme.border,
              ),
              child: field,
            ),
            child: TextField(
              controller: _controller,
              placeholder: '/ and a command',
            ),
          ),
        ),
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
| trigger | /, none | / |
| rows | 8, 4 | 8 |
| popup look | raised, bordered | raised |
