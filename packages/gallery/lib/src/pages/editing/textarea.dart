// The TextArea page.
part of 'editing.dart';

/// The TextArea page's `minLines` option.
const _textareaMinLines = ChoiceOption<int>(
  'minLines',
  'min lines',
  values: [1, 3],
  initial: 3,
);

/// The TextArea page's `maxLines` option.
const _textareaMaxLines = ChoiceOption<int?>(
  'maxLines',
  'max lines',
  values: [null, 3, 6],
  labels: ['none', '3', '6'],
  initial: 6,
);

/// The TextArea page's `enter` option.
const _textareaEnter = ChoiceOption<String>(
  'enter',
  'enter',
  values: ['newline', 'submit'],
  labels: ['breaks the line', 'submits'],
);

/// The TextArea page's `readOnly` option.
const _textareaReadOnly = SwitchOption('readOnly', 'read only');

/// The TextArea page's `enabled` option.
const _textareaEnabled = SwitchOption(
  'enabled',
  'enabled',
  initial: true,
);

final _textareaPage = GalleryPage(
  group: _group,
  title: 'TextArea',
  options: const [
    _textareaMinLines,
    _textareaMaxLines,
    _textareaEnter,
    ..._cursorOptions,
    _textareaReadOnly,
    _textareaEnabled,
  ],
  build: (context, o) => _Area(
    minLines: o(_textareaMinLines),
    maxLines: o(_textareaMaxLines),
    submit: o(_textareaEnter) == 'submit',
    cursor: _shapeOf(o),
    readOnly: o(_textareaReadOnly),
    enabled: o(_textareaEnabled),
  ),
  code: (o) {
    final submit = o(_textareaEnter) == 'submit';
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
      '    spacing: 1,',
      '    children: [',
      '      SizedBox(',
      '        width: 40,',
      ..._focusBox('        ', 'area'),
      '          child: TextArea(',
      '            controller: _controller,',
      "            placeholder: 'notes',",
      if (o(_textareaMinLines) != 1)
        '            minLines: ${o.nameOf(_textareaMinLines)},',
      if (o(_textareaMaxLines) != null)
        '            maxLines: ${o.nameOf(_textareaMaxLines)},',
      ..._shapeArg(o, '            '),
      if (o(_textareaReadOnly)) '            readOnly: true,',
      if (!o(_textareaEnabled)) '            enabled: false,',
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
);

const _notes =
    'Notes wrap at the width of the area, between words.\n'
    'Enter breaks a line.';

const _areaSubmitLine =
    '            onSubmitted: (text) => setState(() => _submitted = text),';

const _whereLine =
    '            builder: (context, _) => Text(_where(), style: theme.muted),';

const _beforeLine =
    '  final before = text.substring(0, _controller.selection.extentOffset);';

const _returnLine =
    r"  return 'line $line of $lines, column ${column.characterCount + 1}';";

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

final class _AreaState extends State<_Area> with KeptState {
  late final TextEditingController _controller = keptAt(
    context,
    'controller',
    () => TextEditingController(text: _notes),
  );
  String? get _submitted => kept['submitted'] as String?;
  int get _serial => kept['serial'] as int? ?? 0;

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
      spacing: 1,
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
                      kept['submitted'] = text;
                      kept['serial'] = _serial + 1;
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
