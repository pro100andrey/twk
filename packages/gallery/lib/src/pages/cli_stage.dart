// The stage of App › Cli: a twk_cli program run on twk_cli's fake terminal
// (../../cli/run.dart), in a terminal's frame. It reads the process's
// stdio through dart:io, which a browser has not: cli_stage_web.dart is
// the stage there.
import 'package:twk/twk.dart';

import '../../cli/check.dart' as check;
import '../../cli/create.dart' as create;
import '../../cli/install.dart' as install;
import '../../cli/run.dart';
import '../motion.dart';
import '../page.dart';

/// The programs, by name.
const _programs = <String, CliProgram>{
  'create': create.create,
  'install': install.install,
  'check': check.check,
};

/// [program] run in a terminal [width] × [height] with its frame, on the
/// gallery's clock.
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
      child: CodeApp(
        child: CliRun(
          key: ValueKey(program),
          script: cliScripts[program]!,
          program: _programs[program]!,
          at: Clock.of(context).frozenAt,
        ),
      ),
    ),
  );
}
