part of '../sample_app.dart';

extension on _SampleAppState {
  List<Widget> _debug() => const [Expanded(child: _Console())];
}

/// The app's log console over a line of text.
final class _Console extends StatefulWidget {
  const _Console();

  @override
  State<_Console> createState() => _ConsoleState();
}

final class _ConsoleState extends State<_Console> {
  final _console = ConsoleController(LogSink());

  @override
  void dispose() {
    _console.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Console(controller: _console, child: const Text('under the console'));
}
