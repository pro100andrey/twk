// The FutureBuilder, StreamBuilder page.
part of 'foundation.dart';

/// The future's delay.
const _wait = 2000;

/// The stream's period.
const _every = 1000;

/// The width of what each builder shows; its state after it.
const _col = 26;

/// The FutureBuilder, StreamBuilder page's `outcome` option.
const _asyncOutcome = ChoiceOption<String>(
  'outcome',
  'future',
  values: ['value', 'error'],
);

/// The FutureBuilder, StreamBuilder page's `take` option.
const _asyncTake = ChoiceOption<bool>(
  'take',
  'stream',
  values: [false, true],
  labels: ['endless', 'take(5)'],
);

final _async = GalleryPage(
  group: _group,
  title: 'FutureBuilder, StreamBuilder',
  options: const [
    _asyncOutcome,
    _asyncTake,
  ],
  build: (context, o) => _Async(
    error: o.nameOf(_asyncOutcome) == 'error',
    take: o(_asyncTake),
  ),
  code: (o) {
    final result = o.nameOf(_asyncOutcome) == 'error'
        ? "() => throw Exception('offline')"
        : "() => 'loaded'";
    return [
      'Future<String>? _load;',
      'final Stream<int> _ticks = Stream.periodic(',
      '  const Duration(seconds: 1),',
      '  (i) => i + 1,',
      ')${o(_asyncTake) ? '.take(5)' : ''};',
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
