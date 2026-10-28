// The semantics of the controls annotated after the first ones: a Dialog
// as a dialog of its title; a window of a WindowLayer as one of its title,
// maximised, or minimised to its chip; a TabBar as a tablist of its tabs;
// a TextField and a TextArea as textboxes of their placeholders and texts,
// an obscured field as protected, never its characters; a ProgressBar as
// how much is done.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [children] one below another at their left edge.
Column column(List<Widget> children) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: children,
);

/// The lines the app reads as now.
List<String> read(TwkTester t) => t.binding.semantics.lines;

/// Which of them is the focused node's.
int? focusedLine(TwkTester t) => t.binding.semantics.focusedLine;

/// Presses each of [keys], apart by spaces, a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

void main() {
  testTwk('a dialog reads as a dialog of its title, or without one, then '
      'what is in it', (t) async {
    await t.pumpWidget(
      column([
        const Dialog(child: Text('plain')),
        Dialog(
          title: 'Quit',
          shadow: const BoxShadow(),
          child: column([
            const Text('Unsaved work'),
            Button('Yes', onPressed: () {}),
          ]),
        ),
      ]),
      size: (40, 12),
    );
    expect(read(t), [
      'dialog',
      'plain',
      'dialog Quit',
      'Unsaved work',
      'button Yes',
    ]);
  });

  testTwk('a dialog shown over the page leaves out what it covers, the '
      'node in it with the focus focused', (t) async {
    await t.pumpWidget(const Overlay(child: _Ask()), size: (40, 12));
    expect(read(t), ['page', 'button Ask']);
    await press(t, 'enter');
    expect(read(t), ['dialog Sure', 'Unsaved work', 'button Yes']);
    expect(focusedLine(t), 2);
  });

  testTwk('a window reads as a dialog of its title, then what is in it, '
      'without its title bar and buttons; maximised as its value; its '
      'title bar focused, the dialog is', (t) async {
    final notes = WindowController(width: 20, height: 4);
    final log = WindowController(top: 5, width: 20, height: 4);
    addTearDown(notes.dispose);
    addTearDown(log.dispose);
    await t.pumpWidget(
      WindowLayer(
        windows: [
          Window(
            title: 'Notes',
            controller: notes,
            onClose: () {},
            child: Button('Save', onPressed: () {}),
          ),
          Window(title: 'Log', controller: log, child: const Text('started')),
        ],
        child: const Text('desk'),
      ),
      size: (40, 12),
    );
    expect(read(t), [
      'desk',
      'dialog Notes',
      'button Save',
      'dialog Log',
      'started',
    ]);
    expect(focusedLine(t), isNull);
    await press(t, 'tab');
    expect(focusedLine(t), 1);
    await press(t, 'tab');
    expect(focusedLine(t), 2);
    await press(t, 'tab');
    expect(focusedLine(t), 3);
    await press(t, 'enter');
    expect(log.maximised, isTrue);
    expect(read(t), [
      'desk',
      'dialog Notes',
      'button Save',
      'dialog Log: maximised',
      'started',
    ]);
    expect(focusedLine(t), 3);
  });

  testTwk('a minimised window is read as its chip, a button of its title, '
      'minimised, and not as itself', (t) async {
    final notes = WindowController(width: 20, height: 4, minimised: true);
    addTearDown(notes.dispose);
    await t.pumpWidget(
      WindowLayer(
        windows: [
          Window(
            title: 'Notes',
            controller: notes,
            child: Button('Save', onPressed: () {}),
          ),
          const Window(title: 'Log', child: Text('started')),
        ],
        child: const Text('desk'),
      ),
      size: (60, 20),
    );
    expect(read(t), [
      'desk',
      'dialog Log',
      'started',
      'button Notes: minimised',
    ]);
    await press(t, 'tab tab');
    expect(focusedLine(t), 3);
    await press(t, 'enter');
    expect(notes.minimised, isFalse);
    expect(read(t), [
      'desk',
      'dialog Notes',
      'button Save',
      'dialog Log',
      'started',
    ]);
    expect(focusedLine(t), 1);
  });

  testTwk('a tab bar reads as a tablist of its tabs, the selected one '
      'selected, and focused while the bar has the focus', (t) async {
    final tabs = TabController(length: 3);
    addTearDown(tabs.dispose);
    await t.pumpWidget(
      column([
        TabBar(controller: tabs, tabs: const ['Files', 'Search', 'Git']),
        SizedBox(
          height: 1,
          child: TabView(
            controller: tabs,
            children: const [Text('file list'), Text('query'), Text('log')],
          ),
        ),
        Button('Go', onPressed: () {}),
      ]),
    );
    expect(read(t), [
      'tablist',
      'tab Files, selected',
      'tab Search',
      'tab Git',
      'file list',
      'button Go',
    ]);
    expect(focusedLine(t), isNull);
    await press(t, 'tab');
    expect(focusedLine(t), 1);
    await press(t, 'right');
    expect(read(t), [
      'tablist',
      'tab Files',
      'tab Search, selected',
      'tab Git',
      'query',
      'button Go',
    ]);
    expect(focusedLine(t), 2);
    await press(t, 'tab');
    expect(focusedLine(t), 5);
    tabs.index = 2;
    await t.pump();
    expect(read(t).sublist(1, 5), [
      'tab Files',
      'tab Search',
      'tab Git, selected',
      'log',
    ]);
  });

  testTwk('a text field and a text area read as textboxes of their '
      'placeholders, their texts as they are typed as their values, a '
      "line for each of the area's lines", (t) async {
    final notes = TextEditingController();
    addTearDown(notes.dispose);
    await t.pumpWidget(
      column([
        const TextField(placeholder: 'Name', autofocus: true),
        const TextField(),
        TextArea(controller: notes, placeholder: 'Notes'),
      ]),
    );
    expect(read(t), ['textbox Name', 'textbox', 'textbox Notes']);
    expect(focusedLine(t), 0);
    await t.type('anna');
    await t.pump();
    expect(read(t), ['textbox Name: anna', 'textbox', 'textbox Notes']);
    await press(t, 'tab tab');
    await t.type('first');
    await press(t, 'enter');
    await t.type('second');
    await t.pump();
    expect(notes.text, 'first\nsecond');
    expect(read(t), [
      'textbox Name: anna',
      'textbox',
      'textbox Notes: first',
      'second',
    ]);
    expect(focusedLine(t), 2);
  });

  testTwk('an obscured field reads as protected, typed in or not, and '
      'never its characters, nor on the screen in the screen-reader mode', (
    t,
  ) async {
    final password = TextEditingController(text: 'hunter2');
    addTearDown(password.dispose);
    await t.pumpWidget(
      column([
        TextField(
          controller: password,
          placeholder: 'Password',
          obscureText: true,
          autofocus: true,
        ),
        const TextField(obscureText: true, placeholder: 'Again'),
      ]),
      mode: ScreenMode.inline,
      size: (40, 4),
    );
    expect(read(t), [
      'textbox Password: protected',
      'textbox Again: protected',
    ]);
    await t.type('42');
    await t.pump();
    expect(password.text, 'hunter242');
    expect(read(t), [
      'textbox Password: protected',
      'textbox Again: protected',
    ]);
    t.binding.screenReader = true;
    await t.pump();
    expect(t.lines.take(2), [
      'textbox Password: protected',
      'textbox Again: protected',
    ]);
    expect(t.lines.join('\n'), isNot(contains('hunter')));
  });

  testTwk('a progress bar reads as how much is done in percent, a value '
      'beyond 0 and 1 as the nearest, and without one while it is not '
      'known', (t) async {
    await t.pumpWidget(
      column(const [
        ProgressBar(value: 0.4),
        ProgressBar(value: 0.333),
        ProgressBar(value: 1.5),
        ProgressBar(value: -1),
        ProgressBar(value: double.nan),
        ProgressBar(),
      ]),
      size: (20, 6),
    );
    expect(read(t), [
      'progressbar 40%',
      'progressbar 33%',
      'progressbar 100%',
      'progressbar 0%',
      'progressbar 0%',
      'progressbar',
    ]);
  });
}

/// A page with a button that asks in a [Dialog].
final class _Ask extends StatelessWidget {
  const _Ask();

  @override
  Widget build(BuildContext context) => column([
    const Text('page'),
    Button(
      'Ask',
      autofocus: true,
      onPressed: () => showDialog<void>(
        context,
        (_) => Dialog(
          title: 'Sure',
          child: column([
            const Text('Unsaved work'),
            Button('Yes', autofocus: true, onPressed: () {}),
          ]),
        ),
      ),
    ),
  ]);
}
