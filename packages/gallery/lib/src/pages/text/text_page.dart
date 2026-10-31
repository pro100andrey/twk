// The Text page.
part of 'text.dart';

/// The Text page's `wrap` option.
const _textWrap = ChoiceOption<String>(
  'wrap',
  'wrap',
  values: ['word', 'grapheme', 'none'],
);

/// The Text page's `overflow` option.
const _textOverflow = ChoiceOption<String>(
  'overflow',
  'overflow',
  values: ['clip', 'ellipsis', 'ellipsisStart', 'ellipsisMiddle'],
  initial: 'ellipsis',
);

/// The Text page's `align` option.
const _textAlign = ChoiceOption<String>(
  'align',
  'align',
  values: ['left', 'center', 'right', 'justify'],
);

/// The Text page's `lines` option.
const _textLines = ChoiceOption<int?>(
  'lines',
  'max lines',
  values: [null, 3, 1],
  labels: ['all', '3', '1'],
);

/// The Text page's `width` option.
final _textWidth = SliderOption(
  'width',
  'width',
  min: 14,
  max: 50,
  initial: 32,
  format: (v) => '$v cells',
);

final _textPage = GalleryPage(
  group: _group,
  title: 'Text',
  options: [
    _textWrap,
    _textOverflow,
    _textAlign,
    _textLines,
    _textWidth,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    return SizedBox(
      width: o(_textWidth).toInt(),
      child: Box(
        border: Border.all(type: BorderType.rounded, style: theme.border),
        child: Text(
          _sample,
          wrap: TextWrap.values.byName(o(_textWrap)),
          overflow: TextOverflow.values.byName(o(_textOverflow)),
          align: TextAlign.values.byName(o(_textAlign)),
          maxLines: o(_textLines),
        ),
      ),
    );
  },
  code: (o) => [
    'final theme = Theme.of(context);',
    'return SizedBox(',
    '  width: ${o.nameOf(_textWidth)},',
    '  child: Box(',
    '    border: .all(type: .rounded, style: theme.border),',
    '    child: Text(',
    "      'Terminals draw text in a grid of cells. A paragraph breaks its '",
    "      'lines between words to fit its width; wide characters, 漢字 and '",
    "      '🙂, take two cells each.',",
    '      wrap: .${o.nameOf(_textWrap)},',
    '      overflow: .${o.nameOf(_textOverflow)},',
    '      align: .${o.nameOf(_textAlign)},',
    if (o(_textLines) != null) '      maxLines: ${o.nameOf(_textLines)},',
    '    ),',
    '  ),',
    ');',
  ].join('\n'),
);

const _sample =
    'Terminals draw text in a grid of cells. A paragraph breaks its lines '
    'between words to fit its width; wide characters, 漢字 and 🙂, take two '
    'cells each.';
