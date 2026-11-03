// The DescriptionList page.
part of 'data.dart';

/// The rows of the DescriptionList page, as the Code writes them: a term
/// and its value, a group's title (no value), or the term of the status
/// and of the memory, whose values are widgets.
const List<(String, String?)> _described = [
  ('Status', null),
  ('IP Address', '192.168.1.42'),
  ('Uptime', '3 days, 4 hours'),
  ('Image', 'twk/server:0.1.0'),
  ('Limits', ''),
  ('CPU', '2 cores'),
  ('Memory', null),
  ('Restart policy', 'unless stopped, 5 times at most in a minute'),
];

/// The DescriptionList page's `width` option.
final _descriptionListWidth = SliderOption(
  'width',
  'width',
  min: 20,
  max: 60,
  initial: 44,
  format: (v) => '$v cells',
);

/// The DescriptionList page's `align` option.
const _descriptionListAlign = ChoiceOption<String>(
  'align',
  'terms',
  values: ['left', 'center', 'right'],
);

/// The DescriptionList page's `separator` option.
const _descriptionListSeparator = ChoiceOption<String>(
  'separator',
  'separator',
  values: [':', ''],
  labels: ['colon', 'none'],
);

/// The DescriptionList page's `groups` option.
const _descriptionListGroups = SwitchOption(
  'groups',
  'groups',
  initial: true,
);

final _descriptionList = GalleryPage(
  group: _group,
  title: 'DescriptionList',
  options: [
    _descriptionListWidth,
    _descriptionListAlign,
    _descriptionListSeparator,
    _descriptionListGroups,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final groups = o(_descriptionListGroups);
    return SizedBox(
      width: o(_descriptionListWidth).toInt(),
      child: DescriptionList(
        termAlign: TextAlign.values.byName(o(_descriptionListAlign)),
        separator: o(_descriptionListSeparator),
        items: [
          for (final (term, value) in _described)
            switch ((term, value)) {
              ('Status', _) => DescriptionItem(
                'Status',
                Text.rich([
                  Span('● ', theme.success),
                  const Span('Running (healthy)'),
                ]),
              ),
              ('Memory', _) => const DescriptionItem(
                'Memory',
                ProgressBar(value: 0.25),
              ),
              (_, '') when groups => DescriptionItem.group(term),
              (_, '') => null,
              (_, final String v) => DescriptionItem.text(term, v),
              _ => null,
            },
        ].nonNulls.toList(),
      ),
    );
  },
  code: (o) {
    final align = o(_descriptionListAlign);
    final separator = o(_descriptionListSeparator);
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: ${o.nameOf(_descriptionListWidth)},',
      '  child: DescriptionList(',
      if (align != 'left') '    termAlign: .$align,',
      if (separator != ':') "    separator: '$separator',",
      '    items: [',
      for (final (term, value) in _described)
        ...switch ((term, value)) {
          ('Status', _) => [
            '      DescriptionItem(',
            "        'Status',",
            '        Text.rich([',
            "          Span('● ', theme.success),",
            "          const Span('Running (healthy)'),",
            '        ]),',
            '      ),',
          ],
          ('Memory', _) => [
            "      const DescriptionItem('Memory', ProgressBar(value: 0.25)),",
          ],
          (_, '') when o(_descriptionListGroups) => [
            "      const DescriptionItem.group('$term'),",
          ],
          (_, '') => const <String>[],
          (_, final String v) => _call(6, 'DescriptionItem.text', [
            "'$term'",
            "'$v'",
          ]),
          _ => const <String>[],
        },
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);

/// [call] as this group's Codes write it: to the whole 80 columns, a
/// comma after it.
List<String> _call(int indent, String head, List<String> args) =>
    call(indent, head, args, ',', width: 80);
