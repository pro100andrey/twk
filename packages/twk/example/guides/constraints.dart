// The layout guide's constraints app (doc/guides/layout.md): a text kept
// between 10 and 30 cells wide by BoxConstraints, and a line that tells
// the room the LayoutBuilder above it was given.
//
//   dart run example/guides/constraints.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Constraints());

final class Constraints extends StatelessWidget {
  const Constraints({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'q': () => AppBinding.of(context).quit()},
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: .start,
        children: [
          // the room this part of the app is given, in cells
          Text('room: ${constraints.maxWidth} x ${constraints.maxHeight}'),
          // minWidth, maxWidth, minHeight, maxHeight: at most 30 wide, any
          // height
          const ConstrainedBox(
            constraints: BoxConstraints(minWidth: 10, maxWidth: 30),
            child: Box(
              border: .all(type: .rounded),
              child: Text(
                'A message that wraps at thirty cells, however wide the '
                'terminal is.',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
