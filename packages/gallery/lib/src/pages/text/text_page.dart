// The Text page.
part of 'text.dart';

final _textPage = GalleryPage(
  group: 'Text',
  title: 'Text',
  options: [
    const ChoiceOption(
      'wrap',
      'wrap',
      values: ['word', 'grapheme', 'none'],
    ),
    const ChoiceOption(
      'overflow',
      'overflow',
      values: ['clip', 'ellipsis', 'ellipsisStart', 'ellipsisMiddle'],
      initial: 'ellipsis',
    ),
    const ChoiceOption(
      'align',
      'align',
      values: ['left', 'center', 'right', 'justify'],
    ),
    const ChoiceOption(
      'lines',
      'max lines',
      values: [null, 3, 1],
      labels: ['all', '3', '1'],
    ),
    SliderOption(
      'width',
      'width',
      min: 14,
      max: 50,
      initial: 32,
      format: (v) => '$v cells',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    return SizedBox(
      width: o.number('width').toInt(),
      child: Box(
        border: Border.all(type: BorderType.rounded, style: theme.border),
        child: Text(
          _sample,
          wrap: TextWrap.values.byName(o.choice('wrap')),
          overflow: TextOverflow.values.byName(o.choice('overflow')),
          align: TextAlign.values.byName(o.choice('align')),
          maxLines: o.choice<int?>('lines'),
        ),
      ),
    );
  },
  code: (o) => [
    'final theme = Theme.of(context);',
    'return SizedBox(',
    '  width: ${o.label('width')},',
    '  child: Box(',
    '    border: .all(type: .rounded, style: theme.border),',
    '    child: Text(',
    "      'Terminals draw text in a grid of cells. A paragraph breaks its '",
    "      'lines between words to fit its width; wide characters, 漢字 and '",
    "      '🙂, take two cells each.',",
    '      wrap: .${o.label('wrap')},',
    '      overflow: .${o.label('overflow')},',
    '      align: .${o.label('align')},',
    if (o['lines'] != null) '      maxLines: ${o.label('lines')},',
    '    ),',
    '  ),',
    ');',
  ].join('\n'),
);

const _sample =
    'Terminals draw text in a grid of cells. A paragraph breaks its lines '
    'between words to fit its width; wide characters, 漢字 and 🙂, take two '
    'cells each.';
