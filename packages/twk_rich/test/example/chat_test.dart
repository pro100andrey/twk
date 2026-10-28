// The agent chat of example/chat.dart in the inline mode: the messages in
// the terminal's history, the answer streaming in below them and going to
// it a block at a time, the prompt that stays, Esc and Ctrl+C.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/chat.dart';

/// The chat started below a shell's prompt on a terminal of [height] rows,
/// as `main` runs it.
/// With [kittyKeyboard] Escape comes at once, without the pause that tells
/// it apart.
Future<void> start(
  TwkTester t, {
  int height = 14,
  bool kittyKeyboard = false,
}) => t.pumpWidget(
  const Chat(),
  size: (70, height),
  mode: ScreenMode.inline,
  history: [r'$ dart run example/chat.dart'],
  clearInlineOnExit: true,
  kittyKeyboard: kittyKeyboard,
);

/// Types [question], sends it, and waits until the answer has ended.
Future<void> ask(TwkTester t, String question) async {
  await t.type(question);
  await t.press('enter');
  await t.pumpUntilIdle();
}

/// The history and the screen, the empty rows that end it left out.
List<String> transcript(TwkTester t) {
  final lines = [...t.scrollback, ...t.lines];
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// The prompt, empty, and the keys below it: the field's Enter first.
const prompt = '''
╭────────────────────────────────────────────────────────────────────╮
│ › Ask something; Enter sends                                       │
╰────────────────────────────────────────────────────────────────────╯
enter submit   ctrl+c quit''';

/// The prompt, emptied once a question was sent, which Ctrl+Z puts back.
const sentPrompt = '''
╭────────────────────────────────────────────────────────────────────╮
│ › Ask something; Enter sends                                       │
╰────────────────────────────────────────────────────────────────────╯
enter submit   ctrl+z undo   ctrl+c quit''';

/// The first answer, as the history shows it.
const firstAnswer = r'''
  To read a file, use File from dart:io:

   import 'dart:io';

   Future<void> main() async {
     final text = await File('notes.txt').readAsString();
     print(text.split('\n').length);
   }

  For a large file, read it as a stream of lines instead:

  • openRead() gives its bytes in chunks;
  • utf8.decoder and LineSplitter make lines of them.''';

void main() {
  testTwk('the greeting goes to the history below the shell, the prompt '
      'below it with the cursor in it', (t) async {
    await start(t);
    expect(
      t,
      matchesScreen('''
\$ dart run example/chat.dart

  A chat with scripted answers. Each is Markdown, streamed in pieces;
  a block of it goes to the terminal's history once complete.

$prompt
'''),
    );
    expect(t, styleAt(2, 2, hasAttr(Attr.bold)));
    expect(t, cursorAt(4, 6));
  });

  testTwk('Enter sends: the question goes to the history, the answer comes '
      'in pieces below it, each block of it going to the history once '
      'complete, and the region gives back the rows it took', (t) async {
    await start(t);
    await t.type('how do I read a file?');
    await t.press('enter');
    await t.pump(pieceInterval * 10);
    expect(
      t,
      matchesScreen('''

  A chat with scripted answers. Each is Markdown, streamed in pieces;
  a block of it goes to the terminal's history once complete.

› how do I read a file?

  To read a file, use File from dart:io:

   im

╭────────────────────────────────────────────────────────────────────╮
│ › Ask something; Enter sends                                       │
╰────────────────────────────────────────────────────────────────────╯
⠹ answering enter submit   ctrl+z undo   esc stop   ctrl+c quit
'''),
    );
    // the paragraph is complete: above the region, in the history
    expect(t.binding.twkApp.screen.height, 7);

    await t.pumpUntilIdle();
    expect(
      transcript(t).join('\n'),
      '''
\$ dart run example/chat.dart

  A chat with scripted answers. Each is Markdown, streamed in pieces;
  a block of it goes to the terminal's history once complete.

› how do I read a file?

$firstAnswer

$sentPrompt''',
    );
    // written above the region: the terminal scrolled it into its history
    expect(t.scrollback, hasLength(11));
    expect(t.binding.twkApp.screen.height, 5);
  });

  testTwk('on a terminal shorter than the answer, a block goes to the '
      'history once complete, the terminal scrolling it, while the rest '
      'comes above the prompt, which stays', (t) async {
    await start(t, height: 10);
    await t.type('how do I read a file?');
    await t.press('enter');
    await t.pump(pieceInterval * 30);
    expect(t.scrollback.last, '  To read a file, use File from dart:io:');
    expect(t.lines.sublist(0, 9), [
      '',
      "   import 'dart:io';",
      '',
      '   Future<void> main() async {',
      "     final text = await File('notes.txt').readAsString();",
      '',
      ...prompt.split('\n').take(3),
    ]);

    await t.pumpUntilIdle();
    expect(transcript(t).join('\n'), contains('$firstAnswer\n\n$sentPrompt'));
  });

  testTwk('the answers come in turn, the first again after the last', (
    t,
  ) async {
    await start(t);
    for (final question in ['file?', 'tests?', 'the change?', 'file again?']) {
      await ask(t, question);
    }
    final lines = transcript(t);
    String after(String question) => lines[lines.indexOf('› $question') + 2];
    expect(after('file?'), '  To read a file, use File from dart:io:');
    expect(
      after('tests?'),
      '  Add test to the dev dependencies, then run the tests:',
    );
    expect(after('the change?'), '  This is what the change to greet does:');
    expect(after('file again?'), '  To read a file, use File from dart:io:');
  });

  testTwk('Esc stops the answer, what came of it going to the history; '
      'neither an empty prompt nor one sent while an answer comes sends '
      'anything', (t) async {
    await start(t);
    await t.press('enter');
    await t.type('  ');
    await t.press('enter');
    await t.pump();
    expect(t.lines.where((l) => l.startsWith('›')), isEmpty);

    await t.press('ctrl+u');
    await t.type('how do I read a file?');
    await t.press('enter');
    await t.pump(pieceInterval * 10);
    await t.type('and tests?');
    await t.press('enter');
    await t.press('escape');
    await t.pumpUntilIdle();
    expect(transcript(t).sublist(1).join('\n'), '''

  A chat with scripted answers. Each is Markdown, streamed in pieces;
  a block of it goes to the terminal's history once complete.

› how do I read a file?

  To read a file, use File from dart:io:

   import 'dart:i

╭────────────────────────────────────────────────────────────────────╮
│ › and tests?                                                       │
╰────────────────────────────────────────────────────────────────────╯
enter submit   ctrl+z undo   ctrl+c quit''');
  });

  testTwk('Esc before the first piece leaves the question alone in the '
      'history, the region as tall as the prompt', (t) async {
    await start(t, kittyKeyboard: true);
    await t.type('how do I read a file?');
    await t.press('enter');
    await t.pump();
    await t.press('escape');
    await t.pumpUntilIdle();
    expect(
      transcript(t).join('\n'),
      endsWith('once complete.\n\n› how do I read a file?\n\n$sentPrompt'),
    );
    expect(t.binding.twkApp.screen.height, 5);
  });

  testTwk('Ctrl+C quits: the history keeps the chat, the prompt is erased', (
    t,
  ) async {
    await start(t);
    await ask(t, 'how do I read a file?');
    await t.press('ctrl+c');
    expect(t.isRunning, isFalse);
    expect(transcript(t).join('\n'), endsWith(firstAnswer));
  });
}
