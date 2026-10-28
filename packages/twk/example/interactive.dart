// A chat: the messages in a list that follows the new ones while it shows
// the end, the others writing every two seconds; who is here beside it; a
// field to write in below. Tab and Shift+Tab move the focus from pane to
// pane, a click gives it to the pane clicked. The arrows, PageUp,
// PageDown, Home and End scroll the list that has the focus, the wheel the
// one under the mouse, and the scrollbar's thumb drags. Enter sends what
// is written, or on a name mentions it. F1 shows the keys in place of the
// panes: nothing there reads the mouse, so the terminal keeps it and its
// own selection works. Ctrl+C quits.
//
//   dart run example/interactive.dart           # on the alternate screen
//   dart run example/interactive.dart --inline  # below the shell's history
//
// Inline, the terminal keeps the mouse: Tab moves the focus.
import 'dart:async';

import 'package:twk/twk.dart';

Future<void> main(List<String> args) {
  final inline = args.contains('--inline');
  return runApp(
    // inline, the region is as tall as the app asks to be, and a list asks
    // for no rows: the box asks for 16
    inline ? const SizedBox(height: 16, child: Chat()) : const Chat(),
    mode: inline ? .inline : .fullscreen,
  );
}

/// Who is here.
const people = ['ann', 'bob', 'cleo', 'dev', 'eve', 'finn', 'gus', 'hal'];

/// What they say, in turn.
const said = [
  'morning all',
  'is the build green?',
  'it is now, my bad',
  'lunch at noon?',
  'the release notes are up for review',
  'who is on call this week?',
  'me, ping me if anything breaks',
];

/// Message [n] of the others.
(String, String) message(int n) =>
    (people[n % people.length], said[n % said.length]);

final class Chat extends StatefulWidget {
  const Chat({super.key});

  @override
  State<Chat> createState() => _ChatState();
}

final class _ChatState extends State<Chat> {
  /// Who said what, oldest first.
  final List<(String, String)> _messages = [
    for (var n = 0; n < 200; n++) message(n),
  ];
  final _list = ListController();
  final _text = TextEditingController();
  final _listNode = FocusNode();
  final _peopleNode = FocusNode();
  final _fieldNode = FocusNode();
  late final Timer _others;
  var _help = false;

  @override
  void initState() {
    super.initState();
    // the others write every two seconds
    _others = Timer.periodic(
      const Duration(seconds: 2),
      (_) => setState(() => _messages.add(message(_messages.length))),
    );
  }

  @override
  void dispose() {
    _others.cancel();
    _list.dispose();
    _text.dispose();
    _listNode.dispose();
    _peopleNode.dispose();
    _fieldNode.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) {
      return;
    }
    setState(() => _messages.add(('you', text)));
    _text.clear();
    // to the end, where the list then follows the new ones
    _list.ensureIndexVisible(_messages.length - 1);
  }

  void _mention(String name) {
    _text.insert('@$name ');
    _fieldNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'f1': () => setState(() => _help = !_help),
      'ctrl+c': () => AppBinding.of(context).quit(),
    },
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        Expanded(
          child: _help
              ? const _Help()
              : Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: .stretch,
                        children: [
                          Expanded(
                            child: _Pane(
                              'Messages',
                              _listNode,
                              Scrollbar(
                                child: ListView.builder(
                                  itemCount: _messages.length,
                                  itemBuilder: (context, i) {
                                    final (who, text) = _messages[i];
                                    return Text.rich([
                                      '$who: '.bold.fg(
                                        who == 'you' ? .green : .cyan,
                                      ),
                                      Span(text),
                                    ]);
                                  },
                                  stickToBottom: true,
                                  controller: _list,
                                  focusNode: _listNode,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 12,
                            child: _Pane(
                              'People',
                              _peopleNode,
                              SelectionList<String>(
                                itemCount: people.length,
                                keyOf: (i) => people[i],
                                itemBuilder: (context, i) => Text(people[i]),
                                onSubmitted: _mention,
                                focusNode: _peopleNode,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Pane(
                      'Write',
                      _fieldNode,
                      TextField(
                        controller: _text,
                        placeholder: 'a message, Enter sends it',
                        onSubmitted: _send,
                        focusNode: _fieldNode,
                        autofocus: true,
                      ),
                    ),
                  ],
                ),
        ),
        _KeyHints([
          ('tab', 'next pane'),
          ('enter', 'send'),
          ('f1', _help ? 'back' : 'help'),
          ('ctrl+c', 'quit'),
        ]),
      ],
    ),
  );
}

/// [child] in a box titled [title], its border in the theme's primary
/// color while [node] has the focus. A press in it gives [node] the focus.
final class _Pane extends StatelessWidget {
  const _Pane(this.title, this.node, this.child);

  final String title;
  final FocusNode node;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onDown: (_) => node.requestFocus(),
    behavior: .opaque,
    child: ListenableBuilder(
      listenable: node,
      builder: (context, child) {
        final theme = Theme.of(context);
        final style = node.hasFocus ? theme.primary : theme.border;
        return Box(
          border: Border.all(type: .rounded, style: style),
          titles: [BorderTitle(' $title ', style: style)],
          padding: const .only(left: 1),
          child: child,
        );
      },
      child: child,
    ),
  );
}

/// The keys, in place of the panes.
final class _Help extends StatelessWidget {
  const _Help();

  @override
  Widget build(BuildContext context) => Box(
    border: const .all(type: .rounded),
    titles: const [BorderTitle(' Keys ')],
    padding: const .x(1),
    child: Column(
      crossAxisAlignment: .start,
      children: [
        for (final (key, does) in const [
          ('tab, shift+tab', 'the next pane, the one before'),
          ('enter', 'send the message, mention the name'),
          ('↑ ↓ pgup pgdn', 'scroll the messages, move in the names'),
          ('home, end', 'to the first, to the last'),
          ('click', 'focus the pane'),
          ('wheel, drag', 'scroll the list under the mouse'),
          ('f1', 'back to the chat'),
          ('ctrl+c', 'quit'),
        ])
          Text.rich([key.padRight(16).bold, Span(does)]),
        const Text(''),
        const Text(
          'Nothing here uses the mouse: select text as in any terminal.',
        ),
      ],
    ),
  );
}

/// A row of [keys], each before what it does.
final class _KeyHints extends StatelessWidget {
  const _KeyHints(this.keys);

  final List<(String, String)> keys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      [
        for (final (key, does) in keys) ...[
          Span(' $key ', theme.primary).bold,
          Span('$does ', theme.muted),
        ],
      ],
      wrap: .none,
      overflow: .ellipsis,
    );
  }
}
