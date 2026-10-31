// The Dialog page.
part of 'overlays.dart';

final _dialogPage = GalleryPage(
  group: 'Overlays',
  title: 'Dialog',
  options: [
    const ChoiceOption(
      'alignment',
      'alignment',
      values: ['center', 'topCenter', 'bottomRight'],
    ),
    const SwitchOption('shadow', 'shadow'),
    _lookOption,
    const SwitchOption('dismissible', 'dismissible', initial: true),
  ],
  build: (context, o) => _Ask(
    alignment: o.choice('alignment'),
    shadow: o.flag('shadow'),
    look: _lookOf(o),
    dismissible: o.flag('dismissible'),
  ),
  code: (o) => [
    'String? _answer;',
    '',
    'void _ask() => unawaited(',
    '  showDialog<bool>(',
    '    context,',
    '    (context) => Dialog(',
    "      title: 'Delete',",
    if (o.flag('shadow')) '      shadow: Panel.shadowOf(Theme.of(context)),',
    ..._lookLine(o, '      '),
    '      child: Column(',
    '        mainAxisSize: .min,',
    '        crossAxisAlignment: .start,',
    '        gap: 1,',
    '        children: [',
    "          const Text('Delete 3 files?'),",
    '          Row(',
    '            mainAxisSize: .min,',
    '            gap: 2,',
    '            children: [',
    '              Button(',
    "                'Delete',",
    '                autofocus: true,',
    '                onPressed: () => closeDialog(context, true),',
    '              ),',
    _keepLine,
    '            ],',
    '          ),',
    '        ],',
    '      ),',
    '    ),',
    if (!o.flag('dismissible')) '    dismissible: false,',
    '    alignment: .${o.label('alignment')},',
    '  ).then(',
    '    (delete) => setState(',
    '      () => _answer = switch (delete) {',
    "        true => 'deleted',",
    "        false => 'kept',",
    "        null => 'dismissed',",
    '      },',
    '    ),',
    '  ),',
    ');',
    '',
    '@override',
    'Widget build(BuildContext context) => Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  gap: 1,',
    '  children: [',
    "    Button('Ask', onPressed: _ask),",
    '    Text.rich([',
    "      Span('answer: ', Theme.of(context).muted),",
    '      switch (_answer) {',
    "        null => Span('nothing', Theme.of(context).muted),",
    '        final answer => Span(answer),',
    '      },',
    '    ]),',
    '  ],',
    ');',
  ].join('\n'),
);

/// The Code's line of the Keep button.
const _keepLine =
    "              Button('Keep', onPressed: () => closeDialog(context, "
    'false)),';

/// A button that asks in a dialog, and the answer.
final class _Ask extends StatefulWidget {
  const _Ask({
    required this.alignment,
    required this.shadow,
    required this.look,
    required this.dismissible,
  });

  final String alignment;
  final bool shadow;
  final PanelLook look;

  /// Whether Escape and a click outside dismiss the dialog.
  final bool dismissible;

  @override
  State<_Ask> createState() => _AskState();
}

final class _AskState extends State<_Ask> {
  String? _answer;
  var _asked = 0;

  static const Map<String, Alignment> _alignments = {
    'center': Alignment.center,
    'topCenter': Alignment.topCenter,
    'bottomRight': Alignment.bottomRight,
  };

  void _ask() => unawaited(
    showDialog<bool>(
      context,
      (context) => Dialog(
        title: 'Delete',
        shadow: widget.shadow ? Panel.shadowOf(Theme.of(context)) : null,
        look: widget.look,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          gap: 1,
          children: [
            const Text('Delete 3 files?'),
            Row(
              mainAxisSize: MainAxisSize.min,
              gap: 2,
              children: [
                Button(
                  'Delete',
                  autofocus: true,
                  onPressed: () => closeDialog(context, true),
                ),
                Button('Keep', onPressed: () => closeDialog(context, false)),
              ],
            ),
          ],
        ),
      ),
      dismissible: widget.dismissible,
      alignment: _alignments[widget.alignment] ?? Alignment.center,
    ).then((delete) {
      if (mounted) {
        setState(() {
          _asked++;
          _answer = switch (delete) {
            true => 'deleted',
            false => 'kept',
            null => 'dismissed',
          };
        });
      }
    }),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Button('Ask', onPressed: _ask),
      LitLine([
        ('answer: ', true),
        (_answer ?? 'nothing', _answer == null),
      ], serial: _asked),
    ],
  );
}
