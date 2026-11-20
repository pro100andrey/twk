// Run by env_test.dart with NO_COLOR and FORCE_COLOR in its own environment:
// starts `sh` in a pseudo-terminal, as the driver does for an app, and
// prints the two variables as the program saw them.
import 'package:twk_driver/twk_driver.dart';

Future<void> main(List<String> args) async {
  final session = await Session.compose(
    ProcessSpec(
      'sh',
      arguments: ['-c', r'echo "colors:[$NO_COLOR][$FORCE_COLOR][$KEPT]"'],
      environment: {if (args.contains('given')) 'NO_COLOR': 'given'},
    ),
    process: const PtyCommandPort(),
    screen: EmulatorScreen(),
    timeout: const Duration(seconds: 30),
  );
  final step = await session.waitFor(
    (screen) => screen.contains('colors:'),
    what: 'the variables',
  );
  print(step.screen.split('\n').firstWhere((l) => l.startsWith('colors:')));
  await session.close();
}
