// Two shells side by side, each in a TerminalView: a click or Alt+1 and
// Alt+2 focus one, the divider drags (or Tab onto it from nowhere), Ctrl+Q
// quits, and so does the end of both shells.
//
//   dart run example/split_shells.dart [shell]
//
// The shell is $SHELL, or sh, unless named.
import 'dart:io';

import 'package:twk/twk.dart';
import 'package:twk_term/twk_term.dart';

Future<void> main(List<String> args) => runApp(
  SplitShells(shell: args.isNotEmpty ? args.first : null),
  exitOnCtrlC: false,
);

final class SplitShells extends StatefulWidget {
  const SplitShells({super.key, this.shell});

  /// The program each pane runs; $SHELL, or sh, when null.
  final String? shell;

  @override
  State<SplitShells> createState() => _SplitShellsState();
}

final class _SplitShellsState extends State<SplitShells> {
  late final List<TerminalSession> _sessions;
  final _nodes = [
    FocusNode(debugLabel: 'left'),
    FocusNode(debugLabel: 'right'),
  ];

  static const _keys = ['ctrl+q', 'alt+1', 'alt+2'];

  @override
  void initState() {
    super.initState();
    final shell = widget.shell ?? Platform.environment['SHELL'] ?? 'sh';
    _sessions = [
      for (var i = 0; i < 2; i++)
        TerminalSession.start(shell, const [])..addListener(_changed),
    ];
    for (final node in _nodes) {
      node.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final session in _sessions) {
      session.dispose();
    }
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  var _titles = const ['', ''];
  var _ended = const [false, false];

  /// A title, a focus or an end changed: the borders show it, and the app
  /// quits once both shells ended.
  void _changed() {
    final titles = [for (final s in _sessions) s.title];
    final ended = [for (final s in _sessions) s.ended];
    if (ended.every((e) => e)) {
      AppBinding.of(context).quit();
      return;
    }
    setState(() {
      _titles = titles;
      _ended = ended;
    });
  }

  Widget _pane(BuildContext context, int i) {
    final focused = _nodes[i].hasFocus;
    final title = _ended[i]
        ? ' ${i + 1}: ended '
        : ' ${i + 1}: ${_titles[i].isEmpty ? 'shell' : _titles[i]} ';
    return Box(
      border: Border.all(
        type: BorderType.rounded,
        style: focused ? Theme.of(context).primary : const Style(),
      ),
      titles: [BorderTitle(title)],
      child: TerminalView(
        session: _sessions[i],
        focusNode: _nodes[i],
        autofocus: i == 0,
        ignoredKeys: _keys,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'ctrl+q': () => AppBinding.of(context).quit(),
      'alt+1': _nodes[0].requestFocus,
      'alt+2': _nodes[1].requestFocus,
    },
    hints: const {'alt+1': 'left', 'alt+2': 'right', 'ctrl+q': 'quit'},
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        Expanded(
          child: SplitView(
            panes: [
              SplitPane(child: _pane(context, 0), minSize: 10),
              SplitPane(child: _pane(context, 1), minSize: 10),
            ],
          ),
        ),
        const KeyHintsBar(),
      ],
    ),
  );
}
