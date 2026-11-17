// The app the driver tests of twk_test run: `up` counts, a button "Save"
// saves, `d` shows "Done" two seconds (of the app's time) later, `l` logs a
// warning, `x` writes a sequence no terminal takes before the next frame, `q`
// quits (`--inline`: in the normal screen). A red
// word shows what colors the terminal profile gives it.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:twk/log.dart';
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => runApp(
  const _Demo(),
  mode: args.contains('--inline') ? ScreenMode.inline : ScreenMode.fullscreen,
);

final class _Demo extends StatefulWidget {
  const _Demo();

  @override
  State<_Demo> createState() => _DemoState();
}

final class _DemoState extends State<_Demo> {
  var _n = 0;
  var _saved = 0;
  var _done = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => setState(() => _n++),
      'd': () {
        _timer = Timer(
          const Duration(seconds: 2),
          () => setState(() => _done = true),
        );
      },
      'x': () {
        AppBinding.of(context).twkApp.terminal.write(
          Uint8List.fromList(utf8.encode('\x1b=')),
        );
        setState(() => _n++);
      },
      'l': () => log('logged at $_n', level: LogLevel.warning),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Count: $_n'),
        Text('Saved: $_saved'),
        const Text('Red', style: Style(fg: Color.rgb(200, 30, 30))),
        if (_done) const Text('Done'),
        Button('Save', onPressed: () => setState(() => _saved++)),
      ],
    ),
  );
}
