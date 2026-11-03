// The TextField page.
part of 'editing.dart';

/// The TextField page's `obscure` option.
const _textfieldObscure = SwitchOption('obscure', 'obscured');

/// The TextField page's `maxLength` option.
const _textfieldMaxLength = ChoiceOption<int?>(
  'maxLength',
  'max length',
  values: [null, 8],
  labels: ['none', '8'],
);

/// The TextField page's `align` option.
const _textfieldAlign = ChoiceOption<String>(
  'align',
  'text align',
  values: ['left', 'center', 'right', 'start', 'end'],
);

/// The TextField page's `readOnly` option.
const _textfieldReadOnly = SwitchOption('readOnly', 'read only');

/// The TextField page's `enabled` option.
const _textfieldEnabled = SwitchOption(
  'enabled',
  'enabled',
  initial: true,
);

/// The TextField page's `paste` option.
const _textfieldPaste = ChoiceOption<String>(
  'paste',
  'a paste',
  values: ['goes in', 'taken'],
);

final _textfieldPage = GalleryPage(
  group: _group,
  title: 'TextField',
  options: const [
    _textfieldObscure,
    _textfieldMaxLength,
    ..._cursorOptions,
    _textfieldAlign,
    _textfieldReadOnly,
    _textfieldEnabled,
    // what onPaste answers: false, the paste goes in; true, it took it
    _textfieldPaste,
  ],
  build: (context, o) => _Field(
    obscure: o(_textfieldObscure),
    maxLength: o(_textfieldMaxLength),
    cursor: _shapeOf(o),
    align: TextAlign.values.byName(o(_textfieldAlign)),
    readOnly: o(_textfieldReadOnly),
    enabled: o(_textfieldEnabled),
    takePaste: o(_textfieldPaste) == 'taken',
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
    if (o(_textfieldObscure)) '            obscureText: true,',
    if (o(_textfieldMaxLength) != null)
      '            maxLength: ${o.nameOf(_textfieldMaxLength)},',
    ..._shapeArg(o, '            '),
    if (o.nameOf(_textfieldAlign) != 'left')
      '            textAlign: .${o.nameOf(_textfieldAlign)},',
    if (o(_textfieldReadOnly)) '            readOnly: true,',
    if (!o(_textfieldEnabled)) '            enabled: false,',
    '            onSubmitted: (text) => setState(() => _submitted = text),',
    '            onEditingComplete: () =>',
    "                setState(() => _heard = 'editing complete'),",
    '            onPaste: (text) {',
    '              setState(',
    _pastedLine,
    '              );',
    '              return ${o(_textfieldPaste) == 'taken'};',
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
    if (o(_textfieldObscure))
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
);

// The Code's lines too long to write here on one.
const _pastedLine =
    "                () => _heard = 'a paste of "
    r"${text.characterCount} characters',";

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

final class _FieldState extends State<_Field> with KeptState {
  late final TextEditingController _controller = keptAt(
    context,
    'controller',
    TextEditingController.new,
  );
  String get _submitted => kept['submitted'] as String? ?? '';
  int get _serial => kept['serial'] as int? ?? 0;
  String get _heard => kept['heard'] as String? ?? '';
  int get _heardSerial => kept['heardSerial'] as int? ?? 0;

  void _hear(String what) => setState(() {
    kept['heard'] = what;
    kept['heardSerial'] = _heardSerial + 1;
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
                kept['submitted'] = text;
                kept['serial'] = _serial + 1;
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
