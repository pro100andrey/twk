---
title: "Recipes"
about: "A dialog, a table, a log, an inline prompt, a future, a timer, and a command-line tool on twk's console."
order: 12
---
# Recipes

Each stands on its own, and is tested in `packages/twk/test/example/`
(`recipes_test.dart`, `deploy_test.dart`).

## Dialogs, tables, logs, futures and timers

<!-- file: packages/twk/example/guides/recipes.dart -->
```dart
import 'dart:async';

import 'package:twk/hooks.dart';
import 'package:twk/log.dart';
import 'package:twk/twk.dart';

/// The root of an app with dialogs: `App` puts the Overlay under the
/// theme, so what it shows is in the theme, and above the screens, so
/// their contexts find it.
/// `runApp(app)` runs it.
const app = App(theme: ThemeData.nord, child: Home());

final class Home extends StatelessWidget {
  const Home({super.key});

  Future<void> _delete(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        title: 'Delete the file?',
        child: Row(
          mainAxisSize: .min,
          spacing: 2,
          children: [
            Button('Delete', onPressed: () => closeDialog(context, true)),
            Button(
              'Cancel',
              autofocus: true,
              onPressed: () => closeDialog(context, false),
            ),
          ],
        ),
      ),
    );
    if ((sure ?? false) && context.mounted) {
      showToast(context: context, message: 'Deleted.');
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Button(
      'Delete…',
      autofocus: true,
      onPressed: () => unawaited(_delete(context)),
    ),
  );
}

final class Entry {
  const Entry(this.name, this.size);

  final String name;
  final int size;
}

/// [entries] in columns: a click on a title or `s` sorts, Up and Down
/// select a row, Enter logs it. The type argument is needed: the columns'
/// closures get no type from `rows`.
Widget entryTable(List<Entry> entries) => Table<Entry>(
  rows: entries,
  columns: [
    TableColumn(
      title: 'name',
      cell: (e) => TableCell(e.name),
      compare: (a, b) => a.name.compareTo(b.name),
    ),
    TableColumn(
      title: 'size',
      width: const .fixed(8),
      align: .right,
      cell: (e) => TableCell('${e.size}'),
      compare: (a, b) => a.size.compareTo(b.size),
    ),
  ],
  onActivated: (e) => log('open ${e.name}'),
  autofocus: true,
);

/// A log that follows its newest line while it shows the end; only the
/// lines in view are built.
Widget logView(List<String> lines) => Scrollbar(
  child: ListView.builder(
    itemCount: lines.length,
    itemBuilder: (context, i) => Text(lines[i]),
    stickToBottom: true,
  ),
);

/// Inline (`runApp(const Prompt(), mode: .inline)`): each line sent goes
/// to the terminal's scrollback, the field alone stays in the app's rows.
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
      Static(items: _sent, builder: (context, line) => Text('> $line')),
      TextField(
        controller: _text,
        autofocus: true,
        onSubmitted: (line) {
          setState(() => _sent.add(line));
          _text.clear();
        },
      ),
    ],
  );
}

/// A spinner until [answer] completes, then its text or its error. Make
/// the future once (in `initState`, or in the caller), not in a build.
Widget answerView(Future<String> answer) => FutureBuilder<String>(
  future: answer,
  builder: (context, snapshot) => switch (snapshot) {
    AsyncSnapshot(hasError: true) => Text('failed: ${snapshot.error}'),
    AsyncSnapshot(hasData: true) => Text(snapshot.requireData),
    _ => const Spinner(),
  },
);

/// The seconds since it was shown, counted by `useInterval` on the app's
/// clock: it stops with the widget and sleeps where a `TickerMode` is off.
final class Uptime extends HookWidget {
  const Uptime({super.key});

  @override
  Widget build(BuildContext context) {
    final seconds = useState(0);
    useInterval(const Duration(seconds: 1), () => seconds.value++);
    return Text('up ${seconds.value}s');
  }
}
```

## A command-line tool: twk's console, not `runApp`

`runApp` is for a program whose screen is its interface: an editor, a
dashboard, a monitor, a list moved through. A command run from a shell
or a script (an installer, an `init`-style setup, a deploy, a tool with
flags) prints lines, asks a question or two and shows progress, and has
to work as well in a pipe, in a CI log and with nobody at the keyboard:
for that, import twk's console, `package:twk/cli.dart`
([the reference](../../packages/twk/doc/reference/cli.md)), and call no `runApp`. A program
does one or the other: where somebody answers at a terminal, the console
runs an inline twk app of its own.

- `Cli.runWithArgs(args, (cli, rest) async { … })` runs the body with a
  console, takes `-v`, `-q`, `--no-color` and `--no-input` out of the
  arguments, and ends what the body throws with a traceback on stderr
  and exit code 1.
- `cli.info`, `cli.success`, `cli.detail` (shown with `-v`), `cli.warn`
  and `cli.err` (both to stderr) write lines; `await cli.show(widget)`
  prints any twk widget once, at the terminal's width (a `Table`, a
  `Box`, a `DescriptionList`, a `Callout`).
- `await cli.prompt(question)`, `cli.confirm`, `cli.chooseOne(question,
  choices:)` and `cli.chooseAny`: at a terminal, a widget that collapses
  into one committed line once answered (`✔ Target environment? prod`);
  on a terminal without escapes, a line read, choices by number; where
  nobody can answer (stdin no terminal, `CI`, `--no-input`), the
  default, or a `PromptAnswerRequiredException` without one. `confirm`
  without a default never says yes for anybody: a question that changes
  something wants a `--yes` flag.
- `cli.progress(message).run(work, done: …)` is a spinner, then the line
  `done` gives with the time it took; `cli.tasks((tracker) => …)` runs
  many tasks at once, each `tracker.run(label, (task) => …, total:)`
  with its bar, rate and time left (twk's `ProgressList`). Where the
  terminal does not redraw, both write lines.
- Its tests give the console a `FakeCliTerminal`
  (`package:twk_test/cli.dart`): `.plain(lines: […])` answers the
  prompts a line each, `.interactive(input: […])` types keys into the
  widgets, and `FakeCliTerminal()` is nobody at the keyboard.

<!-- file: packages/twk/example/guides/deploy.dart -->
```dart
import 'package:twk/cli.dart';
import 'package:twk/twk.dart';

/// Asks where to deploy, and again before production unless `--yes`
/// says so, deploys with a spinner and shows what it deployed.
Future<void> deploy(Cli cli, List<String> args) async {
  final target = await cli.chooseOne(
    'Target environment?',
    choices: ['dev', 'stage', 'prod'],
    // what CI gets: where nobody can answer, a prompt without a default
    // throws
    defaultValue: 'dev',
  );
  // no default: nobody's yes is assumed
  if (target == 'prod' &&
      !args.contains('--yes') &&
      !await cli.confirm('Deploy to prod?')) {
    cli.info('Nothing deployed.');
    return;
  }
  await cli
      .progress('Deploying to $target')
      .run(() => upload(target), done: (_) => 'Deployed to $target');
  await cli.show(
    DescriptionList(
      items: [
        DescriptionItem.text('Target', target),
        DescriptionItem.text('Version', '1.4.2'),
      ],
    ),
  );
}

/// Where a real tool would upload.
Future<void> upload(String target) =>
    Future<void>.delayed(const Duration(milliseconds: 100));
```

The program's `main` is `Cli.runWithArgs(args, deploy)`; its tests give the
console a `FakeCliTerminal`, as above, and are `deploy_test.dart`.
