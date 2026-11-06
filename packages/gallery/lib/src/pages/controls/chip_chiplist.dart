// The Chip, ChipList page.
part of 'controls.dart';

/// The tags of the Chip, ChipList page at first, and the tag that is not
/// pressable.
const _firstTags = [
  'dart',
  'tui',
  'terminal',
  'widgets',
  'beta',
  'mouse',
  'keyboard',
];

/// The Chip, ChipList page's `toggle` option.
const _chipsToggle = SwitchOption('toggle', 'toggle', initial: true);

/// The Chip, ChipList page's `remove` option.
const _chipsRemove = SwitchOption('remove', 'removable', initial: true);

/// The Chip, ChipList page's `width` option.
final _chipsWidth = SliderOption(
  'width',
  'width',
  min: 20,
  max: 50,
  initial: 34,
  format: (v) => '$v cells',
);

final _chipsPage = GalleryPage(
  group: _group,
  title: 'Chip, ChipList',
  options: [
    _chipsToggle,
    _chipsRemove,
    _chipsWidth,
  ],
  build: (context, o) => _Tags(
    toggle: o(_chipsToggle),
    remove: o(_chipsRemove),
    width: o(_chipsWidth).toInt(),
  ),
  code: (o) => [
    'static const _all = [',
    for (final t in _firstTags) "  '$t',",
    '];',
    '',
    'var _tags = _all;',
    "var _on = {'tui'};",
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  final shown = _on.where(_tags.contains);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    spacing: 1,',
    '    children: [',
    '      SizedBox(',
    '        width: ${o(_chipsWidth).toInt()},',
    '        child: ChipList<String>(',
    '          chips: [',
    "            for (final t in _tags) Choice(t, t, enabled: t != 'beta'),",
    '          ],',
    '          selected: _on,',
    if (o(_chipsToggle))
      '          onSelectionChanged: (now) => setState(() => _on = now),',
    if (o(_chipsRemove)) ...[
      '          onDeleted: (tag) {',
      '            setState(() => _tags = [..._tags]..remove(tag));',
      '          },',
    ],
    '        ),',
    '      ),',
    '      Text.rich([',
    "        Span('on: ', theme.muted),",
    '        if (shown.isEmpty)',
    "          Span('nothing', theme.muted)",
    '        else',
    "          Span(shown.join(', ')),",
    '      ]),',
    '      Button(',
    "        'Bring them back',",
    '        onPressed: _tags.length == _all.length',
    '            ? null',
    '            : () => setState(() => _tags = _all),',
    '      ),',
    '    ],',
    '  );',
    '}',
  ].join('\n'),
);

/// Tags that wrap in [width] cells: the chips of a ChipList, and a button
/// to bring back those removed.
final class _Tags extends StatefulWidget {
  const _Tags({
    required this.toggle,
    required this.remove,
    required this.width,
  });

  final bool toggle;
  final bool remove;
  final int width;

  @override
  State<_Tags> createState() => _TagsState();
}

final class _TagsState extends State<_Tags> with KeptState {
  @override
  Widget build(BuildContext context) {
    final tags = keptOr<List<String>>('tags', _firstTags);
    final on = keptOr<Set<String>>('on', {'tui'});
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        SizedBox(
          width: widget.width,
          child: ChipList<String>(
            chips: [
              for (final t in tags) Choice(t, t, enabled: t != 'beta'),
            ],
            selected: on,
            onSelectionChanged: widget.toggle ? (now) => keep('on', now) : null,
            onDeleted: widget.remove
                ? (tag) => keep('tags', [...tags]..remove(tag))
                : null,
          ),
        ),
        LitLine([
          ('on: ', true),
          if (on.where(tags.contains).isEmpty)
            ('nothing', true)
          else
            (on.where(tags.contains).join(', '), false),
        ], serial: serial),
        Button(
          'Bring them back',
          onPressed: tags.length == _firstTags.length
              ? null
              : () => keep('tags', _firstTags),
        ),
      ],
    );
  }
}
