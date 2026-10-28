// A deploy report through twk_cli: messages on each channel, and twk
// widgets printed in the output, as the terminal, a pipe or CI takes them.
//
//   dart run example/twk_cli_example.dart              # at a terminal
//   dart run example/twk_cli_example.dart -v           # with the details
//   dart run example/twk_cli_example.dart --no-color   # plain lines
//   dart run example/twk_cli_example.dart | cat        # a pipe
import 'package:twk/twk.dart';
import 'package:twk_cli/twk_cli.dart';
import 'package:twk_rich/twk_rich.dart';

const _config = '''
services:
  api: { replicas: 3 }
  web: { replicas: 2 }''';

Future<void> main(List<String> args) =>
    Cli.runWithArgs(args, (cli, rest) async {
      cli
        ..detail('mode: ${cli.mode.name}, level: ${cli.level.name}')
        ..info(['Deploying ', 'staging'.bold, ' from ', 'main'.italic]);

      await cli.show(
        Box(
          border: const Border.all(type: BorderType.rounded),
          titles: const [BorderTitle(' deploy.yaml ')],
          padding: const EdgeInsets.only(left: 1, right: 1),
          child: CodeView(_config, language: languageNamed('yaml')),
        ),
      );

      for (final (service, replicas) in [('api', 3), ('web', 2)]) {
        cli.detail('rolling out $service');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        cli.success(['✔ ', service.bold, ' $replicas of $replicas ready']);
      }
      cli
        ..delayed('Logs: ${cli.link(Uri.parse('https://example.com/logs'))}')
        ..warn('web: the image is 3 days old')
        ..success('Deployed in 0.3 s')
        ..flush();
    });
