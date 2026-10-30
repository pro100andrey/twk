# Examples

Each runs from the package's directory: `dart run example/<file>.dart`.

| file | what it shows |
| --- | --- |
| [viewer.dart](viewer.dart) | a viewer of Markdown files and diffs: a diff, `git diff --color`'s too, unified or side by side (Tab), any other file as Markdown, its text selected and copied with the mouse; q quits |
| [chat.dart](chat.dart) | a chat in the inline mode, its scripted answers streamed into a `MarkdownStream`, each block put in the terminal's history once it is complete; Esc stops an answer, Ctrl+C quits |
| [image/viewer.dart](image/viewer.dart) | a PNG or JPEG file with the terminal's graphics protocol or in blocks: f cycles the fit, p what it is drawn with, q quits |
| [image/konsole_images.dart](image/konsole_images.dart) | a kitty image in a header above a log that scrolls in hardware, for Konsole |

A document that scrolls, its text selected with the mouse:

```dart
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';

const text = '''
# Notes

Markdown in a terminal: *emphasis*, **strong**, `code`, [links](https://dart.dev)
and lists:

- one
- two
''';

Future<void> main() => runApp(const Notes());

final class Notes extends StatelessWidget {
  const Notes({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'q': () => AppBinding.of(context).quit()},
    child: const SelectionArea(
      child: SingleChildScrollView(child: MarkdownView(text)),
    ),
  );
}
```

The viewer and the chat have their tests in
[test/example/](https://github.com/pro100andrey/twk/tree/main/packages/twk_rich/test/example).
