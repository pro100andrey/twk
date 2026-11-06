// The RepaintBoundary page.
part of 'debugging.dart';

/// The dots' cells: the marker goes round them.
const _strip = 20;

/// How often the dots under the marker had been painted when the Code's
/// count was built: in the frame of the [k]th step, before it paints. The
/// first frame paints them; without the boundary, each step of the marker
/// over them paints them again, with it the marker alone. The page draws
/// what the Code counts: the gallery's own repaints would count too.
int _paintsAt(int k, {required bool boundary}) =>
    k == 0 ? 0 : (boundary ? 1 : k);

/// The RepaintBoundary page's `boundary` option.
const _repaintBoundaryBoundary = SwitchOption(
  'boundary',
  'RepaintBoundary',
  initial: true,
);

/// The RepaintBoundary page's `every` option.
const _repaintBoundaryEvery = ChoiceOption<int>(
  'every',
  'a step every',
  values: [300, 1000],
  labels: ['300 ms', '1 s'],
);

final _repaintBoundary = GalleryPage(
  group: _group,
  title: 'RepaintBoundary',
  options: const [
    _repaintBoundaryBoundary,
    _repaintBoundaryEvery,
  ],
  build: (context, o) => _Paints(
    boundary: o(_repaintBoundaryBoundary),
    every: o(_repaintBoundaryEvery),
  ),
  code: _paintsCode,
);

String _paintsCode(Options o) {
  final ms = o(_repaintBoundaryEvery);
  final every = ms == 1000 ? 'seconds: 1' : 'milliseconds: $ms';
  final marker = o(_repaintBoundaryBoundary)
      ? [
          '    // painted on its own, over what is under it: the dots are not',
          '    final marker = RepaintBoundary(',
          '      child: CustomPaint(painter: _Marker(_at, theme.primary)),',
          '    );',
        ]
      : [
          '    // painted with what is under it: the dots too',
          codeLine([
            '    final marker = ',
            'CustomPaint(painter: _Marker(_at, theme.primary));',
          ]),
        ];
  return [
    "import 'dart:async';",
    '',
    "import 'package:twk/twk.dart';",
    '',
    'void main() => runApp(const Paints());',
    '',
    '/// Dots across its cells, counting how often it paints them.',
    'final class _Dots extends CellPainter {',
    '  _Dots(this.style);',
    '',
    '  final Style style;',
    '  var paints = 0;',
    '',
    '  @override',
    '  void paint(Canvas canvas, int width, int height) {',
    '    paints++;',
    "    canvas.text(0, 0, '·' * width, style.penIn(canvas.styles));",
    '  }',
    '',
    '  @override',
    '  bool shouldRepaint(_Dots oldDelegate) => false;',
    '}',
    '',
    '/// A dot in the column [at] says, painted again as it moves.',
    'final class _Marker extends CellPainter {',
    '  _Marker(this.at, this.style) : super(repaint: at);',
    '',
    '  final ValueNotifier<int> at;',
    '  final Style style;',
    '',
    '  @override',
    '  void paint(Canvas canvas, int width, int height) =>',
    "      canvas.text(at.value, 0, '●', style.penIn(canvas.styles));",
    '',
    '  @override',
    '  bool shouldRepaint(_Marker oldDelegate) => false;',
    '}',
    '',
    'final class Paints extends StatefulWidget {',
    '  const Paints({super.key});',
    '',
    '  @override',
    '  State<Paints> createState() => _PaintsState();',
    '}',
    '',
    'final class _PaintsState extends State<Paints> {',
    '  final _at = ValueNotifier(0);',
    '  late final Timer _timer;',
    '  late final _dots = _Dots(Theme.of(context).border);',
    '',
    '  @override',
    '  void initState() {',
    '    super.initState();',
    '    // the marker a cell on: its painter repaints, no widget is built',
    '    _timer = Timer.periodic(',
    '      const Duration($every),',
    '      (_) => _at.value = (_at.value + 1) % $_strip,',
    '    );',
    '  }',
    '',
    '  @override',
    '  void dispose() {',
    '    _timer.cancel();',
    '    _at.dispose();',
    '    super.dispose();',
    '  }',
    '',
    '  @override',
    '  Widget build(BuildContext context) {',
    '    final theme = Theme.of(context);',
    ...marker,
    '    return Column(',
    '      mainAxisSize: .min,',
    '      crossAxisAlignment: .start,',
    '      spacing: 1,',
    '      children: [',
    '        CustomPaint(',
    '          painter: _dots,',
    '          child: SizedBox(width: $_strip, height: 1, child: marker),',
    '        ),',
    '        // the count on its own too: in a box of its size, a new one',
    '        // lays nothing else out; in a boundary, repaints nothing else',
    '        RepaintBoundary(',
    '          child: SizedBox(',
    '            width: $_strip,',
    '            height: 1,',
    '            child: ListenableBuilder(',
    '              listenable: _at,',
    '              builder: (context, _) => Text.rich([',
    "                Span('painted: ', theme.muted),",
    r"                Span('${_dots.paints}'),",
    '              ]),',
    '            ),',
    '          ),',
    '        ),',
    '      ],',
    '    );',
    '  }',
    '}',
  ].join('\n');
}

/// Dots across the cells of a [CustomPaint].
final class _DotsPainter extends CellPainter {
  const _DotsPainter(this.style);

  final Style style;

  @override
  void paint(Canvas canvas, int width, int height) =>
      canvas.text(0, 0, '·' * width, style.penIn(canvas.styles));

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => oldDelegate.style != style;
}

/// A dot in column [at].
final class _MarkerPainter extends CellPainter {
  const _MarkerPainter(this.at, this.style);

  final int at;
  final Style style;

  @override
  void paint(Canvas canvas, int width, int height) =>
      canvas.text(at, 0, '●', style.penIn(canvas.styles));

  @override
  bool shouldRepaint(_MarkerPainter oldDelegate) =>
      oldDelegate.at != at || oldDelegate.style != style;
}

/// The Code's `Paints`: dots under a marker that a timer moves a cell on
/// every [every] ms, the marker in a RepaintBoundary with [boundary], and
/// how often the dots were painted. The steps on the gallery's clock, from
/// when the page was first built (0 while it stands still) or [every] was
/// chosen; the count as the Code's would be.
final class _Paints extends StatefulWidget {
  const _Paints({required this.boundary, required this.every});

  final bool boundary;
  final int every;

  @override
  State<_Paints> createState() => _PaintsState();
}

final class _PaintsState extends TimedState<_Paints> {
  @override
  Widget buildTimed(BuildContext context) {
    final theme = Theme.of(context);
    final every = widget.every;
    if (kept['born'] == null || kept['every'] != every) {
      // a step every [every] from now: the timer started again
      kept['born'] = kept['born'] == null && motion.frozen ? 0 : now;
      kept['every'] = every;
    }
    final born = kept['born']! as int;
    final k = math.max(0, (now - born) ~/ every);
    wake(born + (k + 1) * every);
    final marker = CustomPaint(
      painter: _MarkerPainter(k % _strip, theme.primary),
    );
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 1,
      children: [
        CustomPaint(
          painter: _DotsPainter(theme.border),
          child: SizedBox(
            width: _strip,
            height: 1,
            child: widget.boundary ? RepaintBoundary(child: marker) : marker,
          ),
        ),
        RepaintBoundary(
          child: SizedBox(
            width: _strip,
            height: 1,
            child: Text.rich([
              Span('painted: ', theme.muted),
              Span('${_paintsAt(k, boundary: widget.boundary)}'),
            ]),
          ),
        ),
      ],
    );
  }
}
