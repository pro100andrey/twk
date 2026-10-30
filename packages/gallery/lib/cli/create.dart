// Asks what a new app is to be: its name, a template, its features and a
// last yes or no. At a terminal each question is a widget until it is
// answered, then a line: `✔ Template? server`.
import 'package:twk/cli.dart';
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => Cli.runWithArgs(args, create);

Future<void> create(Cli cli, List<String> rest) async {
  final name = await cli.prompt(
    'Project name?',
    defaultValue: 'my_app',
    validate: (name) => RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)
        ? null
        : 'lowercase letters, digits and _',
  );
  final template = await cli.chooseOne(
    'Template?',
    choices: ['console', 'package', 'server', 'web'],
  );
  final features = await cli.chooseAny(
    'Features?',
    choices: ['Linter', 'Docker', 'Tests', 'CI'],
    defaultValues: ['Linter'],
  );
  if (!await cli.confirm('Create $name?')) {
    cli.info('Nothing created.');
    return;
  }
  cli.success([
    'Created '.bold,
    name,
    ' from ',
    template.italic,
    ' with ${features.join(', ')}',
  ]);
}
