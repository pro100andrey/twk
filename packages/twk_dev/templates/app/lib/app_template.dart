import 'package:twk/twk.dart';

/// The app's name, in its title bar.
const appName = 'app_template';

/// A note: its [title] and its [body].
final class Note {
  const Note(this.title, this.body);

  final String title;
  final String body;
}

/// The notes the app shows.
const notes = [
  Note(
    'Welcome',
    'This app was made by twk create. The list on the left chooses a '
        'note, this pane shows it.',
  ),
  Note(
    'Keys',
    'Up and Down choose a note, Enter opens it: Up and Down scroll it '
        'then, Escape goes back to the list. Tab moves between the two, a '
        'click focuses a pane. Ctrl+Q quits.',
  ),
  Note(
    'Code',
    'The app is in lib/, started by bin/main.dart; its tests are in '
        'test/.',
  ),
  Note(
    'Hot reload',
    'dart run twk_dev:twk run bin/main.dart runs the app and reloads it as '
        'the files of lib/ change, the note chosen kept.',
  ),
];

/// [notes] in a list beside the one chosen, the app's name above them and
/// the keys below: Up and Down choose a note, Enter opens it and Escape
/// goes back to the list, Tab moves between the two, Ctrl+Q quits.
final class NotesApp extends StatefulWidget {
  const NotesApp(this.notes, {super.key});

  final List<Note> notes;

  @override
  State<NotesApp> createState() => _NotesAppState();
}

final class _NotesAppState extends State<NotesApp> {
  // the note chosen, by index; the first at the start
  final _chosen = SelectionController<int>(selected: const [0]);
  final _listNode = FocusNode();
  final _noteNode = FocusNode();

  @override
  void dispose() {
    _chosen.dispose();
    _listNode.dispose();
    _noteNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      {'ctrl+q': () => AppBinding.of(context).quit()},
      hints: const {'ctrl+q': 'quit'},
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          StatusBar(
            left: Text.rich([Span(' $appName ', theme.primary).bold]),
            right: Text('${widget.notes.length} notes '),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: .stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: _Pane(
                    'Notes',
                    _listNode,
                    // Enter while the list has the focus
                    KeyBindings(
                      {'enter': _noteNode.requestFocus},
                      hints: const {'enter': 'open'},
                      child: SelectionList<int>(
                        itemCount: widget.notes.length,
                        keyOf: (i) => i,
                        itemBuilder: (context, i) =>
                            Text(widget.notes[i].title),
                        controller: _chosen,
                        focusNode: _listNode,
                        autofocus: true,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  // rebuilt as the note chosen changes
                  child: ListenableBuilder(
                    listenable: _chosen,
                    builder: (context, _) {
                      final note = widget.notes[_chosen.selected.first];
                      return _Pane(
                        note.title,
                        _noteNode,
                        // Escape while the note has the focus
                        KeyBindings(
                          {'escape': _listNode.requestFocus},
                          hints: const {'escape': 'back'},
                          child: SingleChildScrollView(
                            focusNode: _noteNode,
                            child: Text(note.body),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // the keys of the pane with the focus, and Ctrl+Q
          const KeyHintsBar(),
        ],
      ),
    );
  }
}

/// [child] in a box titled [title], its border in the theme's primary
/// color while [node] has the focus; a press in it gives [node] the focus.
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
          border: .all(type: .rounded, style: style),
          titles: [BorderTitle(' $title ', style: style)],
          padding: const .x(1),
          child: child,
        );
      },
      child: child,
    ),
  );
}
