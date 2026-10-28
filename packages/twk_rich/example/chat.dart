// An agent chat in the inline mode, below the shell's history. What you
// send and what the agent answers go to the terminal's history above the
// prompt (Static), where the terminal scrolls and selects them like
// anything printed. The answers are scripted, with no model behind them:
// Markdown with code in it, streamed a few characters at a time into a
// MarkdownStream, which parses again only what each piece may change.
// Each block of an answer goes to the history once it is complete
// (MarkdownStream.takeSettled), the rest shown live above the prompt
// (MarkdownView.blocks), and the region gives back the rows the block
// took in it. Enter sends, Esc stops an answer, Ctrl+C quits and leaves
// the chat in the history.
//
//   dart run example/chat.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';

Future<void> main() =>
    runApp(const Chat(), mode: .inline, clearInlineOnExit: true);

/// What the agent says first.
const greeting =
    '**A chat with scripted answers.** Each is Markdown, streamed in '
    "pieces; a block of it goes to the terminal's history once complete.";

/// The answers, one after another, then from the first again.
const answers = [
  r'''
To read a file, use `File` from `dart:io`:

```dart
import 'dart:io';

Future<void> main() async {
  final text = await File('notes.txt').readAsString();
  print(text.split('\n').length);
}
```

For a **large** file, read it as a stream of lines instead:

- `openRead()` gives its bytes in chunks;
- `utf8.decoder` and `LineSplitter` make lines of them.
''',
  '''
Add `test` to the dev dependencies, then run the tests:

```bash
dart pub add dev:test
dart test --reporter=expanded
```

A test of `greet`, in `test/greet_test.dart`:

```dart
import 'package:test/test.dart';

void main() {
  test('greets by name', () {
    expect(greet('Ada'), 'Hello, Ada!');
  });
}
```
''',
  r'''
This is what the change to `greet` does:

```diff
-String greet(String name) {
-  return 'Hello, ' + name + '!';
+String greet(String name, {String language = 'en'}) {
+  return '${hello[language]}, $name!';
```

| language | greeting |
|----------|----------|
| `en`     | Hello    |
| `uk`     | Привіт   |

> The names are *not* translated.
''',
];

/// How often the next piece of an answer comes.
const pieceInterval = Duration(milliseconds: 20);

/// The characters in a piece of an answer.
const pieceLength = 6;

/// The chat, in the theme of the terminal's brightness.
final class Chat extends StatelessWidget {
  const Chat({super.key});

  @override
  Widget build(BuildContext context) =>
      const Theme.adaptive(child: _Conversation());
}

final class _Conversation extends StatefulWidget {
  const _Conversation();

  @override
  State<_Conversation> createState() => _ConversationState();
}

final class _ConversationState extends State<_Conversation> {
  /// What the history shows, oldest first: what the user sent, a
  /// [String], and the blocks of what the agent said, [MdBlock]s.
  final _history = <Object>[...parseMarkdown(greeting)];

  final _input = TextEditingController();

  /// How many answers were given: the next is the one after them.
  var _answered = 0;

  /// The answer coming in, so far; null when none is.
  MarkdownStream? _answer;

  /// What brings the next piece of the answer.
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty || _answer != null) {
      return;
    }
    final answer = answers[_answered++ % answers.length].runes.toList();
    var shown = 0;
    setState(() {
      _history.add(text);
      _answer = MarkdownStream();
    });
    _input.clear();
    _timer = Timer.periodic(pieceInterval, (_) {
      final next = math.min(shown + pieceLength, answer.length);
      _take(String.fromCharCodes(answer, shown, next));
      shown = next;
      if (shown == answer.length) {
        _finish();
      }
    });
  }

  /// Adds [piece] to the answer coming in, or with [piece] null ends it;
  /// the blocks of it that are complete go to the history.
  void _take(String? piece) {
    final answer = _answer!;
    setState(() {
      if (piece == null) {
        answer.close();
        _answer = null;
      } else {
        answer.add(piece);
      }
      _history.addAll(answer.takeSettled());
    });
  }

  /// Ends the answer coming in: what came of it goes to the history.
  void _finish() {
    _timer?.cancel();
    _timer = null;
    _take(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answer = _answer;
    final live = answer?.live ?? const [];
    return KeyBindings(
      {
        'escape': answer == null ? null : _finish,
        'ctrl+c': () => AppBinding.of(context).quit(),
      },
      hints: const {'escape': 'stop', 'ctrl+c': 'quit'},
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Static(items: _history, builder: _entry),
          // on a short terminal the answer gives up rows, not the prompt
          if (live.isNotEmpty)
            Flexible(
              child: _agent(
                MarkdownView.blocks(live, definitions: answer!.definitions),
              ),
            ),
          Padding(
            padding: const .only(top: 1),
            child: Box(
              border: Border.all(type: .rounded, style: theme.border),
              padding: const .x(1),
              child: Row(
                gap: 1,
                children: [
                  Text.rich([Span('›', theme.primary).bold]),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      autofocus: true,
                      placeholder: 'Ask something; Enter sends',
                      onSubmitted: _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            gap: 1,
            children: [
              if (answer != null) ...[
                Spinner(style: theme.accent),
                Text('answering', style: theme.muted),
              ],
              const Expanded(child: KeyHintsBar()),
            ],
          ),
        ],
      ),
    );
  }

  /// [entry] of the history as it shows there.
  Widget _entry(BuildContext context, Object entry) => switch (entry) {
    final MdBlock block => _agent(MarkdownView.blocks([block])),
    _ => Padding(
      padding: const .only(top: 1),
      child: Text.rich([
        Span('› ', Theme.of(context).primary).bold,
        Span('$entry'),
      ]),
    ),
  };

  /// What the agent said, [view], a row below what is before it and two
  /// columns in, as the blocks of a view are apart.
  static Widget _agent(Widget view) =>
      Padding(padding: const .only(top: 1, left: 2), child: view);
}
