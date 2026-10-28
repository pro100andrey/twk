// The screen modes guide's app (doc/guides/screen-modes.md): a prompt
// below the shell's history. Each line sent goes into the terminal's
// scrollback above the field, which alone stays in the app's rows;
// Ctrl+C quits, leaving the lines where they are.
//
//   dart run example/guides/inline.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Prompt(), mode: .inline);

final class Prompt extends StatefulWidget {
  const Prompt({super.key});

  @override
  State<Prompt> createState() => _PromptState();
}

final class _PromptState extends State<Prompt> {
  final _sent = <String>[];
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      // written once each, into the scrollback; only ever appended to
      Static(items: _sent, builder: (context, line) => Text('> $line')),
      TextField(
        controller: _text,
        placeholder: 'say something, Enter sends',
        autofocus: true,
        onSubmitted: (line) {
          setState(() => _sent.add(line));
          _text.clear();
        },
      ),
    ],
  );
}
