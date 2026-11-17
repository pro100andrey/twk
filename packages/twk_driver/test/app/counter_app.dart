// The app the driver's process test runs: `up` counts, a button "Save"
// saves, `q` quits, and it asks the terminal its queries on the way (twk's
// probe), which only an answering emulator can satisfy.
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => runApp(
  const _Counter(),
  mode: args.contains('--inline') ? ScreenMode.inline : ScreenMode.fullscreen,
);

final class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

final class _CounterState extends State<_Counter> {
  var _n = 0;
  var _saved = 0;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => setState(() => _n++),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Column(
      children: [
        Text('Count: $_n'),
        Text('Saved: $_saved'),
        Button('Save', onPressed: () => setState(() => _saved++)),
      ],
    ),
  );
}
