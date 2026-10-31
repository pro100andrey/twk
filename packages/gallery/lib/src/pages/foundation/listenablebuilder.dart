// The ListenableBuilder page.
part of 'foundation.dart';

/// The timer's period.
const _tick = 1000;

/// The ListenableBuilder page's `timer` option.
const _listenableTimer = SwitchOption(
  'timer',
  'timer',
  initial: true,
);

final _listenable = GalleryPage(
  group: _group,
  title: 'ListenableBuilder',
  options: const [_listenableTimer],
  build: (context, o) => _Counting(timer: o(_listenableTimer)),
  code: (o) {
    final timer = o(_listenableTimer);
    return [
      'final _count = ValueNotifier<int>(0);',
      if (timer) ...[
        'late final Timer _timer;',
        '',
        '@override',
        'void initState() {',
        '  super.initState();',
        '  // one more each second',
        '  _timer = Timer.periodic(',
        '    const Duration(seconds: 1),',
        '    (_) => _count.value++,',
        '  );',
        '}',
      ],
      '',
      '@override',
      'void dispose() {',
      if (timer) '  _timer.cancel();',
      '  _count.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    Row(',
      '      mainAxisSize: .min,',
      '      gap: 2,',
      '      children: [',
      "        Button('Count', onPressed: () => _count.value++),",
      '        // notifies no one when it is 0 already',
      "        Button('Reset', onPressed: () => _count.value = 0),",
      '      ],',
      '    ),',
      '    ListenableBuilder(',
      '      listenable: _count,',
      codeLine([
        '      builder: (context, _) => ',
        r"Text('ListenableBuilder: ${_count.value}'),",
      ]),
      '    ),',
      '    ValueListenableBuilder(',
      '      valueListenable: _count,',
      codeLine([
        '      builder: (context, value, _) => ',
        r"Text('ValueListenableBuilder: $value'),",
      ]),
      '    ),',
      '  ],',
      ');',
    ].join('\n');
  },
);

/// The Code's count: what was pressed, and the ticks of the timer while
/// [timer] runs, on the gallery's clock.
final class _Counting extends StatefulWidget {
  const _Counting({required this.timer});

  final bool timer;

  @override
  State<_Counting> createState() => _CountingState();
}

final class _CountingState extends TimedState<_Counting> {
  final _count = ValueNotifier<int>(0);

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  /// The count now: the kept count at `since`, and the ticks since.
  int _counted() {
    if (kept['n'] == null) {
      kept
        ..['n'] = 0
        ..['since'] = _born(kept, motion)
        ..['timer'] = widget.timer;
    }
    final since = kept['since']! as int;
    if (kept['timer'] != widget.timer) {
      // the timer started or stopped: the ticks so far are counted in
      if (kept['timer']! as bool) {
        kept['n'] = (kept['n']! as int) + (now - since) ~/ _tick;
      }
      kept
        ..['timer'] = widget.timer
        ..['since'] = now;
    }
    final n = kept['n']! as int;
    if (!widget.timer) {
      return n;
    }
    final at = kept['since']! as int;
    final k = (now - at) ~/ _tick;
    wake(at + (k + 1) * _tick);
    return n + k;
  }

  /// Sets the count to what [f] makes of it, as `_count.value = …` does.
  void _set(int Function(int) f) => setState(() {
    final c = _counted();
    kept['n'] = (kept['n']! as int) + f(c) - c;
  });

  @override
  Widget buildTimed(BuildContext context) {
    _count.value = _counted();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          gap: 2,
          children: [
            Button('Count', onPressed: () => _set((v) => v + 1)),
            Button('Reset', onPressed: () => _set((_) => 0)),
          ],
        ),
        ListenableBuilder(
          listenable: _count,
          builder: (context, _) => Text('ListenableBuilder: ${_count.value}'),
        ),
        ValueListenableBuilder(
          valueListenable: _count,
          builder: (context, value, _) =>
              Text('ValueListenableBuilder: $value'),
        ),
      ],
    );
  }
}
