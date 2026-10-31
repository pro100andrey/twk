// The CustomPaint page.
part of 'layout.dart';

// ------------------------------------------------------------ CustomPaint

const _blocks = ' ▁▂▃▄▅▆▇█';

const _waveStep = 100;

/// Blocks as high as a wave 24 columns long at [phase], as the Code's
/// WavePainter paints them; the gallery's clock gives the phase.
final class _Wave extends CellPainter {
  const _Wave(this.phase, this.style);

  final int phase;
  final Style style;

  @override
  void paint(Canvas canvas, int width, int height) {
    final pen = style.penIn(canvas.styles);
    for (var x = 0; x < width; x++) {
      final u = (x + phase) % 24;
      final eighths = 4 + 3 * (u < 12 ? u : 24 - u);
      for (var row = 0; row < height; row++) {
        final left = eighths - 8 * row;
        if (left > 0) {
          canvas.text(x, height - 1 - row, _blocks[math.min(left, 8)], pen);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Wave oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.style != style;
}

/// The CustomPaint page's `paints` option.
const _customPaintPaints = ChoiceOption<String>(
  'paints',
  'painter',
  values: ['under', 'over'],
  labels: ['painter', 'foregroundPainter'],
);

/// The CustomPaint page's `moving` option.
const _customPaintMoving = SwitchOption(
  'moving',
  'moving',
  initial: true,
);

/// The CustomPaint page's `color` option.
const _customPaintColor = ColorOption(
  'color',
  'style',
  values: ['primary', 'accent', 'success'],
  initial: 'primary',
);

final _customPaint = GalleryPage(
  group: _group,
  title: 'CustomPaint',
  options: const [
    _customPaintPaints,
    _customPaintMoving,
    _customPaintColor,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final style = o.styleOf(context, _customPaintColor);
    final under = o(_customPaintPaints) == 'under';
    Widget painted(int phase) => CustomPaint(
      painter: under ? _Wave(phase, style) : null,
      foregroundPainter: under ? null : _Wave(phase, style),
      child: SizedBox(
        width: 36,
        height: 6,
        child: Center(
          child: Text(
            'cells of its own',
            style: theme.text.merge(const Style(attrs: Attr.bold)),
          ),
        ),
      ),
    );
    if (!o(_customPaintMoving)) {
      return painted(0);
    }
    return _Ticks(
      ms: _waveStep,
      builder: (context, steps) => painted(steps),
    );
  },
  code: (o) {
    final which = o(_customPaintPaints) == 'under'
        ? 'painter'
        : 'foregroundPainter';
    return [
      if (o(_customPaintMoving)) ...[
        'final _phase = ValueNotifier(0);',
        'late final Timer _timer;',
        '',
        '@override',
        'void initState() {',
        '  super.initState();',
        '  _timer = Timer.periodic(',
        '    const Duration(milliseconds: $_waveStep),',
        '    (_) => _phase.value++,',
        '  );',
        '}',
        '',
        '@override',
        'void dispose() {',
        '  _timer.cancel();',
        '  _phase.dispose();',
        '  super.dispose();',
        '}',
      ] else ...[
        'final _phase = ValueNotifier(0);',
        '',
        '@override',
        'void dispose() {',
        '  _phase.dispose();',
        '  super.dispose();',
        '}',
      ],
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return CustomPaint(',
      '    $which: WavePainter(_phase, theme.${o(_customPaintColor)}),',
      '    child: SizedBox(',
      '      width: 36,',
      '      height: 6,',
      '      child: Center(',
      '        child: Text(',
      "          'cells of its own',",
      '          style: theme.text.merge(const .new(attrs: Attr.bold)),',
      '        ),',
      '      ),',
      '    ),',
      '  );',
      '}',
      '',
      '/// Blocks as high as a wave 24 columns long, moved along by [phase]',
      '/// with no widget built again.',
      'final class WavePainter extends CellPainter {',
      '  WavePainter(this.phase, this.style) : super(repaint: phase);',
      '',
      '  final ValueNotifier<int> phase;',
      '  final Style style;',
      '',
      '  @override',
      '  void paint(Canvas canvas, int width, int height) {',
      '    final pen = style.penIn(canvas.styles);',
      '    for (var x = 0; x < width; x++) {',
      '      final u = (x + phase.value) % 24;',
      '      final eighths = 4 + 3 * (u < 12 ? u : 24 - u);',
      '      for (var row = 0; row < height; row++) {',
      '        final left = eighths - 8 * row;',
      '        if (left > 0) {',
      codeLine([
        '          canvas.text(x, height - 1 - row, ',
        "'$_blocks'[min(left, 8)], pen);",
      ]),
      '        }',
      '      }',
      '    }',
      '  }',
      '',
      '  @override',
      '  bool shouldRepaint(WavePainter oldDelegate) =>',
      '      oldDelegate.phase != phase || oldDelegate.style != style;',
      '}',
    ].join('\n');
  },
);
