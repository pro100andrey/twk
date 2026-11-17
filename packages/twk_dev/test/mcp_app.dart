// The app the MCP process test drives: `up` counts, a button "Save"
// counts saves and logs them, `l` logs, `q` quits; a timer clears a notice
// a second after a save.
import 'dart:async';

import 'package:twk/twk.dart';
import 'package:twk_core/terminal.dart' show LogLevel, LogRecord;

Future<void> main() => runApp(const _Counter());

final class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

final class _CounterState extends State<_Counter> {
  var _n = 0;
  var _saved = 0;
  var _notice = false;

  void _log(String message) => AppBinding.of(context).twkApp.logs.add(
    LogRecord(DateTime.now(), LogLevel.info, message),
  );

  void _save() {
    setState(() {
      _saved++;
      _notice = true;
    });
    _log('saved $_saved');
    Timer(const Duration(seconds: 1), () => setState(() => _notice = false));
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => setState(() => _n++),
      'l': () => _log('pressed l'),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Column(
      children: [
        Text('Count: $_n'),
        Text('Saved: $_saved'),
        if (_notice) const Text('Notice: saved'),
        Button('Save', onPressed: _save),
      ],
    ),
  );
}
