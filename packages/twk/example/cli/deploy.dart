// A deploy report through twk's console: messages on each channel, and twk
// widgets printed in the output, as the terminal, a pipe or CI takes them.
//
//   dart run example/cli/deploy.dart              # at a terminal
//   dart run example/cli/deploy.dart -v           # with the details
//   dart run example/cli/deploy.dart --no-color   # plain lines
//   dart run example/cli/deploy.dart | cat        # a pipe
import 'package:twk/cli.dart';
import 'package:twk/twk.dart';

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
        const Box(
          border: Border.all(type: BorderType.rounded),
          titles: [BorderTitle(' deploy.yaml ')],
          padding: EdgeInsets.only(left: 1, right: 1),
          child: Text(_config),
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
