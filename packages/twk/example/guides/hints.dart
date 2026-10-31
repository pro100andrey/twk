// The layout guide's second app (doc/guides/layout.md): two panes side by
// side when the terminal is wide, one when it is narrow, and a key, `s`,
// that swaps the panes, which exists, and is hinted, only side by side.
//
//   dart run example/guides/hints.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Hints());

final class Hints extends StatefulWidget {
  const Hints({super.key});

  @override
  State<Hints> createState() => _HintsState();
}

final class _HintsState extends State<Hints> {
  var _swapped = false;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'q': () => AppBinding.of(context).quit()},
    hints: const {'q': 'quit'},
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxW >= 40;
              const one = Box(child: Text('one'));
              const two = Box(child: Text('two'));
              // below the LayoutBuilder, so the layout decides the key; the
              // layer stays in the tree, only its key comes and goes
              return KeyBindings(
                // null in a narrow layout: no key, so no hint
                {'s': wide ? () => setState(() => _swapped = !_swapped) : null},
                hints: const {'s': 'swap'},
                child: Focus(
                  autofocus: true,
                  child: wide
                      ? Row(
                          children: [
                            Expanded(child: _swapped ? two : one),
                            Expanded(child: _swapped ? one : two),
                          ],
                        )
                      : one,
                ),
              );
            },
          ),
        ),
        const KeyHintsBar(),
      ],
    ),
  );
}
