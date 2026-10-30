part of '../sample_app.dart';

extension on _SampleAppState {
  /// A command's output with its escapes, read into spans whole and as it
  /// comes, and without them.
  List<Widget> _ansi() {
    const output = '\x1b[32mok\x1b[0m done\n';
    final stream = AnsiStream()..add(output);
    return [
      SizedBox(
        height: 1,
        child: Row(
          gap: 1,
          children: [
            Text.rich(parseAnsi(output).first),
            Text.rich(stream.lines.first),
            Text(stripAnsi(output).trim()),
          ],
        ),
      ),
    ];
  }
}
