// The app the driver's time tests run: a Spinner and a tick count that go
// by themselves, a `u` that counts and draws, a debounce that a key starts
// (`d`: "saved" after 500 ms), a plain `Future.delayed` of the app's own
// code (`f`), a child process it starts (`c`: what the child says of its
// time), and `q` to quit.
//
// With `--probe` it is the child: it says whether it took TWK_DRIVEN, and
// ends. With `--quiet` it has no spinner and no tick: nothing waits for time
// until a key starts something. `x` writes 400 kB to the terminal, which a
// terminal nobody reads does not take, so that the app's end has to wait for
// the terminal's guards.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:twk/src/binding/driven_start.dart';
import 'package:twk/twk.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--probe')) {
    print('child driven=${DrivenStart.of() != null}');
    return;
  }
  await runApp(_Demo(quiet: args.contains('--quiet')));
}

final class _Demo extends StatefulWidget {
  const _Demo({required this.quiet});

  final bool quiet;

  @override
  State<_Demo> createState() => _DemoState();
}

final class _DemoState extends State<_Demo> {
  var _ticks = 0;
  var _ups = 0;
  var _saved = 'not saved';
  var _child = 'no child';
  Timer? _debounce;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (!widget.quiet) {
      _tick = AppBinding.of(context).startPeriodic(
        const Duration(seconds: 1),
        (_) => setState(() => _ticks++),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _startDebounce() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() => _saved = 'saved');
    });
  }

  Future<void> _startChild() async {
    final result = await Process.run(Platform.resolvedExecutable, [
      Platform.script.toFilePath(),
      '--probe',
    ]);
    if (mounted) {
      setState(() => _child = '${result.stdout}'.trim());
    }
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'u': () => setState(() => _ups++),
      'd': _startDebounce,
      'f': () => unawaited(
        Future<void>.delayed(const Duration(seconds: 2)).then((_) {
          if (mounted) {
            setState(() => _saved = 'later');
          }
        }),
      ),
      'c': () => unawaited(_startChild()),
      'x': () =>
          AppBinding.of(context).twkApp.terminal.write(Uint8List(400000)),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Column(
      children: [
        if (!widget.quiet) const Spinner(),
        Text('ticks: $_ticks'),
        Text('ups: $_ups'),
        Text('saved: $_saved'),
        Text('child: $_child'),
      ],
    ),
  );
}
