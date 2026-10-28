// A static screen: a header, two boxes side by side with text wrapped in
// them, and a footer; q quits.
//
//   dart run example/static_screen.dart           # on the alternate screen
//   dart run example/static_screen.dart --inline  # below the shell's history
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => runApp(
  const StaticScreen(),
  mode: args.contains('--inline') ? .inline : .fullscreen,
);

final class StaticScreen extends StatelessWidget {
  const StaticScreen({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'q': () => AppBinding.of(context).quit()},
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        Text.rich([' twk '.bold.reverse, ' widgets for terminal UIs'.dim]),
        const Expanded(
          child: Row(
            crossAxisAlignment: .stretch,
            gap: 1,
            children: [
              Expanded(
                child: _Panel(
                  'Layout',
                  'A Column stacks the header, this row and the footer, and '
                      'Expanded gives the row the lines the other two leave. '
                      'In the row two Expanded boxes share the width, a gap '
                      'of one cell between them.',
                ),
              ),
              Expanded(
                child: _Panel(
                  'Text',
                  'Text breaks its lines between words to fit its box. '
                      'Resize the terminal: the boxes share the new width '
                      'and the text is wrapped again.',
                ),
              ),
            ],
          ),
        ),
        Text.rich(['q'.bold, ' quit'.dim]),
      ],
    ),
  );
}

/// [text] in a box with a rounded border and [title] on its top edge.
final class _Panel extends StatelessWidget {
  const _Panel(this.title, this.text);

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Box(
    border: const .all(type: .rounded),
    titles: [BorderTitle(' $title ', style: const Style(attrs: Attr.bold))],
    padding: const .x(1),
    child: Text(text),
  );
}
