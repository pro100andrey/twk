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

/// The Callout page's `kind` option.
const _calloutKind = ChoiceOption<String>(
  'kind',
  'kind',
  values: ['info', 'success', 'warning', 'error'],
);

/// The Callout page's `dismiss` option.
const _calloutDismiss = SwitchOption(
  'dismiss',
  'dismissible',
  initial: true,
);

/// The Callout page's `actions` option.
const _calloutActions = SwitchOption(
  'actions',
  'actions',
  initial: true,
);

/// The Callout page's `title` option.
const _calloutTitle = ChoiceOption<String>(
  'title',
  'title',
  values: ['kind', 'own'],
);

/// The Callout page's `icon` option.
const _calloutIcon = ChoiceOption<String>(
  'icon',
  'icon',
  values: ['kind', 'own', 'none'],
);

/// The Callout page's `border` option.
const _calloutBorder = ChoiceOption<String>(
  'border',
  'border',
  values: ['single', 'rounded', 'heavy'],
);

/// The Callout page's `width` option.
final _calloutWidth = SliderOption(
  'width',
  'width',
  min: 24,
  max: 60,
  initial: 44,
  format: (v) => '$v cells',
);

final _callout = GalleryPage(
  group: _group,
  title: 'Callout',
  options: [
    _calloutKind,
    _calloutDismiss,
    _calloutActions,
    _calloutTitle,
    _calloutIcon,
    _calloutBorder,
    _calloutWidth,
  ],
  build: (context, o) => _Notice(
    kind: StatusKind.values.byName(o(_calloutKind)),
    dismiss: o(_calloutDismiss),
    actions: o(_calloutActions),
    width: o(_calloutWidth).toInt(),
    ownTitle: o(_calloutTitle) == 'own',
    icon: _iconOf(o),
    border: BorderType.values.byName(o(_calloutBorder)),
  ),
  code: (o) {
    final kind = StatusKind.values.byName(o(_calloutKind));
    final (says, act, title) = _notices[kind]!;
    final icon = _iconOf(o);
    final dismiss = o(_calloutDismiss);
    final actions = o(_calloutActions);
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
      '    spacing: 1,',
      '    children: [',
      '      if (_shown)',
      '        SizedBox(',
      '          width: ${o.nameOf(_calloutWidth)},',
      '          child: Callout.text(',
      "            '$says',",
      if (kind != StatusKind.info) '            kind: .${kind.name},',
      if (o(_calloutTitle) == 'own') "            title: '$title',",
      if (icon != null) "            icon: '$icon',",
      if (o(_calloutBorder) != 'single')
        '            borderType: .${o(_calloutBorder)},',
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
String? _iconOf(Options o) => switch (o(_calloutIcon)) {
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
    required this.border,
  });

  final StatusKind kind;
  final bool dismiss;
  final bool actions;
  final int width;

  /// Whether it has its own title, not the kind's name.
  final bool ownTitle;

  /// Its icon: null for the kind's, `''` for none.
  final String? icon;

  /// The lines of its box.
  final BorderType border;

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
      spacing: 1,
      children: [
        if (keptOr('shown', true))
          SizedBox(
            width: widget.width,
            child: Callout.text(
              says,
              kind: widget.kind,
              title: widget.ownTitle ? title : null,
              icon: widget.icon,
              borderType: widget.border,
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
