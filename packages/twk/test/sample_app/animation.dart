part of '../sample_app.dart';

extension on _SampleAppState {
  List<Widget> _animation() => [
    ValueListenableBuilder(
      valueListenable: _count,
      builder: (context, count, child) {
        final odd = count.isOdd;
        const duration = Duration(milliseconds: 200);
        return Row(
          gap: 1,
          children: [
            const Spinner(),
            const Spinner(
              frames: SpinnerFrames.arc,
              style: Style(fg: Color.green),
            ),
            const Expanded(child: ProgressBar(value: 0.4)),
            const Expanded(child: ProgressBar()),
            const Expanded(child: _Pulse()),
            AnimatedPadding(
              padding: EdgeInsets.only(left: odd ? 1 : 0),
              duration: duration,
              child: const Text('pad'),
            ),
            SizedBox(
              width: 4,
              height: 1,
              child: AnimatedAlign(
                alignment: odd ? Alignment.centerRight : Alignment.centerLeft,
                duration: duration,
                curve: Curves.easeOut,
                child: const Text('•'),
              ),
            ),
            SizedBox(
              width: 4,
              height: 1,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    left: odd ? 3 : 0,
                    duration: duration,
                    child: const Text('•'),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              opacity: odd ? 0.5 : 1,
              duration: duration,
              child: const Text('fade'),
            ),
            AnimatedDefaultTextStyle(
              style: Style(fg: odd ? Color.red : Color.green),
              duration: duration,
              child: const Text('style'),
            ),
            AnimatedBox(
              width: odd ? 6 : 4,
              height: 1,
              style: Style(bg: odd ? Color.blue : Color.black),
              duration: duration,
              child: const Text('box'),
            ),
            AnimatedSize(
              duration: duration,
              child: Text(odd ? 'longer' : 'short'),
            ),
            AnimatedSwitcher(
              duration: duration,
              transition: odd
                  ? SwitcherTransition.dissolve
                  : const SwitcherTransition.slide(
                      from: Alignment.bottomCenter,
                    ),
              child: Text('$count', key: ValueKey(count)),
            ),
            TweenAnimationBuilder<double>(
              value: odd ? 1 : 0,
              tween: Tween.new,
              duration: duration,
              builder: (context, value, child) =>
                  SizedBox(width: 4, child: ProgressBar(value: value)),
            ),
            const Opacity(opacity: 0.6, child: Text('dim')),
            const Dissolve(shown: 0.8, child: Text('cells')),
            const FractionalTranslation(x: 0.2, child: Text('moved')),
            Effect(
              effect: CellEffect.parallel([
                const CellEffect.scanlines(),
                if (odd)
                  const CellEffect.typewriter(duration: duration)
                else
                  const CellEffect.sweep(
                    from: Alignment.centerRight,
                    duration: duration,
                  ).reversed.delayed(duration),
              ]),
              child: const Text('effect'),
            ),
            _Glow(on: odd, duration: duration),
          ],
        );
      },
    ),
    ProgressList(tracker: _progress, maxVisible: 2),
    ValueListenableBuilder(
      valueListenable: _count,
      builder: (context, count, child) => SkeletonTheme(
        period: const Duration(seconds: 1),
        child: Row(
          gap: 1,
          children: [
            Skeletonize(
              enabled: count.isEven,
              child: Text('User: ${count.isEven ? 'Placeholder' : 'Ada'}'),
            ),
            const Skeleton(width: 6),
            const Expanded(child: Skeleton.text(lines: 2)),
          ],
        ),
      ),
    ),
  ];
}

/// The tasks of the progress list: one going, one done, one waiting.
final _progress = ProgressTracker()
  ..add('fetch', total: 4, unit: ProgressUnit.bytes).advance()
  ..add('build').done()
  ..add('test');

/// A bar filled and emptied, round after round, by a controller, and
/// shaded as it fills.
final class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

final class _PulseState extends State<_Pulse> with TickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  static final Animatable<double> _fill = const Tween<double>(
    begin: 0.1,
    end: 1,
  ).chain(Curves.easeInOut);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => ProgressBar(value: _fill.evaluate(_controller)),
      ),
      Positioned.fill(
        child: AnimatedModalBarrier(animation: _controller, alpha: 0x20),
      ),
    ],
  );
}

/// A dot that glows when [on], its color running to the new one: an
/// implicit animation of the app's own.
final class _Glow extends ImplicitlyAnimatedWidget {
  const _Glow({required this.on, required super.duration});

  final bool on;

  @override
  State<_Glow> createState() => _GlowState();
}

final class _GlowState extends ImplicitlyAnimatedWidgetState<_Glow> {
  Tween<Style>? _style;

  @override
  void forEachTween(TweenVisitor visit) => _style = visit(
    _style,
    Style(
      fg: widget.on
          ? const Color.rgb(255, 200, 0)
          : const Color.rgb(60, 60, 60),
    ),
    StyleTween.new,
  );

  @override
  Widget build(BuildContext context) =>
      Text('●', style: _style!.transform(progress));
}
