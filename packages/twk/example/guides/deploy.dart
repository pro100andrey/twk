// A command-line tool on twk's console: the Recipes guide.
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
