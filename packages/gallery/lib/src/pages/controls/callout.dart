// The Callout page.
part of 'controls.dart';

/// What a callout of each kind says, the button that acts on it, and its
/// own title.
const Map<StatusKind, (String, String, String)> _notices = {
  StatusKind.info: ('A newer version of twk is out: 0.2.0.', 'Update', 'twk'),
  StatusKind.success: ('The build finished in 4.2 s.', 'Open it', 'Build'),
  StatusKind.warning: (
    'The disk is 95 % full: 2.1 GB are left.',
    'Clean up',
    'Disk',
  ),
  StatusKind.error: ('3 of the 214 tests failed.', 'Show them', 'Tests'),
};

/// The Callout page's own icon, in place of the kind's.
const _ownIcon = '★';

final _callout = GalleryPage(
  group: 'Controls',
  title: 'Callout',
  options: [
    const ChoiceOption(
      'kind',
      'kind',
      values: ['info', 'success', 'warning', 'error'],
    ),
    const SwitchOption('dismiss', 'dismissible', initial: true),
    const SwitchOption('actions', 'actions', initial: true),
    const ChoiceOption(
      'title',
      'title',
      values: ['kind', 'own'],
    ),
    const ChoiceOption(
      'icon',
      'icon',
      values: ['kind', 'own', 'none'],
    ),
    SliderOption(
      'width',
      'width',
      min: 24,
      max: 60,
      initial: 44,
      format: (v) => '$v cells',
    ),
  ],
  build: (context, o) => _Notice(
    kind: StatusKind.values.byName(o.choice('kind')),
    dismiss: o.flag('dismiss'),
    actions: o.flag('actions'),
    width: o.number('width').toInt(),
    ownTitle: o.choice<String>('title') == 'own',
    icon: _iconOf(o),
  ),
  code: (o) {
    final kind = StatusKind.values.byName(o.choice('kind'));
    final (says, act, title) = _notices[kind]!;
    final icon = _iconOf(o);
    final dismiss = o.flag('dismiss');
    final actions = o.flag('actions');
    final did = act.toLowerCase();
    return [
      'var _shown = true;',
      "var _did = '';",
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      if (_shown)',
      '        SizedBox(',
      '          width: ${o.label('width')},',
      '          child: Callout.text(',
      "            '$says',",
      if (kind != StatusKind.info) '            kind: .${kind.name},',
      if (o.choice<String>('title') == 'own') "            title: '$title',",
      if (icon != null) "            icon: '$icon',",
      if (dismiss) ...[
        '            onDismissed: () => setState(() {',
        '              _shown = false;',
        "              _did = 'dismissed';",
        '            }),',
      ],
      if (actions) ...[
        '            actions: [',
        '              Button(',
        "                '$act',",
        "                onPressed: () => setState(() => _did = '$did'),",
        '              ),',
        '            ],',
      ],
      '          ),',
      '        )',
      '      else',
      '        Button(',
      "          'Show it again',",
      '          onPressed: () => setState(() {',
      '            _shown = true;',
      "            _did = 'shown again';",
      '          }),',
      '        ),',
      '      Text.rich([',
      "        Span('did: ', theme.muted),",
      '        if (_did.isEmpty)',
      "          Span('nothing', theme.muted)",
      '        else',
      '          Span(_did),',
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The Callout page's icon in [o]: null for the kind's, `''` for none.
String? _iconOf(Options o) => switch (o.choice<String>('icon')) {
  'own' => _ownIcon,
  'none' => '',
  _ => null,
};

/// A callout of [kind], dismissed and shown again, and what was done.
final class _Notice extends StatefulWidget {
  const _Notice({
    required this.kind,
    required this.dismiss,
    required this.actions,
    required this.width,
    required this.ownTitle,
    required this.icon,
  });

  final StatusKind kind;
  final bool dismiss;
  final bool actions;
  final int width;

  /// Whether it has its own title, not the kind's name.
  final bool ownTitle;

  /// Its icon: null for the kind's, `''` for none.
  final String? icon;

  @override
  State<_Notice> createState() => _NoticeState();
}

final class _NoticeState extends State<_Notice> with KeptState {
  void _did(String what, {bool? shown}) => setState(() {
    if (shown != null) {
      kept['shown'] = shown;
    }
    kept['did'] = what;
    kept['serial'] = serial + 1;
  });

  @override
  Widget build(BuildContext context) {
    final (says, act, title) = _notices[widget.kind]!;
    final did = keptOr('did', '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        if (keptOr('shown', true))
          SizedBox(
            width: widget.width,
            child: Callout.text(
              says,
              kind: widget.kind,
              title: widget.ownTitle ? title : null,
              icon: widget.icon,
              onDismissed: widget.dismiss
                  ? () => _did('dismissed', shown: false)
                  : null,
              actions: [
                if (widget.actions)
                  Button(act, onPressed: () => _did(act.toLowerCase())),
              ],
            ),
          )
        else
          Button(
            'Show it again',
            onPressed: () => _did('shown again', shown: true),
          ),
        LitLine([
          ('did: ', true),
          if (did.isEmpty) ('nothing', true) else (did, false),
        ], serial: serial),
      ],
    );
  }
}
