// A create-an-app flow through the console's prompts: a name, a
// template, the features, a token and a last yes or no, asked as the
// terminal allows.
//
//   dart run example/cli/create.dart              # at a terminal: widgets
//   dart run example/cli/create.dart --no-color   # plain: lines, numbers
//   dart run example/cli/create.dart --no-input   # nobody to ask: defaults
//   dart run example/cli/create.dart --no-input --yes
//
// Ctrl+C in a prompt cancels it: the flow says so and ends with 130.
import 'dart:io';

import 'package:twk/cli.dart';
import 'package:twk/twk.dart';

const _templates = ['console', 'package', 'server', 'web', 'flutter'];
const _features = ['Linter', 'Docker', 'Tests', 'CI', 'Docs'];
const _licenses = [
  'MIT',
  'Apache-2.0',
  'BSD-3-Clause',
  'GPL-3.0',
  'LGPL-3.0',
  'MPL-2.0',
  'ISC',
  'Unlicense',
  'none',
];

Future<void> main(List<String> args) => Cli.runWithArgs(args, (
  cli,
  rest,
) async {
  final yes = rest.contains('--yes');
  try {
    final name = await cli.prompt(
      'Project name?',
      defaultValue: 'my_app',
      validate: (name) => RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)
          ? null
          : 'lowercase letters, digits and _, a letter first',
    );
    final template = await cli.chooseOne(
      'Template?',
      choices: _templates,
      defaultValue: 'console',
    );
    final features = await cli.chooseAny(
      'Features?',
      choices: _features,
      defaultValues: ['Linter', 'Tests'],
      max: 4,
    );
    final license = await cli.chooseOne(
      'License?',
      choices: _licenses,
      defaultValue: 'MIT',
    );
    final org = await cli.prompt(
      'Organization?',
      defaultValue: 'com.example',
      suggest: (typed) => [
        for (final org in ['com.example', 'dev.twk', 'io.github'])
          if (org.startsWith(typed)) org,
      ],
    );
    final token = await cli.prompt(
      'Registry token?',
      hidden: true,
      defaultValue: '',
      placeholder: 'empty to skip',
    );
    // no default: nobody's yes is assumed, --yes says it
    final go = yes || await cli.confirm('Create $name ($template)?');
    if (!go) {
      cli.info('Nothing created.');
      return;
    }
    cli
      ..success(['✔ ', 'Created '.bold, name, ' from ', template.italic])
      ..detail('features: ${features.join(', ')}; license: $license')
      ..detail('organization: $org; token: ${token.isEmpty ? 'none' : 'set'}');
  } on PromptCancelledException {
    cli.warn('Cancelled.');
    exitCode = 130;
  } on PromptAnswerRequiredException catch (e) {
    cli.err(
      '"${e.question}" has no default: pass --yes, or run it at a terminal',
    );
    exitCode = 2;
  }
});
