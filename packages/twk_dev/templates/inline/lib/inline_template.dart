import 'dart:async';

import 'package:twk/twk.dart';

/// What the app answers to [line], after [thinking].
String answer(String line) {
  final words = line.trim().split(RegExp(r'\s+')).length;
  return 'You said "$line": $words ${words == 1 ? 'word' : 'words'}.';
}

/// How long the app thinks before it answers.
const thinking = Duration(milliseconds: 600);

/// A prompt below the shell's: each line sent goes to the terminal's
/// scrollback with the app's answer under it, a spinner turning while the
/// app thinks; the field and the keys alone stay in the app's rows. Enter
/// sends, Ctrl+Q quits.
final class Chat extends StatefulWidget {
  const Chat({super.key});

  @override
  State<Chat> createState() => _ChatState();
}

final class _ChatState extends State<Chat> {
  /// The lines sent and answered, oldest first: who and what.
  final _said = <(String, String)>[];
  final _text = TextEditingController();

  /// Answers the line sent last while the app thinks.
  Timer? _thinking;

  @override
  void dispose() {
    _thinking?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _send(String line) {
    if (line.trim().isEmpty || _thinking != null) {
      return;
    }
    _text.clear();
    setState(() {
      _said.add(('you', line));
      _thinking = Timer(thinking, () {
        setState(() {
          _said.add(('app', answer(line)));
          _thinking = null;
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      // not 'q': the field takes it as text
      {'ctrl+q': () => AppBinding.of(context).quit()},
      hints: const {'ctrl+q': 'quit'},
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          // written once each, to the scrollback above the app's rows
          Static(
            items: _said,
            builder: (context, said) => switch (said) {
              ('you', final line) => Text.rich([
                Span('> ', theme.primary).bold,
                Span(line),
              ]),
              (_, final line) => Text(line, style: theme.muted),
            },
          ),
          if (_thinking != null)
            Row(
              gap: 1,
              children: [
                Spinner(style: theme.primary),
                const Text('thinking…'),
              ],
            ),
          TextField(
            controller: _text,
            placeholder: 'say something, Enter sends it',
            onSubmitted: _send,
            autofocus: true,
          ),
          const KeyHintsBar(),
        ],
      ),
    );
  }
}
