// The Tooltip page.
part of 'overlays.dart';

/// The Tooltip page's `wait` option.
const _tooltipWait = ChoiceOption<int>(
  'wait',
  'wait',
  values: [100, 500, 1000],
  labels: ['100 ms', '500 ms', '1 s'],
  initial: 500,
);

/// The Tooltip page's `hover` option.
const _tooltipHover = SwitchOption(
  'hover',
  'on hover',
  initial: true,
);

/// The Tooltip page's `focus` option.
const _tooltipFocus = SwitchOption(
  'focus',
  'on focus',
  initial: true,
);

final _tooltipPage = GalleryPage(
  group: _group,
  title: 'Tooltip',
  about:
      'A message by a widget while the mouse or the keyboard focus rests '
      'on it, or while a TooltipController says, centred under it by an '
      'AnchorFollower in the overlay; above it where there is no room '
      'below.',
  options: [
    _tooltipWait,
    _tooltipHover,
    _tooltipFocus,
    _lookOption,
  ],
  build: (context, o) => _Tips(
    wait: Duration(milliseconds: o(_tooltipWait)),
    hover: o(_tooltipHover),
    focus: o(_tooltipFocus),
    look: _lookOf(o),
  ),
  code: (o) => [
    'final _share = TooltipController();',
    '',
    '@override',
    'void dispose() {',
    '  _share.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) => Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  spacing: 1,',
    '  children: [',
    '    Row(',
    '      mainAxisSize: .min,',
    '      spacing: 2,',
    '      children: [',
    '        for (final (label, message, done) in const [',
    for (final (label, message, done) in _tips)
      "          ('$label', '$message', '$done'),",
    '        ])',
    '          Tooltip(',
    '            message: message,',
    if (o(_tooltipWait) case final ms when ms != 500)
      '            wait: const Duration(milliseconds: $ms),',
    if (!o(_tooltipHover)) '            showOnHover: false,',
    if (!o(_tooltipFocus)) '            showOnFocus: false,',
    ..._lookLine(o, '            '),
    "            controller: label == 'Share' ? _share : null,",
    '            child: Button(',
    '              label,',
    '              onPressed: () => showToast(',
    '                context,',
    '                done,',
    '                style: Theme.of(context).success,',
    '              ),',
    '            ),',
    '          ),',
    '      ],',
    '    ),',
    '    // shows the Share message at once, until it is pressed again',
    '    ListenableBuilder(',
    '      listenable: _share,',
    '      builder: (context, _) => Button(',
    "        _share.isShown ? 'Hide the tip' : 'Show the tip',",
    '        onPressed: _share.isShown ? _share.hide : _share.show,',
    '      ),',
    '    ),',
    '  ],',
    ');',
  ].join('\n'),
);

/// The Tooltip page's buttons: each label, its tooltip, what a press says.
const _tips = [
  ('Save', 'Saves the file', 'Saved'),
  ('Open', 'Opens a file', 'Opened'),
  ('Share', 'Copies a link to it', 'Link copied'),
];

/// The Tooltip page: the three buttons with their tooltips, the Share one
/// served by a controller, and the button that shows and hides it.
final class _Tips extends StatefulWidget {
  const _Tips({
    required this.wait,
    required this.hover,
    required this.focus,
    required this.look,
  });

  final Duration wait;
  final bool hover;
  final bool focus;
  final PanelLook look;

  @override
  State<_Tips> createState() => _TipsState();
}

final class _TipsState extends State<_Tips> {
  final _share = TooltipController();

  @override
  void dispose() {
    _share.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 1,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          for (final (label, message, done) in _tips)
            Tooltip(
              message: message,
              wait: widget.wait,
              showOnHover: widget.hover,
              showOnFocus: widget.focus,
              look: widget.look,
              controller: label == 'Share' ? _share : null,
              child: Button(
                label,
                onPressed: () => showToast(
                  context,
                  done,
                  style: Theme.of(context).success,
                ),
              ),
            ),
        ],
      ),
      ListenableBuilder(
        listenable: _share,
        builder: (context, _) => Button(
          _share.isShown ? 'Hide the tip' : 'Show the tip',
          onPressed: _share.isShown ? _share.hide : _share.show,
        ),
      ),
    ],
  );
}
