// What a terminal app learns about the terminal's color scheme, written to
// stderr, for color_scheme_test.dart: the brightness the probe found and
// whether the terminal reports changes, then each color scheme report and
// default color that arrives. It quits after the background that follows a
// color scheme report, with status 1 if none came within 10 seconds.
import 'dart:async';
import 'dart:io';

import 'package:twk_core/terminal.dart';

Future<void> main() async {
  final term = await Terminal.open();
  final info = term.info;
  stderr.writeln(
    'brightness ${info.brightness?.name} '
    'reports ${info.colorSchemeReports}',
  );
  final background = Completer<int>();
  var reported = false;
  final sub = term.events.listen((e) {
    switch (e) {
      case ColorSchemeReport(:final brightness):
        reported = true;
        stderr.writeln('scheme ${brightness.name}');
      case ColorReport(:final which, :final rgb):
        stderr.writeln('color $which ${rgb.toRadixString(16).padLeft(6, '0')}');
        if (reported && which == 11 && !background.isCompleted) {
          background.complete(0);
        }
      default:
    }
  });
  final status = await background.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () => 1,
  );
  await sub.cancel();
  await term.close();
  exit(status);
}
