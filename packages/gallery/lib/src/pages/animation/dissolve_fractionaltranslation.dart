// The Dissolve, FractionalTranslation page.
part of 'animation.dart';

/// A double as Dart writes one: `1.0`, `0.25`.
String _dbl(num v) => v == v.roundToDouble() ? v.toStringAsFixed(1) : '$v';

/// The child: its text in a Box padded a cell either side.
const _piece = 'a child, its cells shown or moved';

/// The controller's duration while it runs.
const _round = 2000;

/// The Dissolve, FractionalTranslation page's `share` option.
const _dissolveShare = ChoiceOption<double>(
  'share',
  'share',
  values: _opacities,
  labels: _fractions,
  initial: 0.5,
);

/// The Dissolve, FractionalTranslation page's `run` option.
const _dissolveRun = SwitchOption('run', 'run', initial: true);

/// The Dissolve, FractionalTranslation page's `inverse` option.
const _dissolveInverse = SwitchOption('inverse', 'inverse');

final _dissolve = GalleryPage(
  group: _group,
  title: 'Dissolve, FractionalTranslation',
  options: [
    _dissolveShare,
    _dissolveRun,
    // the cells from the end of their order: exactly the others
    _dissolveInverse,
  ],
  build: (context, o) {
    final share = o(_dissolveShare);
    final inverse = o(_dissolveInverse);
    // a new share, or the switch, runs the controller again from it
    return o(_dissolveRun)
        ? _Shares(share, inverse: inverse, key: ValueKey(share))
        : _sharesTree(context, share, inverse: inverse);
  },
  code: (o) {
    final inverse = o(_dissolveInverse);
    final inv = inverse ? ', inverse: true' : '';
    List<String> tree(String share) => [
      'Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  children: [',
      '    Text(',
      "      'Dissolve(shown: \${$share.toStringAsFixed(2)}$inv)',",
      '      style: theme.muted,',
      '    ),',
      '    Dissolve(shown: $share$inv, child: shown),',
      '    const SizedBox(height: 1),',
      '    Text(',
      "      'FractionalTranslation(x: \${($share - 1).toStringAsFixed(2)})',",
      '      style: theme.muted,',
      '    ),',
      '    FractionalTranslation(x: $share - 1, child: shown),',
      '  ],',
      ')',
    ];
    const shown = [
      'final theme = Theme.of(context);',
      'final shown = Box(',
      '  style: theme.selection,',
      '  padding: const .x(1),',
      "  child: const Text('$_piece'),",
      ');',
    ];
    final share = o(_dissolveShare);
    if (!o(_dissolveRun)) {
      return [
        ...shown,
        'const share = ${_dbl(share)};',
        'return ${tree('share').join('\n')};',
      ].join('\n');
    }
    final t = tree('share');
    return [
      'final class _SharesState extends State<_Shares>',
      '    with TickerProviderStateMixin {',
      ..._indent([
        'late final _controller = AnimationController(',
        '  vsync: this,',
        '  duration: const Duration(milliseconds: $_round),',
        '  value: ${_js(share)},',
        ')..repeat(reverse: true);',
        '',
        '@override',
        'void dispose() {',
        '  _controller.dispose();',
        '  super.dispose();',
        '}',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        ..._indent(shown, 2),
        '  return ListenableBuilder(',
        '    listenable: _controller,',
        '    builder: (context, _) {',
        '      final share = _controller.value;',
        ..._indent([
          'return ${t.first}',
          ...t.sublist(1, t.length - 1),
          ');',
        ], 6),
        '    },',
        '  );',
        '}',
      ], 2),
      '}',
    ].join('\n');
  },
);

/// The Code's tree: the child dissolved to [share] of its cells, and
/// moved left by what is left of it.
Widget _sharesTree(
  BuildContext context,
  double share, {
  required bool inverse,
}) {
  final theme = Theme.of(context);
  final shown = Box(
    style: theme.selection,
    padding: const .x(1),
    child: const Text(_piece),
  );
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    children: [
      Text(
        'Dissolve(shown: ${share.toStringAsFixed(2)}'
        '${inverse ? ', inverse: true' : ''})',
        style: theme.muted,
      ),
      Dissolve(shown: share, inverse: inverse, child: shown),
      const SizedBox(height: 1),
      Text(
        'FractionalTranslation(x: ${(share - 1).toStringAsFixed(2)})',
        style: theme.muted,
      ),
      FractionalTranslation(x: share - 1, child: shown),
    ],
  );
}

/// The Code's `_Shares`: a controller from [share] up to 1 and back, round
/// after round, the tree at its value.
final class _Shares extends StatefulWidget {
  const _Shares(this.share, {required this.inverse, super.key});

  final double share;
  final bool inverse;

  @override
  State<_Shares> createState() => _SharesState();
}

final class _SharesState extends State<_Shares> with TickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _round),
    value: widget.share,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) =>
        _sharesTree(context, _controller.value, inverse: widget.inverse),
  );
}
