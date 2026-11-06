// What the pages of the group share.
part of 'focus.dart';

/// The Code's lines too long for a line of Dart.
const _focusableArgs =
    '  const _Focusable(this.node, {this.skipTraversal, '
    'this.canRequestFocus});';

const _countLine =
    "Text.rich([Span('count: ', theme.muted), "
    r"Span('$_count')]),";

/// [node] in a box that takes the focus, by Tab or a click.
final class _Focusable extends StatelessWidget {
  const _Focusable(
    this.node, {
    this.skipTraversal,
    this.canRequestFocus,
    this.muted = false,
  });

  final FocusNode node;
  final bool? skipTraversal;
  final bool? canRequestFocus;

  /// Whether its label is muted, where something else keeps the focus from
  /// it (ExcludeFocus).
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: node.requestFocus,
      child: Focus(
        focusNode: node,
        skipTraversal: skipTraversal,
        canRequestFocus: canRequestFocus,
        child: ListenableBuilder(
          listenable: node,
          builder: (context, _) => Box(
            border: Border.all(
              type: node.hasFocus ? BorderType.heavy : BorderType.rounded,
              style: node.hasFocus ? theme.primary : theme.border,
            ),
            padding: const EdgeInsets.x(1),
            child: Text(
              node.debugLabel!,
              style: canRequestFocus == false || muted
                  ? theme.muted
                  : (node.hasFocus ? bold : const Style()),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Dart of `_Focusable`, with its [args] or not.
List<String> _focusableCode({required bool args}) => [
  '/// [node] in a box that takes the focus, by Tab or a click.',
  'final class _Focusable extends StatelessWidget {',
  if (args) ...[
    _focusableArgs,
    '',
    '  final FocusNode node;',
    '  final bool? skipTraversal;',
    '  final bool? canRequestFocus;',
  ] else ...[
    '  const _Focusable(this.node);',
    '',
    '  final FocusNode node;',
  ],
  '',
  '  @override',
  '  Widget build(BuildContext context) {',
  '    final theme = Theme.of(context);',
  '    return GestureDetector(',
  '      onTap: node.requestFocus,',
  '      child: Focus(',
  '        focusNode: node,',
  if (args) ...[
    '        skipTraversal: skipTraversal,',
    '        canRequestFocus: canRequestFocus,',
  ],
  '        child: ListenableBuilder(',
  '          listenable: node,',
  '          builder: (context, _) => Box(',
  '            border: .all(',
  '              type: node.hasFocus ? .heavy : .rounded,',
  '              style: node.hasFocus ? theme.primary : theme.border,',
  '            ),',
  '            padding: const .x(1),',
  '            child: Text(',
  '              node.debugLabel!,',
  if (args) ...[
    '              style: canRequestFocus == false',
    '                  ? theme.muted',
    '                  : (node.hasFocus ? bold : const Style()),',
  ] else
    '              style: node.hasFocus ? bold : const Style(),',
  '            ),',
  '          ),',
  '        ),',
  '      ),',
  '    );',
  '  }',
  '}',
];

const _boldCode = 'const bold = Style(attrs: Attr.bold);';

/// The box and the count by it, lit a moment when [serial] changes.
Widget _counter(FocusNode node, int count, int serial) => Row(
  mainAxisSize: MainAxisSize.min,
  spacing: 2,
  children: [
    _Focusable(node),
    LitLine([('count: ', true), ('$count', false)], serial: serial),
  ],
);

/// [counter], then [bar] while the focus is in [counter], then [did]: a
/// Column, as the Code's. The gallery's own: the bar lists the keys of the
/// focus path, which with the focus outside the page are the shell's (its
/// list's, its options'); the design's bar is empty then.
Widget _withBar(Widget counter, Widget bar, [Widget? did]) => FocusBuilder(
  builder: (context, hasFocus, _) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 1,
    children: [
      counter,
      if (hasFocus) bar else const SizedBox(height: 1),
      ?did,
    ],
  ),
);
