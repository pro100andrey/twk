// The Editing group of the gallery.
import 'package:twk/twk.dart';

import '../page.dart';
import 'common.dart';
import 'controls.dart' show popupLookArg, popupLookOf, popupLookOption;

/// The options of a field's cursor: its shape, the terminal's own among
/// them, and whether it blinks.
const List<PageOption> _cursorOptions = [
  ChoiceOption(
    'cursor',
    'cursor',
    values: ['bar', 'block', 'underline', 'terminalDefault'],
    labels: ['bar', 'block', 'underline', 'terminal'],
  ),
  SwitchOption('blink', 'blinking', disabled: _terminalCursor),
];

/// Whether the cursor of [o] is the terminal's own, which blinks as the
/// terminal says.
bool _terminalCursor(Options o) =>
    o.choice<String>('cursor') == 'terminalDefault';

/// The cursor shape of [o].
CursorShape _shapeOf(Options o) {
  final shape = o.choice<String>('cursor');
  if (_terminalCursor(o) || !o.flag('blink')) {
    return CursorShape.values.byName(shape);
  }
  return CursorShape.values.byName(
    'blinking${shape[0].toUpperCase()}${shape.substring(1)}',
  );
}

/// The Code's `cursorShape:` line, [pad] columns in, where it is not the
/// default.
List<String> _shapeArg(Options o, String pad) => [
  if (_shapeOf(o) != CursorShape.bar)
    '${pad}cursorShape: .${_shapeOf(o).name},',
];

/// The Code of a Box whose border is primary while the focus is in
/// [child], a FocusBuilder's, [pad] columns in.
List<String> _focusBox(String pad, String child) => [
  '$pad// the border primary while the focus is in it',
  '${pad}child: FocusBuilder(',
  '$pad  builder: (context, hasFocus, $child) => Box(',
  '$pad    border: .all(',
  '$pad      type: .rounded,',
  '$pad      style: hasFocus ? theme.primary : theme.border,',
  '$pad    ),',
  '$pad    child: $child,',
  '$pad  ),',
];

/// [child] in a rounded box, its border primary while the focus is in it.
Widget _focusBoxed(Widget child) => FocusBuilder(
  builder: (context, hasFocus, child) {
    final theme = Theme.of(context);
    return Box(
      border: Border.all(
        type: BorderType.rounded,
        style: hasFocus ? theme.primary : theme.border,
      ),
      child: child,
    );
  },
  child: child,
);

/// [key] of the page's state, made by [create] the first time: what
/// outlives a visit to another page.
T _kept<T>(BuildContext context, String key, T Function() create) =>
    PageControl.of(context).state.putIfAbsent(key, create) as T;

const _notes =
    'Notes wrap at the width of the area, between words.\n'
    'Enter breaks a line.';

const _commands = {
  'help': 'the keys',
  'open': 'a file',
  'quit': 'the app',
  'save': 'the file',
  'search': 'in the files',
  'settings': 'of the app',
  'share': 'a link',
  'sort': 'the lines',
};

const _fruit = [
  'apple', 'apricot', 'avocado', 'banana', 'blackberry', //
  'blueberry', 'cherry', 'grape', 'lemon', 'lime',
  'mango', 'orange', 'peach', 'pear', 'plum',
];

// The Code's lines too long to write here on one.
const _pastedLine =
    "                () => _heard = 'a paste of "
    r"${text.characterCount} characters',";
const _areaSubmitLine =
    '            onSubmitted: (text) => setState(() => _submitted = text),';
const _whereLine =
    '            builder: (context, _) => Text(_where(), style: theme.muted),';
const _beforeLine =
    '  final before = text.substring(0, _controller.selection.extentOffset);';
const _returnLine =
    r"  return 'line $line of $lines, column ${column.characterCount + 1}';";
const _fruitLine =
    '            if (fuzzyMatch(query, fruit) != null) Suggestion(fruit),';
const _commandsLine =
    '          for (final MapEntry(key: command, value: detail) in '
    '_commands.entries)';
const _passwordLine =
    '                  errorText: _password.isNotEmpty && '
    '_password.characterCount < 8';
const _themeChangedLine =
    '              onChanged: (theme) => setState(() => _theme = theme),';
const _passwordChangedLine =
    '                onChanged: (text) => setState(() => _password = text),';
const _selectedLine =
    '        onSelected: (suggestion) => '
    'setState(() => _chosen = suggestion.text),';

/// The pages of the Editing group that draw.
final editingPages = [
  GalleryPage(
    group: 'Editing',
    title: 'TextField',
    options: const [
      SwitchOption('obscure', 'obscured'),
      ChoiceOption(
        'maxLength',
        'max length',
        values: [null, 8],
        labels: ['none', '8'],
      ),
      ..._cursorOptions,
      ChoiceOption(
        'align',
        'text align',
        values: ['left', 'center', 'right', 'start', 'end'],
      ),
      SwitchOption('readOnly', 'read only'),
      SwitchOption('enabled', 'enabled', initial: true),
      // what onPaste answers: false, the paste goes in; true, it took it
      ChoiceOption('paste', 'a paste', values: ['goes in', 'taken']),
    ],
    build: (context, o) => _Field(
      obscure: o.flag('obscure'),
      maxLength: o.choice('maxLength'),
      cursor: _shapeOf(o),
      align: TextAlign.values.byName(o.choice('align')),
      readOnly: o.flag('readOnly'),
      enabled: o.flag('enabled'),
      takePaste: o.choice<String>('paste') == 'taken',
    ),
    code: (o) => [
      "var _submitted = '';",
      "var _heard = '';",
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      SizedBox(',
      '        width: 30,',
      ..._focusBox('        ', 'field'),
      '          child: TextField(',
      "            placeholder: 'type here',",
      if (o.flag('obscure')) '            obscureText: true,',
      if (o['maxLength'] != null)
        '            maxLength: ${o.label('maxLength')},',
      ..._shapeArg(o, '            '),
      if (o.label('align') != 'left')
        '            textAlign: .${o.label('align')},',
      if (o.flag('readOnly')) '            readOnly: true,',
      if (!o.flag('enabled')) '            enabled: false,',
      '            onSubmitted: (text) => setState(() => _submitted = text),',
      '            onEditingComplete: () =>',
      "                setState(() => _heard = 'editing complete'),",
      '            onPaste: (text) {',
      '              setState(',
      _pastedLine,
      '              );',
      '              return ${o.choice<String>('paste') == 'taken'};',
      '            },',
      '          ),',
      '        ),',
      '      ),',
      '      Column(',
      '        mainAxisSize: .min,',
      '        crossAxisAlignment: .start,',
      '        children: [',
      '          Text.rich([',
      "            Span('submitted: ', theme.muted),",
      '            if (_submitted.isEmpty)',
      "              Span('nothing', theme.muted)",
      '            else',
      if (o.flag('obscure'))
        "              Span('•' * _submitted.characterCount),"
      else
        '              Span(_submitted),',
      '          ]),',
      '          Text.rich([',
      "            Span('heard: ', theme.muted),",
      '            if (_heard.isEmpty)',
      "              Span('nothing', theme.muted)",
      '            else',
      '              Span(_heard),',
      '          ]),',
      '        ],',
      '      ),',
      '    ],',
      '  );',
      '}',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Editing',
    title: 'InputDecoration',
    options: const [
      ChoiceOption(
        'border',
        'border',
        values: ['outline', 'underline', 'none'],
      ),
      SwitchOption('filled', 'filled'),
      SwitchOption('enabled', 'enabled', initial: true),
    ],
    build: (context, o) => _Decorated(
      border: switch (o.choice<String>('border')) {
        'outline' => const OutlineInputBorder(),
        'underline' => const UnderlineInputBorder(),
        _ => InputBorder.none,
      },
      filled: o.flag('filled'),
      enabled: o.flag('enabled'),
    ),
    code: (o) {
      final border = switch (o.choice<String>('border')) {
        'outline' => 'OutlineInputBorder()',
        'underline' => null,
        _ => 'InputBorder.none',
      };
      final on = o.flag('enabled');
      // the parts each decoration ends with, [pad] columns in (const where
      // the decoration is not)
      List<String> rest(String pad, {bool constant = true}) {
        final made = constant || border == null || border.startsWith('Input');
        return [
          if (border != null) '${pad}border: ${made ? '' : 'const '}$border,',
          if (o.flag('filled')) '${pad}filled: true,',
        ];
      }

      List<String> enabled(String pad) => [if (!on) '${pad}enabled: false,'];
      return [
        "var _theme = 'dark';",
        "var _password = '';",
        '',
        '@override',
        'Widget build(BuildContext context) {',
        '  return Row(',
        '    mainAxisSize: .min,',
        '    crossAxisAlignment: .start,',
        '    gap: 2,',
        '    children: [',
        '      SizedBox(',
        '        width: 24,',
        '        child: Column(',
        '          mainAxisSize: .min,',
        '          gap: 1,',
        '          children: [',
        '            Select<String>(',
        '              choices: const [',
        "                Choice('dark', 'Dark'),",
        "                Choice('light', 'Light'),",
        "                Choice('nord', 'Nord'),",
        '              ],',
        '              value: _theme,',
        if (on) _themeChangedLine else '              onChanged: null,',
        '              decoration: const InputDecoration(',
        "                icon: Text('◐'),",
        "                labelText: 'Theme',",
        "                helperText: 'Enter opens it',",
        ...rest('                '),
        '              ),',
        '            ),',
        '            TextField(',
        "              placeholder: 'twk',",
        ...enabled('              '),
        '              decoration: const InputDecoration(',
        "                labelText: 'Site',",
        "                prefixText: 'https://',",
        "                suffixText: '.dev',",
        "                helperText: 'where it lives',",
        ...rest('                '),
        '              ),',
        '            ),',
        '          ],',
        '        ),',
        '      ),',
        '      SizedBox(',
        '        width: 24,',
        '        child: Column(',
        '          mainAxisSize: .min,',
        '          gap: 1,',
        '          children: [',
        '            TextField(',
        "              placeholder: 'files, commands',",
        ...enabled('              '),
        '              decoration: const InputDecoration(',
        "                labelText: 'Search',",
        "                prefixIcon: Text('⌕'),",
        "                suffixIcon: Text('↵'),",
        "                helperText: 'by name',",
        ...rest('                '),
        '              ),',
        '            ),',
        '            // only the field builds again as its text changes',
        '            StatefulBuilder(',
        '              builder: (context, setState) => TextField(',
        "                placeholder: 'secret',",
        '                obscureText: true,',
        '                // counted in the decoration: 0/16',
        '                maxLength: 16,',
        ...enabled('                '),
        _passwordChangedLine,
        '                decoration: InputDecoration(',
        "                  labelText: 'Password',",
        _passwordLine,
        "                      ? 'at least 8 chars'",
        '                      : null,',
        ...rest('                  ', constant: false),
        '                ),',
        '              ),',
        '            ),',
        '          ],',
        '        ),',
        '      ),',
        '    ],',
        '  );',
        '}',
      ].join('\n');
    },
  ),
  GalleryPage(
    group: 'Editing',
    title: 'TextArea',
    options: const [
      ChoiceOption('minLines', 'min lines', values: [1, 3], initial: 3),
      ChoiceOption(
        'maxLines',
        'max lines',
        values: [null, 3, 6],
        labels: ['none', '3', '6'],
        initial: 6,
      ),
      ChoiceOption(
        'enter',
        'enter',
        values: ['newline', 'submit'],
        labels: ['breaks the line', 'submits'],
      ),
      ..._cursorOptions,
      SwitchOption('readOnly', 'read only'),
      SwitchOption('enabled', 'enabled', initial: true),
    ],
    build: (context, o) => _Area(
      minLines: o.choice('minLines'),
      maxLines: o.choice('maxLines'),
      submit: o.choice<String>('enter') == 'submit',
      cursor: _shapeOf(o),
      readOnly: o.flag('readOnly'),
      enabled: o.flag('enabled'),
    ),
    code: (o) {
      final submit = o.choice<String>('enter') == 'submit';
      return [
        'final _controller = TextEditingController(',
        r"  text: 'Notes wrap at the width of the area, between words.\n'",
        "      'Enter breaks a line.',",
        ');',
        if (submit) 'String? _submitted;',
        '',
        '@override',
        'void dispose() {',
        '  _controller.dispose();',
        '  super.dispose();',
        '}',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        '  final theme = Theme.of(context);',
        '  return Column(',
        '    mainAxisSize: .min,',
        '    crossAxisAlignment: .start,',
        '    gap: 1,',
        '    children: [',
        '      SizedBox(',
        '        width: 40,',
        ..._focusBox('        ', 'area'),
        '          child: TextArea(',
        '            controller: _controller,',
        "            placeholder: 'notes',",
        if (o['minLines'] != 1) '            minLines: ${o.label('minLines')},',
        if (o['maxLines'] != null)
          '            maxLines: ${o.label('maxLines')},',
        ..._shapeArg(o, '            '),
        if (o.flag('readOnly')) '            readOnly: true,',
        if (!o.flag('enabled')) '            enabled: false,',
        if (submit) _areaSubmitLine,
        '          ),',
        '        ),',
        '      ),',
        '      Column(',
        '        mainAxisSize: .min,',
        '        crossAxisAlignment: .start,',
        '        children: [',
        '          ListenableBuilder(',
        '            listenable: _controller,',
        _whereLine,
        '          ),',
        if (submit) ...[
          '          Text.rich([',
          "            Span('submitted: ', theme.muted),",
          '            if (_submitted case final text?)',
          '              Span(',
          r"                '${text.split('\n').length} lines, '",
          r"                '${text.characterCount} characters',",
          '              )',
          '            else',
          "              Span('nothing', theme.muted),",
          '          ]),',
        ],
        '        ],',
        '      ),',
        '    ],',
        '  );',
        '}',
        '',
        '/// Where the caret is: its line of the lines there are, and its',
        '/// column, in characters.',
        'String _where() {',
        '  final text = _controller.text;',
        _beforeLine,
        r"  final line = '\n'.allMatches(before).length + 1;",
        r"  final lines = '\n'.allMatches(text).length + 1;",
        r"  final column = before.substring(before.lastIndexOf('\n') + 1);",
        _returnLine,
        '}',
      ].join('\n');
    },
  ),
  GalleryPage(
    group: 'Editing',
    title: 'Autocomplete',
    options: [
      const ChoiceOption('trigger', 'trigger', values: ['/', 'none']),
      const ChoiceOption('rows', 'rows', values: [8, 4]),
      popupLookOption(),
    ],
    build: (context, o) => _Complete(
      fruit: o.choice<String>('trigger') == 'none',
      rows: o.choice('rows'),
      popupLook: popupLookOf(o),
    ),
    code: (o) {
      final fruit = o.choice<String>('trigger') == 'none';
      final placeholder = fruit ? 'a fruit' : '/ and a command';
      return [
        'final _controller = TextEditingController();',
        'String? _chosen;',
        '',
        if (fruit) ...[
          'static const _fruit = [',
          for (var k = 0; k < 15; k += 5)
            '  ${_fruit.sublist(k, k + 5).map((f) => "'$f'").join(', ')},',
          '];',
        ] else ...[
          'static const _commands = {',
          for (final MapEntry(:key, :value) in _commands.entries)
            "  '$key': '$value',",
          '};',
        ],
        '',
        '@override',
        'void dispose() {',
        '  _controller.dispose();',
        '  super.dispose();',
        '}',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        '  final theme = Theme.of(context);',
        '  return Column(',
        '    mainAxisSize: .min,',
        '    crossAxisAlignment: .start,',
        '    gap: 1,',
        '    children: [',
        '      // the suggestions show under the box, from its left edge',
        '      Autocomplete(',
        '        controller: _controller,',
        if (!fruit) "        trigger: '/',",
        if (o['rows'] != 8) '        rows: ${o.label('rows')},',
        ...popupLookArg(o, '        '),
        '        suggestions: (query) => [',
        if (fruit) ...[
          '          for (final fruit in _fruit)',
          _fruitLine,
        ] else ...[
          _commandsLine,
          '            if (fuzzyMatch(query, command) != null)',
          '              Suggestion(command, detail: detail),',
        ],
        '        ],',
        _selectedLine,
        '        child: SizedBox(',
        '          width: 30,',
        ..._focusBox('          ', 'field'),
        '            child: TextField(',
        '              controller: _controller,',
        "              placeholder: '$placeholder',",
        '            ),',
        '          ),',
        '        ),',
        '      ),',
        '      Text.rich([',
        "        Span('chosen: ', theme.muted),",
        '        if (_chosen case final chosen?)',
        '          Span(chosen)',
        '        else',
        "          Span('nothing', theme.muted),",
        '      ]),',
        '    ],',
        '  );',
        '}',
      ].join('\n');
    },
  ),
];

/// A field in a box, what was submitted from it, and what it heard last:
/// its onEditingComplete or its onPaste.
final class _Field extends StatefulWidget {
  const _Field({
    required this.obscure,
    required this.maxLength,
    required this.cursor,
    required this.align,
    required this.readOnly,
    required this.enabled,
    required this.takePaste,
  });

  final bool obscure;
  final int? maxLength;
  final CursorShape cursor;
  final TextAlign align;
  final bool readOnly;
  final bool enabled;

  /// What onPaste answers: whether it took the paste.
  final bool takePaste;

  @override
  State<_Field> createState() => _FieldState();
}

final class _FieldState extends State<_Field> {
  late final Map<String, Object?> _state = PageControl.of(context).state;
  late final TextEditingController _controller = _kept(
    context,
    'controller',
    TextEditingController.new,
  );
  String get _submitted => _state['submitted'] as String? ?? '';
  int get _serial => _state['serial'] as int? ?? 0;
  String get _heard => _state['heard'] as String? ?? '';
  int get _heardSerial => _state['heardSerial'] as int? ?? 0;

  void _hear(String what) => setState(() {
    _state['heard'] = what;
    _state['heardSerial'] = _heardSerial + 1;
  });

  @override
  Widget build(BuildContext context) {
    final shown = widget.obscure ? '•' * _submitted.characterCount : _submitted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SizedBox(
          width: 30,
          child: _focusBoxed(
            TextField(
              controller: _controller,
              placeholder: 'type here',
              obscureText: widget.obscure,
              maxLength: widget.maxLength,
              cursorShape: widget.cursor,
              textAlign: widget.align,
              readOnly: widget.readOnly,
              enabled: widget.enabled,
              onSubmitted: (text) => setState(() {
                _state['submitted'] = text;
                _state['serial'] = _serial + 1;
              }),
              onEditingComplete: () => _hear('editing complete'),
              onPaste: (text) {
                _hear('a paste of ${text.characterCount} characters');
                return widget.takePaste;
              },
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LitLine([
              ('submitted: ', true),
              if (_submitted.isEmpty) ('nothing', true) else (shown, false),
            ], serial: _serial),
            LitLine([
              ('heard: ', true),
              if (_heard.isEmpty) ('nothing', true) else (_heard, false),
            ], serial: _heardSerial),
          ],
        ),
      ],
    );
  }
}

/// Four fields in [border], each decorated in its own way: a Select
/// with an icon and a helper, a prefix and a suffix, icons inside, and a
/// counter and an error, its field built again alone.
final class _Decorated extends StatefulWidget {
  const _Decorated({
    required this.border,
    required this.filled,
    required this.enabled,
  });

  final InputBorder border;
  final bool filled;
  final bool enabled;

  @override
  State<_Decorated> createState() => _DecoratedState();
}

final class _DecoratedState extends State<_Decorated> {
  late final Map<String, Object?> _state = PageControl.of(context).state;
  String get _theme => _state['theme'] as String? ?? 'dark';
  String get _password => _state['passwordText'] as String? ?? '';

  /// The field of [key], its text kept from visit to visit.
  TextEditingController _controller(String key) =>
      _kept(context, key, TextEditingController.new);

  @override
  Widget build(BuildContext context) {
    final border = widget.border;
    final filled = widget.filled;
    final enabled = widget.enabled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 2,
      children: [
        SizedBox(
          width: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            gap: 1,
            children: [
              Select<String>(
                choices: const [
                  Choice('dark', 'Dark'),
                  Choice('light', 'Light'),
                  Choice('nord', 'Nord'),
                ],
                value: _theme,
                onChanged: enabled
                    ? (theme) => setState(() => _state['theme'] = theme)
                    : null,
                decoration: InputDecoration(
                  icon: const Text('◐'),
                  labelText: 'Theme',
                  helperText: 'Enter opens it',
                  border: border,
                  filled: filled,
                ),
              ),
              TextField(
                controller: _controller('site'),
                placeholder: 'twk',
                enabled: enabled,
                decoration: InputDecoration(
                  labelText: 'Site',
                  prefixText: 'https://',
                  suffixText: '.dev',
                  helperText: 'where it lives',
                  border: border,
                  filled: filled,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            gap: 1,
            children: [
              TextField(
                controller: _controller('search'),
                placeholder: 'files, commands',
                enabled: enabled,
                decoration: InputDecoration(
                  labelText: 'Search',
                  prefixIcon: const Text('⌕'),
                  suffixIcon: const Text('↵'),
                  helperText: 'by name',
                  border: border,
                  filled: filled,
                ),
              ),
              StatefulBuilder(
                builder: (context, setState) {
                  final password = _password;
                  return TextField(
                    controller: _controller('password'),
                    placeholder: 'secret',
                    obscureText: true,
                    maxLength: 16,
                    enabled: enabled,
                    onChanged: (text) =>
                        setState(() => _state['passwordText'] = text),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      errorText:
                          password.isNotEmpty && password.characterCount < 8
                          ? 'at least 8 chars'
                          : null,
                      border: border,
                      filled: filled,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// An area in a box, where its caret is, and what was submitted from it.
final class _Area extends StatefulWidget {
  const _Area({
    required this.minLines,
    required this.maxLines,
    required this.submit,
    required this.cursor,
    required this.readOnly,
    required this.enabled,
  });

  final int minLines;
  final int? maxLines;
  final bool submit;
  final CursorShape cursor;
  final bool readOnly;
  final bool enabled;

  @override
  State<_Area> createState() => _AreaState();
}

final class _AreaState extends State<_Area> {
  late final Map<String, Object?> _state = PageControl.of(context).state;
  late final TextEditingController _controller = _kept(
    context,
    'controller',
    () => TextEditingController(text: _notes),
  );
  String? get _submitted => _state['submitted'] as String?;
  int get _serial => _state['serial'] as int? ?? 0;

  /// Where the caret is: its line of the lines there are, and its column,
  /// in characters.
  String _where() {
    final text = _controller.text;
    final before = text.substring(0, _controller.selection.extentOffset);
    final line = '\n'.allMatches(before).length + 1;
    final lines = '\n'.allMatches(text).length + 1;
    final column = before.substring(before.lastIndexOf('\n') + 1);
    return 'line $line of $lines, column ${column.characterCount + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final submitted = _submitted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SizedBox(
          width: 40,
          child: _focusBoxed(
            TextArea(
              controller: _controller,
              placeholder: 'notes',
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              cursorShape: widget.cursor,
              readOnly: widget.readOnly,
              enabled: widget.enabled,
              onSubmitted: widget.submit
                  ? (text) => setState(() {
                      _state['submitted'] = text;
                      _state['serial'] = _serial + 1;
                    })
                  : null,
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => Text(_where(), style: theme.muted),
            ),
            if (widget.submit)
              LitLine([
                ('submitted: ', true),
                if (submitted == null)
                  ('nothing', true)
                else
                  (
                    '${submitted.split('\n').length} lines, '
                        '${submitted.characterCount} characters',
                    false,
                  ),
              ], serial: _serial),
          ],
        ),
      ],
    );
  }
}

/// A field that suggests commands after `/`, or fruit, and what was
/// chosen.
final class _Complete extends StatefulWidget {
  const _Complete({
    required this.fruit,
    required this.rows,
    required this.popupLook,
  });

  final bool fruit;
  final int rows;
  final PanelLook popupLook;

  @override
  State<_Complete> createState() => _CompleteState();
}

final class _CompleteState extends State<_Complete> {
  late final Map<String, Object?> _state = PageControl.of(context).state;
  late final TextEditingController _controller = _kept(
    context,
    'controller',
    TextEditingController.new,
  );
  String? get _chosen => _state['chosen'] as String?;
  int get _serial => _state['serial'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Autocomplete(
          controller: _controller,
          trigger: widget.fruit ? null : '/',
          rows: widget.rows,
          popupLook: widget.popupLook,
          suggestions: (query) => widget.fruit
              ? [
                  for (final fruit in _fruit)
                    if (fuzzyMatch(query, fruit) != null) Suggestion(fruit),
                ]
              : [
                  for (final MapEntry(key: command, value: detail)
                      in _commands.entries)
                    if (fuzzyMatch(query, command) != null)
                      Suggestion(command, detail: detail),
                ],
          onSelected: (suggestion) => setState(() {
            _state['chosen'] = suggestion.text;
            _state['serial'] = _serial + 1;
          }),
          child: SizedBox(
            width: 30,
            child: _focusBoxed(
              TextField(
                controller: _controller,
                placeholder: widget.fruit ? 'a fruit' : '/ and a command',
              ),
            ),
          ),
        ),
        LitLine([
          ('chosen: ', true),
          if (chosen == null) ('nothing', true) else (chosen, false),
        ], serial: _serial),
      ],
    );
  }
}
