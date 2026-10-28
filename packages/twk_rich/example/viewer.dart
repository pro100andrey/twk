// A viewer of Markdown files and diffs. A file that holds a diff, as
// `git diff` writes it, colors and all, or `diff -u`, shows as a diff,
// with Tab switching it between unified and side by side; any other file,
// and one whose name ends in .md, as Markdown, whose text the mouse
// selects and copies. The arrows, PgUp, PgDn, Home, End and the wheel
// scroll; q quits.
//
//   dart run example/viewer.dart README.md
//   git diff --color > /tmp/changes.diff
//   dart run example/viewer.dart /tmp/changes.diff
import 'dart:io';

import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run example/viewer.dart FILE');
    exitCode = 64;
    return;
  }
  final String text;
  try {
    text = File(args.single).readAsStringSync();
  } on FileSystemException catch (e) {
    stderr.writeln('${args.single}: ${e.osError?.message ?? e.message}');
    exitCode = 66;
    return;
  }
  await runApp(Viewer(args.single, text));
}

/// The file [name] holding [text], as a diff or as Markdown.
final class Viewer extends StatefulWidget {
  const Viewer(this.name, this.text, {super.key});

  /// The file's name, in the title.
  final String name;

  final String text;

  @override
  State<Viewer> createState() => _ViewerState();
}

final class _ViewerState extends State<Viewer> {
  /// The diff the file holds; null for Markdown.
  late Diff? _diff = _diffIn(widget.name, widget.text);

  DiffLayout _layout = .unified;

  @override
  void didUpdateWidget(Viewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.name != oldWidget.name || widget.text != oldWidget.text) {
      _diff = _diffIn(widget.name, widget.text);
    }
  }

  void _switchLayout() => setState(
    () => _layout = _layout == DiffLayout.unified
        ? DiffLayout.sideBySide
        : DiffLayout.unified,
  );

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'q': () => AppBinding.of(context).quit(),
      'tab': _diff == null ? null : _switchLayout,
    },
    hints: {
      'q': 'quit',
      'tab': _layout == DiffLayout.unified ? 'side by side' : 'unified',
    },
    child: Theme.adaptive(
      child: _Page(widget.name, widget.text, _diff, _layout),
    ),
  );
}

/// The file below its name and what it holds, the keys below it.
final class _Page extends StatelessWidget {
  const _Page(this.name, this.text, this.diff, this.layout);

  final String name;
  final String text;
  final Diff? diff;
  final DiffLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diff = this.diff;
    return Box(
      style: theme.background.merge(theme.text),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Text.rich([
            Span(' $name  ', theme.primary).bold,
            Span(diff == null ? 'Markdown' : _summary(diff), theme.muted),
          ], wrap: .none),
          Expanded(
            child: diff == null
                ? SelectionArea(
                    child: SingleChildScrollView(
                      autofocus: true,
                      child: Padding(
                        padding: const .x(1),
                        child: MarkdownView(text),
                      ),
                    ),
                  )
                : DiffView(diff, layout: layout, autofocus: true),
          ),
          const KeyHintsBar(),
        ],
      ),
    );
  }
}

/// The diff in [text], its colors left out; null when it has none or
/// [name] is that of a Markdown file.
Diff? _diffIn(String name, String text) {
  if (name.endsWith('.md') || name.endsWith('.markdown')) {
    return null;
  }
  final diff = Diff.parse(stripAnsi(text));
  return diff.files.isEmpty ? null : diff;
}

/// How many files [diff] changes and how many lines it adds and removes:
/// `2 files  +10 -4`.
String _summary(Diff diff) {
  var added = 0;
  var removed = 0;
  for (final file in diff.files) {
    for (final hunk in file.hunks) {
      for (final line in hunk.lines) {
        switch (line.kind) {
          case DiffLineKind.added:
            added++;
          case DiffLineKind.removed:
            removed++;
          case DiffLineKind.context:
        }
      }
    }
  }
  final count = diff.files.length;
  return '${count == 1 ? '1 file' : '$count files'}  +$added -$removed';
}
