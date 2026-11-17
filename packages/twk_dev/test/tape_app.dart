// The app the tape's process test drives: `Save` counts saves; `Under` is a
// button another, `Over`, covers entirely.
import 'package:twk/twk.dart';

Future<void> main() => runApp(const _App());

final class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

final class _AppState extends State<_App> {
  var _saved = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('Saved: $_saved'),
      Button('Save', onPressed: () => setState(() => _saved++)),
      SizedBox(
        height: 1,
        child: Stack(
          children: [
            Button('Under', onPressed: () {}),
            Positioned.fill(child: Button('Over', onPressed: () {})),
          ],
        ),
      ),
    ],
  );
}
