// The ModalBarrier page.
part of 'overlays.dart';

/// The ModalBarrier page's `barrier` option.
const _modalbarrierBarrier = SwitchOption(
  'barrier',
  'barrier',
  initial: true,
);

/// The ModalBarrier page's `alpha` option.
const _modalbarrierAlpha = ChoiceOption<int>(
  'alpha',
  'alpha',
  values: [0x40, 0x80, 0xc0],
  labels: ['¼', '½', '¾'],
  initial: 0x80,
);

/// The ModalBarrier page's `fade` option.
final _modalbarrierFade = SwitchOption(
  'fade',
  'fade',
  disabled: (o) => !o(_modalbarrierBarrier),
);

final _modalbarrierPage = GalleryPage(
  group: _group,
  title: 'ModalBarrier',
  options: [
    _modalbarrierBarrier,
    _modalbarrierAlpha,
    // an AnimatedModalBarrier, its shade coming in and going on a
    // controller
    _modalbarrierFade,
  ],
  build: (context, o) => _Barrier(
    barrier: o(_modalbarrierBarrier),
    alpha: o(_modalbarrierAlpha),
    fade: o(_modalbarrierBarrier) && o(_modalbarrierFade),
  ),
  code: _barrierCode,
);

/// The ModalBarrier page's Code.
String _barrierCode(Options o) {
  final alpha = o(_modalbarrierAlpha);
  final fade = o(_modalbarrierBarrier) && o(_modalbarrierFade);
  final barrier = !o(_modalbarrierBarrier)
      ? ''
      : [
          if (fade) ...[
            '      AnimatedModalBarrier(',
            '        animation: _fade,',
          ] else
            '      ModalBarrier(',
          if (alpha != 0x80)
            '        alpha: 0x${alpha.toRadixString(16)}, // ${o.nameOf(_modalbarrierAlpha)}',
          '        onDismiss: () => setState(() => _dismissed++),',
          '      ),',
          '',
        ].join('\n');
  final controller = !fade
      ? ''
      : '''

// the shade comes in and goes, again and again
late final _fade = AnimationController(
  vsync: this,
  duration: const Duration(seconds: 1),
)..repeat(reverse: true);

@override
void dispose() {
  _fade.dispose();
  super.dispose();
}''';
  return '''
var _pressed = 0;
var _dismissed = 0;$controller

@override
Widget build(BuildContext context) => SizedBox(
  width: 40,
  height: 8,
  child: Stack(
    fit: .expand,
    children: [
      Column(
        crossAxisAlignment: .start,
        gap: 1,
        children: [
          const Text(
            'The text under the barrier, dimmed by it: the mouse does not '
            'reach it.',
          ),
          Button('Press me', onPressed: () => setState(() => _pressed++)),
          Text.rich([
            Span('pressed ', Theme.of(context).muted),
            Span('\$_pressed'),
            Span(', the barrier ', Theme.of(context).muted),
            Span('\$_dismissed'),
          ]),
        ],
      ),
$barrier      const Center(
        child: Panel(
          padding: .x(1),
          shadow: false,
          child: Text('over it'),
        ),
      ),
    ],
  ),
);''';
}

/// Text and a button under a barrier, and a panel over it.
final class _Barrier extends StatefulWidget {
  const _Barrier({
    required this.barrier,
    required this.alpha,
    required this.fade,
  });

  final bool barrier;
  final int alpha;

  /// Whether the barrier is an [AnimatedModalBarrier] whose shade comes in
  /// and goes on a controller of 1 s, repeated both ways.
  final bool fade;

  @override
  State<_Barrier> createState() => _BarrierState();
}

final class _BarrierState extends State<_Barrier>
    with TickerProviderStateMixin, KeptState {
  int get _pressed => kept['pressed'] as int? ?? 0;
  int get _dismissed => kept['dismissed'] as int? ?? 0;

  // the Code's _fade, from when fade is turned on
  AnimationController? _fade;

  @override
  void dispose() {
    _fade?.dispose();
    super.dispose();
  }

  /// The controller while fade is on: made and run when it is turned on,
  /// thrown away when it is turned off.
  AnimationController? _fadeNow() {
    if (!widget.fade) {
      _fade?.dispose();
      return _fade = null;
    }
    return _fade ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  void _dismiss() => setState(() => kept['dismissed'] = _dismissed + 1);

  @override
  Widget build(BuildContext context) {
    final fade = _fadeNow();
    final alpha = widget.alpha == 0x80 ? null : widget.alpha;
    return _build(
      context,
      !widget.barrier
          ? null
          : fade != null
          ? AnimatedModalBarrier(
              animation: fade,
              alpha: alpha,
              onDismiss: _dismiss,
            )
          : ModalBarrier(alpha: alpha, onDismiss: _dismiss),
    );
  }

  Widget _build(BuildContext context, Widget? barrier) => SizedBox(
    width: 40,
    height: 8,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          gap: 1,
          children: [
            const Text(
              'The text under the barrier, dimmed by it: the mouse does not '
              'reach it.',
            ),
            Button(
              'Press me',
              onPressed: () => setState(() => kept['pressed'] = _pressed + 1),
            ),
            Text.rich([
              Span('pressed ', Theme.of(context).muted),
              Span('$_pressed'),
              Span(', the barrier ', Theme.of(context).muted),
              Span('$_dismissed'),
            ]),
          ],
        ),
        ?barrier,
        const Center(
          child: Panel(
            padding: EdgeInsets.x(1),
            shadow: false,
            child: Text('over it'),
          ),
        ),
      ],
    ),
  );
}
