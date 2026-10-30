// The Foundation group of the gallery.
//
// Time is the gallery's clock alone: a timer's ticks, a future's two
// seconds and a stream's events are worked out from when they started, so
// a route's `t=` shows that moment (the page opened at 0).
import 'dart:async';

import 'package:twk/twk.dart';

import '../motion.dart';
import '../page.dart';
import 'common.dart';

/// The pages of the Foundation group that draw.
final List<GalleryPage> foundationPages = [_listenable, _async];

/// When the page was first built, in ms: at 0 while time is frozen.
int _born(Map<String, Object?> state, Motion motion) =>
    (state['born'] ??= motion.frozen ? 0 : motion.now.inMilliseconds) as int;

// ------------------------------------------------------- ListenableBuilder

/// The timer's period.
const _tick = 1000;

final _listenable = GalleryPage(
  group: 'Foundation',
  title: 'ListenableBuilder',
  options: const [SwitchOption('timer', 'timer', initial: true)],
  build: (context, o) => _Counting(timer: o.flag('timer')),
  code: (o) {
    final timer = o.flag('timer');
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

// --------------------------------------------- FutureBuilder, StreamBuilder

/// The future's delay.
const _wait = 2000;

/// The stream's period.
const _every = 1000;

/// The width of what each builder shows; its state after it.
const _col = 26;

final _async = GalleryPage(
  group: 'Foundation',
  title: 'FutureBuilder, StreamBuilder',
  options: const [
    ChoiceOption('outcome', 'future', values: ['value', 'error']),
    ChoiceOption(
      'take',
      'stream',
      values: [false, true],
      labels: ['endless', 'take(5)'],
    ),
  ],
  build: (context, o) => _Async(
    error: o.label('outcome') == 'error',
    take: o.choice<bool>('take'),
  ),
  code: (o) {
    final result = o.label('outcome') == 'error'
        ? "() => throw Exception('offline')"
        : "() => 'loaded'";
    return [
      'Future<String>? _load;',
      'final Stream<int> _ticks = Stream.periodic(',
      '  const Duration(seconds: 1),',
      '  (i) => i + 1,',
      ')${o.choice<bool>('take') ? '.take(5)' : ''};',
      '',
      'void _start() => setState(',
      '  () => _load = Future.delayed(',
      '    const Duration(seconds: 2),',
      '    $result,',
      '  ),',
      ');',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  Widget shown(Widget what, AsyncSnapshot<Object?> snapshot) => Row(',
      '    mainAxisSize: .min,',
      '    gap: 1,',
      '    children: [',
      '      SizedBox(width: $_col, child: what),',
      '      Text(snapshot.connectionState.name, style: theme.muted),',
      '    ],',
      '  );',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      "      Button('Load', onPressed: _start),",
      '      FutureBuilder<String>(',
      '        future: _load,',
      '        builder: (context, snapshot) => shown(',
      '          switch (snapshot.connectionState) {',
      codeLine([
        '            ConnectionState.none => ',
        "const Text('future: not started'),",
      ]),
      '            ConnectionState.waiting => Row(',
      '              gap: 1,',
      '              children: [',
      "                const Text('future:'),",
      '                const Spinner(),',
      '              ],',
      '            ),',
      '            _ when snapshot.hasError => Text(',
      r"              'future: ${snapshot.error}',",
      '              style: theme.error,',
      '            ),',
      codeLine([
        '            _ => ',
        r"Text('future: ${snapshot.data}', style: theme.success),",
      ]),
      '          },',
      '          snapshot,',
      '        ),',
      '      ),',
      '      StreamBuilder<int>(',
      '        stream: _ticks,',
      '        builder: (context, snapshot) =>',
      r"            shown(Text('stream: ${snapshot.data ?? 0} s'), snapshot),",
      '      ),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The Code's future and stream, on the gallery's clock: the future done
/// [_wait] ms after Load ([error] its outcome), the stream an event each
/// [_every] ms from when it was listened to, done after the fifth with
/// [take].
final class _Async extends StatefulWidget {
  const _Async({required this.error, required this.take});

  final bool error;
  final bool take;

  @override
  State<_Async> createState() => _AsyncState();
}

final class _AsyncState extends TimedState<_Async> {
  Completer<String>? _loading;
  StreamController<int>? _ticks;
  var _sent = 0;

  @override
  void dispose() {
    unawaited(_ticks?.close());
    super.dispose();
  }

  void _start() => setState(() {
    kept
      ..['loadAt'] = motion.frozen ? null : now
      ..['loadError'] = widget.error
      ..['loaded'] = true;
    _loading = null;
  });

  /// The future of the latest Load, completed once its time is past.
  Future<String>? _future() {
    if (kept['loaded'] != true) {
      return null;
    }
    final at = kept['loadAt'] as int?;
    final error = kept['loadError'] == true;
    final c = _loading ??= Completer<String>()
      // an error nobody waits on yet is not an unhandled one
      ..future.ignore();
    if (!c.isCompleted) {
      if (at == null || now >= at + _wait) {
        if (error) {
          c.completeError(Exception('offline'));
        } else {
          c.complete('loaded');
        }
      } else {
        wake(at + _wait);
      }
    }
    return c.future;
  }

  /// The stream, its events sent up to now.
  Stream<int> _stream() {
    if (kept['listened'] == null || kept['take'] != widget.take) {
      // a new stream, listened to from now
      kept
        ..['listened'] = kept['listened'] == null ? _born(kept, motion) : now
        ..['take'] = widget.take;
      unawaited(_ticks?.close());
      _ticks = null;
    }
    final ticks = _ticks ??= StreamController<int>();
    final listened = kept['listened']! as int;
    final limit = widget.take ? 5 : 1 << 30;
    final n = (now - listened) ~/ _every;
    for (; _sent < n && _sent < limit; _sent++) {
      ticks.add(_sent + 1);
    }
    if (n >= limit) {
      if (!ticks.isClosed) {
        unawaited(ticks.close());
      }
    } else {
      wake(listened + (n + 1) * _every);
    }
    return ticks.stream;
  }

  @override
  Widget buildTimed(BuildContext context) {
    final theme = Theme.of(context);
    if (_ticks == null) {
      _sent = 0;
    }
    final future = _future();
    final stream = _stream();
    Widget shown(Widget what, AsyncSnapshot<Object?> snapshot) => Row(
      mainAxisSize: MainAxisSize.min,
      gap: 1,
      children: [
        SizedBox(width: _col, child: what),
        Text(snapshot.connectionState.name, style: theme.muted),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Button('Load', onPressed: _start),
        FutureBuilder<String>(
          future: future,
          builder: (context, snapshot) => shown(
            switch (snapshot.connectionState) {
              ConnectionState.none => const Text('future: not started'),
              ConnectionState.waiting => const Row(
                gap: 1,
                children: [Text('future:'), Spinner()],
              ),
              _ when snapshot.hasError => Text(
                'future: ${snapshot.error}',
                style: theme.error,
              ),
              _ => Text('future: ${snapshot.data}', style: theme.success),
            },
            snapshot,
          ),
        ),
        StreamBuilder<int>(
          stream: stream,
          builder: (context, snapshot) =>
              shown(Text('stream: ${snapshot.data ?? 0} s'), snapshot),
        ),
      ],
    );
  }
}
