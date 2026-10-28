// The Screen readers group of the gallery.
import 'package:twk/twk.dart';

import '../page.dart';

/// The pages of the Screen readers group that draw.
final List<GalleryPage> screenReaderPages = [_semantics];

/// [parts] as one line of the Code, a line too long for this file.
String _line(List<String> parts) => parts.join();

/// The form's column.
const _fw = 19;

/// The page's width: the reading's longest line, after the focus bar.
const int _w = _fw + 2 + 35;

/// The popup's lines.
const _covered = 'the page under it';
const _over = 'the notice on top';

final _semantics = GalleryPage(
  group: 'Screen readers',
  title: 'Semantics',
  options: const [
    ChoiceOption(
      'view',
      'view',
      values: ['beside', 'reader'],
      labels: ['beside the form', 'TWK_SCREEN_READER=1'],
    ),
    SwitchOption('block', 'BlockSemantics', initial: true),
    SwitchOption('label', 'progress label', initial: true),
    // the heading on the screen, left out of what is read
    SwitchOption('exclude', 'ExcludeSemantics'),
  ],
  build: (context, o) => _SignIn(
    reader: o.label('view') != 'beside the form',
    block: o.flag('block'),
    label: o.flag('label'),
    exclude: o.flag('exclude'),
  ),
  code: _code,
);

/// The Code of the form's heading, in an ExcludeSemantics with [exclude].
List<String> _heading({required bool exclude}) {
  const node = [
    'Semantics(',
    '  role: .heading,',
    '  child: Text(',
    "    'Sign in',",
    '    style: theme.primary.merge(const .new(attrs: Attr.bold)),',
    '  ),',
    '),',
  ];
  return [
    for (final l
        in exclude
            ? [
                '// on the screen, left out of what is read',
                'ExcludeSemantics(',
                for (final (i, l) in node.indexed)
                  '${i == 0 ? '  child: ' : '  '}$l',
                '),',
              ]
            : node)
      '    $l',
  ];
}

/// The Code of the form, [nodes] with the focus nodes it reads, each line
/// after [pad].
List<String> _form(Options o, String pad, {required bool nodes}) => [
  'Column(',
  '  mainAxisSize: .min,',
  '  crossAxisAlignment: .start,',
  '  children: [',
  ..._heading(exclude: o.flag('exclude')),
  '    Checkbox(',
  '      value: _remember,',
  if (nodes) '      focusNode: _nodes[0],',
  '      onChanged: (v) => setState(() => _remember = v),',
  "      label: 'Remember me',",
  '    ),',
  '    Switch(',
  '      value: _dark,',
  if (nodes) '      focusNode: _nodes[1],',
  '      onChanged: (v) => setState(() => _dark = v),',
  "      label: 'Dark mode',",
  '    ),',
  '  ],',
  '),',
  'Row(',
  '  gap: 1,',
  '  children: [',
  '    // on the screen, not read: nodes: [] reads nothing of it',
  '    Semantics(',
  '      nodes: const [],',
  "      child: Text('Upload', style: theme.muted),",
  '    ),',
  '    Expanded(',
  if (o.flag('label'))
    '      // read as a progress bar: its label, then how much is done'
  else
    '      // read as how much is done alone',
  '      child: ProgressBar(',
  '        value: _done / 10,',
  '        style: theme.primary.merge(.new(bg: theme.surface.bg)),',
  if (o.flag('label')) "        semanticsLabel: 'Upload',",
  '      ),',
  '    ),',
  '  ],',
  '),',
  'Row(',
  '  gap: 1,',
  '  children: [',
  '    Button(',
  "      'More',",
  if (nodes) '      focusNode: _nodes[2],',
  '      onPressed: () =>',
  '          setState(() => _done = (_done + 1) % 11),',
  '    ),',
  if (nodes)
    "    Button('Cancel', focusNode: _nodes[3], onPressed: () {}),"
  else
    "    Button('Cancel', onPressed: () {}),",
  '  ],',
  '),',
  '// a container: a line of its own, then those of what is in it',
  'Semantics(',
  '  role: .dialog,',
  "  label: 'Popup',",
  '  child: Box(',
  '    style: theme.surface,',
  '    padding: const .x(1),',
  '    child: Column(',
  '      mainAxisSize: .min,',
  '      crossAxisAlignment: .start,',
  '      children: [',
  "        Text('$_covered', style: theme.muted),",
  if (o.flag('block')) ...[
    "        // leaves out what the dialog's node read before it, as a",
    '        // barrier does what it covers',
    "        const BlockSemantics(child: Text('$_over')),",
  ] else
    "        const Text('$_over'),",
  '      ],',
  '    ),',
  '  ),',
  '),',
].map((l) => l.isEmpty ? l : '$pad$l').toList();

String _code(Options o) {
  if (o.label('view') != 'beside the form') {
    return [
      "import 'package:twk/twk.dart';",
      '',
      '// the app read out as lines of text, the focused one reversed: no',
      '// boxes, borders or columns; TWK_SCREEN_READER=1 does it to any app',
      'void main() => runApp(const SignIn(), screenReader: true);',
      '',
      'final class SignIn extends StatefulWidget {',
      '  const SignIn({super.key});',
      '',
      '  @override',
      '  State<SignIn> createState() => _SignInState();',
      '}',
      '',
      'final class _SignInState extends State<SignIn> {',
      '  var _remember = false;',
      '  var _dark = true;',
      '  var _done = 4;',
      '',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    final theme = Theme.of(context);',
      '    return Column(',
      '      mainAxisSize: .min,',
      '      crossAxisAlignment: .start,',
      '      gap: 1,',
      '      children: [',
      ..._form(o, '        ', nodes: false),
      '      ],',
      '    );',
      '  }',
      '}',
    ].join('\n');
  }
  return [
    'final GlobalKey _form = GlobalKey();',
    '',
    '// of the controls, so that a move of the focus among them is read',
    _line([
      'final List<FocusNode> _nodes = ',
      '[for (var i = 0; i < 4; i++) FocusNode()];',
    ]),
    '',
    'var _remember = false;',
    'var _dark = true;',
    'var _done = 4;',
    '',
    '// the nodes of the form with a line, as a screen reader reads them',
    'var _read = const <SemanticsNode>[];',
    '',
    '@override',
    'void initState() {',
    '  super.initState();',
    '  for (final node in _nodes) {',
    '    node.addListener(_readNext);',
    '  }',
    '}',
    '',
    '@override',
    'void dispose() {',
    '  for (final node in _nodes) {',
    '    node.dispose();',
    '  }',
    '  super.dispose();',
    '}',
    '',
    _line([
      '/// Reads the form at the start of the next frame, ',
      'as this one built it.',
    ]),
    'void _readNext() =>',
    _line([
      '    AppBinding.maybeOf(context)?',
      '.scheduleFrameCallback((_) => _readForm());',
    ]),
    '',
    'void _readForm() {',
    '  final form = _form.currentContext;',
    '  if (!mounted || form == null) {',
    '    return;',
    '  }',
    '  Iterable<SemanticsNode> withLines(SemanticsNode node) sync* {',
    '    if (node.line.isNotEmpty) {',
    '      yield node;',
    '    }',
    '    for (final child in node.children) {',
    '      yield* withLines(child);',
    '    }',
    '  }',
    '',
    '  final read = [...withLines(SemanticsNode.of(form))];',
    '  String said(List<SemanticsNode> nodes) => [',
    r"    for (final n in nodes) '${n.focused} ${n.line}',",
    r"  ].join('\n');",
    '  if (said(read) != said(_read)) {',
    '    setState(() => _read = read);',
    '  }',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  _readNext();',
    '  final theme = Theme.of(context);',
    '  return SizedBox(',
    '    width: $_w,',
    '    child: Row(',
    '      crossAxisAlignment: .start,',
    '      gap: 2,',
    '      children: [',
    '        SizedBox(',
    '          width: $_fw,',
    '          child: Column(',
    '            key: _form,',
    '            mainAxisSize: .min,',
    '            crossAxisAlignment: .start,',
    '            gap: 1,',
    '            children: [',
    ..._form(o, '              ', nodes: true),
    '            ],',
    '          ),',
    '        ),',
    '        Expanded(',
    '          child: Column(',
    '            mainAxisSize: .min,',
    '            crossAxisAlignment: .stretch,',
    '            children: [',
    "              Text('A screen reader reads:', style: theme.muted),",
    '              for (final node in _read)',
    '                // the focused node on the selection, a bar before it',
    '                Box(',
    '                  style: node.focused ? theme.selection : null,',
    '                  child: Row(',
    '                    crossAxisAlignment: .start,',
    '                    gap: 1,',
    '                    children: [',
    '                      SizedBox(',
    '                        width: 1,',
    '                        child: node.focused',
    "                            ? Text('▎', style: theme.primary)",
    '                            : null,',
    '                      ),',
    '                      Expanded(',
    '                        child: Text.rich([',
    '                          if (node.role case final role?) ...[',
    '                            Span(role.word, theme.muted),',
    _line([
      '                            ',
      'Span(node.line.substring(role.word.length)),',
    ]),
    '                          ] else',
    '                            Span(node.line),',
    '                        ]),',
    '                      ),',
    '                    ],',
    '                  ),',
    '                ),',
    '            ],',
    '          ),',
    '        ),',
    '      ],',
    '    ),',
    '  );',
    '}',
  ].join('\n');
}

/// The Code's form, and what a screen reader reads of it: beside it, or
/// in its place as the screen-reader mode shows an app ([reader]): the
/// lines alone, the focused one reversed. The form's state is the page's.
final class _SignIn extends StatefulWidget {
  const _SignIn({
    required this.reader,
    required this.block,
    required this.label,
    required this.exclude,
  });

  final bool reader;
  final bool block;
  final bool label;

  /// Whether the heading is in an [ExcludeSemantics].
  final bool exclude;

  @override
  State<_SignIn> createState() => _SignInState();
}

final class _SignInState extends State<_SignIn> {
  late final Map<String, Object?> _kept = PageControl.of(context).state;
  final GlobalKey _form = GlobalKey();

  // of the controls, so that a move of the focus among them is read
  final List<FocusNode> _nodes = [for (var i = 0; i < 4; i++) FocusNode()];

  bool get _remember => (_kept['remember'] ?? false) as bool;
  bool get _dark => (_kept['dark'] ?? true) as bool;
  int get _done => (_kept['done'] ?? 4) as int;

  // the nodes of the form with a line, as a screen reader reads them
  var _read = const <SemanticsNode>[];
  int? _pending;

  @override
  void initState() {
    super.initState();
    for (final node in _nodes) {
      node.addListener(_readNext);
    }
  }

  @override
  void dispose() {
    if (_pending case final id?) {
      AppBinding.maybeOf(context)?.cancelFrameCallback(id);
    }
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Reads the form at the start of the next frame, as this one built it.
  void _readNext() {
    if (_pending != null || !mounted) {
      return;
    }
    _pending = AppBinding.maybeOf(context)?.scheduleFrameCallback((_) {
      _pending = null;
      _readForm();
    });
  }

  void _readForm() {
    final form = _form.currentContext;
    if (!mounted || form == null) {
      return;
    }
    Iterable<SemanticsNode> withLines(SemanticsNode node) sync* {
      if (node.line.isNotEmpty) {
        yield node;
      }
      for (final child in node.children) {
        yield* withLines(child);
      }
    }

    final read = [...withLines(SemanticsNode.of(form))];
    String said(List<SemanticsNode> nodes) => [
      for (final n in nodes) '${n.focused} ${n.line}',
    ].join('\n');
    if (said(read) != said(_read)) {
      setState(() => _read = read);
    }
  }

  void _set(String key, Object value) => setState(() => _kept[key] = value);

  /// The form's widgets, its column's children.
  List<Widget> _formChildren(ThemeData theme) => [
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          excluding: widget.exclude,
          child: Semantics(
            role: SemanticsRole.heading,
            child: Text(
              'Sign in',
              style: theme.primary.merge(const Style(attrs: Attr.bold)),
            ),
          ),
        ),
        Checkbox(
          value: _remember,
          focusNode: _nodes[0],
          onChanged: (v) => _set('remember', v),
          label: 'Remember me',
        ),
        Switch(
          value: _dark,
          focusNode: _nodes[1],
          onChanged: (v) => _set('dark', v),
          label: 'Dark mode',
        ),
      ],
    ),
    Row(
      gap: 1,
      children: [
        // on the screen, not read: nodes: [] reads nothing of it
        Semantics(
          nodes: const [],
          child: Text('Upload', style: theme.muted),
        ),
        Expanded(
          child: ProgressBar(
            value: _done / 10,
            style: theme.primary.merge(Style(bg: theme.surface.bg)),
            semanticsLabel: widget.label ? 'Upload' : null,
          ),
        ),
      ],
    ),
    Row(
      gap: 1,
      children: [
        Button(
          'More',
          focusNode: _nodes[2],
          onPressed: () => _set('done', (_done + 1) % 11),
        ),
        Button('Cancel', focusNode: _nodes[3], onPressed: () {}),
      ],
    ),
    // a container: a line of its own, then those of what is in it
    Semantics(
      role: SemanticsRole.dialog,
      label: 'Popup',
      child: Box(
        style: theme.surface,
        padding: const EdgeInsets.x(1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_covered, style: theme.muted),
            if (widget.block)
              // leaves out what the dialog's node read before it, as a
              // barrier does what it covers
              const BlockSemantics(child: Text(_over))
            else
              const Text(_over),
          ],
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    _readNext();
    final theme = Theme.of(context);
    final form = SizedBox(
      width: _fw,
      child: Column(
        key: _form,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: _formChildren(theme),
      ),
    );
    if (widget.reader) {
      // the lines alone, the focused one reversed; the form laid out under
      // them and not painted, so that it has the focus and is read
      return SizedBox(
        width: 36,
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final node in _read)
                  Text(
                    node.line,
                    style: node.focused
                        ? const Style(attrs: Attr.reverse)
                        : const Style(),
                  ),
              ],
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Opacity(opacity: 0, child: form),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: _w,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 2,
        children: [
          form,
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('A screen reader reads:', style: theme.muted),
                for (final node in _read)
                  // the focused node on the selection, a bar before it
                  Box(
                    style: node.focused ? theme.selection : null,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      gap: 1,
                      children: [
                        SizedBox(
                          width: 1,
                          child: node.focused
                              ? Text('▎', style: theme.primary)
                              : null,
                        ),
                        Expanded(
                          child: Text.rich([
                            if (node.role case final role?) ...[
                              Span(role.word, theme.muted),
                              Span(node.line.substring(role.word.length)),
                            ] else
                              Span(node.line),
                          ]),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
