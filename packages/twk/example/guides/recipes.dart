// Recipes: the Recipes guide.
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
        semanticsLabel: 'message',
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
