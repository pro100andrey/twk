// The app inspect_test.dart inspects: a text at column 2 of row 1 on a
// terminal in memory, whose input is stdin; it says on stdout when it has
// drawn its first frame, at the start of the second, which a frame
// callback the first one calls asks for. The test runs it compiled, and
// `twk run` runs it from source as the `bin/main.dart` of a package of its
// own.
//
// The libraries of twk it runs on, not all of twk: it compiles in half the
// time, which `twk run` takes from a test's.
import 'dart:async';
import 'dart:io';

import 'package:twk/src/binding/binding.dart' show AppBinding;
import 'package:twk/src/layout/basic.dart' show Padding;
import 'package:twk/src/text/widgets.dart' show Text;
import 'package:twk_core/twk_core.dart' show EdgeInsets, HeadlessTerminal;

Future<void> main() async {
  final term = HeadlessTerminal(width: 30, height: 4);
  final input = stdin.listen(term.input);
  final binding = AppBinding(term);
  binding.scheduleFrameCallback(
    (_) => binding.scheduleFrameCallback((_) => stdout.writeln('running')),
  );
  await binding.run(
    const Padding(
      padding: EdgeInsets.only(left: 2, top: 1),
      child: Text('inspected'),
    ),
  );
  await input.cancel();
}
