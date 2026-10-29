---
title: "Screen modes"
about: "Full screen, inline below the shell's prompt, or a fixed rectangle of the screen."
order: 5
---
# Screen modes

The same widgets run in three places on the terminal.

| mode | how | for |
| --- | --- | --- |
| full screen | `runApp(app)` | an app that is its own screen: an editor, a monitor, a file manager |
| inline | `runApp(app, mode: .inline)` | a prompt, a chat, a progress view that stays in the shell's history |
| fixed viewport | `runApp(app, viewport: Viewport.fixed(left, top, width, height), mode: .inline)` | a panel in a rectangle of the screen, the rest left alone |

## Full screen

The app takes the terminal's alternate screen, all of it, at its size; it
follows resizes, and what the terminal showed before comes back when the
app ends. Only full screen gets the mouse.

## Inline

The app takes rows of the normal screen from the prompt down, as many as
it asks for (its height when unconstrained), and grows and shrinks with
them. When it ends, its rows stay in the terminal's history with the
shell's output.

<!-- file: packages/twk/example/guides/inline.dart -->
```dart
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
```

`Static(items:, builder:)` is output that is finished once shown: inline,
each new item is written once into the terminal's scrollback above the
app's rows and takes no rows of them. Here only the field stays in the
app's rows, however much was said. Items are told apart by their index,
so a `Static`'s list is only appended to. Full screen, the same items
show in place, one below another.

Inline, a list asks for no rows: give it a height
(`SizedBox(height: 16, child: ...)`).

## Where the output is no terminal

In a pipe or a CI log, `runApp` writes no escape sequences: the app's
last frame is written as plain text when it ends, and an inline app's
`Static` items as they come.

| | |
| --- | --- |
| ![Static](../../packages/gallery/doc/shots/app/static.dark.svg)<br>**[Static](../widgets/app/static.md)** | ![Viewport](../../packages/gallery/doc/shots/app/viewport.dark.svg)<br>**[Viewport](../widgets/app/viewport.md)** |

For a command-line tool that prints lines, asks a question or two and
shows progress — and must work just as well with nobody at the keyboard —
there is twk's console,
[`package:twk/cli.dart`](https://github.com/pro100andrey/twk/tree/main/packages/twk/doc/reference/cli.md).
