/// An app written against `package:twk/twk.dart` alone: it builds every
/// public widget, has widgets and render objects of its own, and names
/// every declaration of twk_core that twk.dart exports (exports_test.dart
/// checks all three). [runInMemory] runs it on a terminal in memory.
///
/// A widget is built in the part of its topic, `sample_app/<topic>.dart`,
/// the topic of the library that declares it: the part gives the rows of
/// the topic, wraps the app where its widgets do, and keeps the state they
/// need. This library keeps what the topics share, a count and a stream of
/// its values, and lays out the rows of the topics in a column.
library;

import 'dart:async';

import 'package:twk/twk.dart';

part 'sample_app/animation.dart';
part 'sample_app/binding.dart';
part 'sample_app/controls.dart';
part 'sample_app/data.dart';
part 'sample_app/debug.dart';
part 'sample_app/editing.dart';
part 'sample_app/focus.dart';
part 'sample_app/foundation.dart';
part 'sample_app/framework.dart';
part 'sample_app/gestures.dart';
part 'sample_app/layout.dart';
part 'sample_app/navigation.dart';
part 'sample_app/overlay.dart';
part 'sample_app/scroll.dart';
part 'sample_app/semantics.dart';
part 'sample_app/style.dart';
part 'sample_app/text.dart';

/// Runs the app in a viewport of a terminal in memory until it painted
/// its first frame and took a `q`; returns what it logged. Its frames are
/// spaced by [clock]: a test hands it a fake clock's stopwatch, and runs
/// this in that clock's zone.
Future<List<LogRecord>> runInMemory({required Stopwatch clock}) async {
  final terminal = HeadlessTerminal(
    width: 122,
    height: 72,
    caps: const TerminalCaps(
      repeatChar: true,
      graphics: GraphicsProtocol.kitty,
    ),
    colorMode: ColorMode.ansi256,
    options: const TerminalOptions(mouseMotion: true),
    multiplexer: Multiplexer.tmux,
    notifications: NotificationProtocol.osc777,
    pointerShapes: true,
    pointerNames: PointerNames.x11,
    progressReports: true,
    bidi: BidiReordering.terminal,
  )..type('q');
  final logs = LogSink();
  await _run(terminal, logs, clock);
  return logs.records;
}

Future<void> _run(TerminalBackend terminal, LogSink logs, Stopwatch clock) =>
    runApp(
      const SampleApp(),
      viewport: const Viewport.fixed(1, 1, 120, 70),
      terminal: terminal,
      logs: logs,
      bidi: BidiReordering.terminal,
      clock: clock,
    );

/// One line of [Glyphs] painted on its own, as text.
String snapshot() =>
    renderToString(RenderGlyphs('snap'), 8, 1, styles: StyleTable());

final class SampleApp extends StatefulWidget {
  const SampleApp({super.key});

  @override
  State<SampleApp> createState() => _SampleAppState();
}

final class _SampleAppState extends State<SampleApp> {
  final _count = ValueNotifier<int>(0);
  final _ticks = StreamController<int>.broadcast();

  @override
  void dispose() {
    _count.dispose();
    unawaited(_ticks.close());
    super.dispose();
  }

  bool _bump() {
    _count.value++;
    _ticks.add(_count.value);
    return true;
  }

  @override
  Widget build(BuildContext context) => _listening(
    _focused(
      _themed(
        _styled(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._animation(),
              ..._binding(),
              ..._controls(),
              ..._data(),
              ..._debug(),
              ..._editing(),
              ..._focus(),
              ..._foundation(),
              ..._framework(),
              ..._gestures(),
              ..._layout(),
              ..._navigation(),
              ..._overlay(),
              ..._scroll(),
              ..._semantics(),
              ..._style(),
              ..._text(),
            ],
          ),
        ),
      ),
    ),
  );
}
