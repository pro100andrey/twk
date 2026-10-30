// The stage of App › Cli in a browser: twk's console talks to the process's
// stdio through dart:io, which a page in a browser has not, so the run
// that cli_stage.dart shows on the VM is not there; this says so in its
// place.
import 'package:twk/twk.dart';

/// What stands for [program]'s run in a terminal [width] × [height].
Widget cliStage(
  BuildContext context,
  String program, {
  required int width,
  required int height,
}) {
  final theme = Theme.of(context);
  return SizedBox(
    width: width,
    height: height,
    child: Box(
      border: Border.all(type: BorderType.rounded, style: theme.border),
      titles: [BorderTitle(' terminal ', style: theme.muted)],
      padding: const EdgeInsets.only(left: 1, right: 1),
      child: Center(
        child: Text(
          "twk's console runs where a program has a terminal: it reads and "
          'writes the stdio of the process (dart:io), which a page in a '
          'browser has not. The run of $program.dart shows in the gallery '
          'at a terminal: dart run packages/gallery/bin/gallery.dart',
          style: theme.muted,
          align: TextAlign.center,
        ),
      ),
    ),
  );
}
