/// `twk create`: [CreateCommand], and what it does as functions:
/// [createApp] (writing), [askCreate] (asking what the flags left),
/// [canAsk], [createPlan], [packageNameOf], [packageNameError],
/// [isCheckout] and [checkoutOfCommand].
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show max;

import 'package:args/command_runner.dart';
import 'package:mold/mold.dart';
import 'package:path/path.dart' as p;
import 'package:twk/cli.dart';

import 'agents.dart';
import 'templates/templates.dart';

/// `twk create`: unpacks a template ([templates]), a package packed with
/// mold, into a directory under a new package's name: a package that
/// runs, analyzes and passes its tests as it is.
final class CreateCommand extends Command<int> {
  /// Sets up `twk create`'s options: `--template`, `--agents`, `--name`,
  /// `--path-to-twk`, `--force`, `--dry-run` and `--list`.
  ///
  /// `terminal` gives the terminal to ask on where the flags left a
  /// question, null where nobody can be asked: [askTerminal], the
  /// process's own where stdin and stdout are a terminal, unless a test
  /// gives another.
  CreateCommand({this._terminal = askTerminal}) {
    argParser
      ..addOption(
        'template',
        abbr: 't',
        valueHelp: 'name',
        allowed: [for (final t in templates) t.name],
        allowedHelp: {for (final t in templates) t.name: t.description},
        help:
            'The kind of app (default: asked in a terminal, else '
            '${templates.first.name}).',
      )
      ..addMultiOption(
        'agents',
        valueHelp: 'files',
        allowed: [for (final a in CreateAgents.values) a.flag, 'none'],
        allowedHelp: {
          for (final a in CreateAgents.values) a.flag: a.description,
          'none': 'write none of them, and ask nothing',
        },
        help:
            'The files for coding agents to write, as `twk agents` does '
            '(default: asked in a terminal, else none).',
      )
      ..addOption(
        'name',
        valueHelp: 'package',
        help:
            "The package's name (default: the directory's, in lower case, "
            'other characters than letters, digits and _ as _).',
      )
      ..addOption(
        'path-to-twk',
        valueHelp: 'dir',
        help:
            'The checkout of the twk repository to take twk, twk_test, '
            'twk_dev and twk_lints from by path (default: the one this '
            'command runs from, else pub).',
      )
      ..addFlag(
        'force',
        negatable: false,
        help:
            'Write into a directory that is not empty, over the files of '
            'the same paths.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Name the files it would write, and which of them over a file '
            'there, writing none.',
      )
      ..addFlag('list', negatable: false, help: 'List the templates.');
  }

  final CliTerminal? Function() _terminal;

  @override
  String get name => 'create';

  @override
  String get invocation =>
      'twk create <dir> [--template=<name>] [--agents=<files>] '
      '[--name=<package>] [--path-to-twk=<dir>] [--force] [--dry-run]';

  @override
  String get description =>
      'Start a new app from a template.\n\n'
      'Unpacks the template, a package packed with mold, into <dir>, made '
      'with its parents if it is not there, under the package name: a '
      'pubspec that takes twk, twk_test, twk_dev and twk_lints by path '
      'from a checkout of the twk repository, or from pub, '
      "analysis_options.yaml (with twk_lints' recommended rules), "
      'bin/main.dart, the app in lib/, a testTwk test of it in test/, a '
      'README and a .gitignore. In a terminal it asks for the template and '
      'the files for coding agents (the twk skill, AGENTS.md) that '
      '--template and --agents did not say; without one it asks nothing, '
      'and takes the app template and no files for agents. A directory '
      'that is not empty is refused unless --force, which writes over the '
      'files of the same paths and leaves the others. --dry-run names the '
      'files it would write, and which over a file there; --list names the '
      'templates.';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.flag('list')) {
      final width = templates.map((t) => t.name.length).reduce(max);
      for (final t in templates) {
        stdout.writeln('${t.name.padRight(width)}  ${t.description}');
      }
      return 0;
    }
    final rest = args.rest;
    if (rest.isEmpty) {
      usageException('No directory to create the app in.');
    }
    if (rest.length > 1) {
      usageException('One directory at most.');
    }
    final dir = p.normalize(p.absolute(rest.single));
    final name = args.option('name') ?? packageNameOf(p.basename(dir));
    if (packageNameError(name) case final error?) {
      usageException(
        args.option('name') == null
            ? '$error; --name=<package> gives the package another'
            : error,
      );
    }
    final String? checkout;
    if (args.option('path-to-twk') case final given?) {
      checkout = p.normalize(p.absolute(given));
      if (!isCheckout(checkout)) {
        stderr.writeln(
          'twk create: no checkout of twk at $checkout: it has no '
          'packages/twk, packages/twk_test, packages/twk_dev and '
          'packages/twk_lints',
        );
        return 1;
      }
    } else {
      checkout = await checkoutOfCommand();
    }
    final dryRun = args.flag('dry-run');
    final given = args.option('template') == null
        ? null
        : templates.firstWhere((t) => t.name == args.option('template'));
    final agentsGiven = args.wasParsed('agents')
        ? _agentsOf(args.multiOption('agents'))
        : null;
    // a refusal of the directory comes before any question: planning
    // writes nothing, and what the template changes is not a refusal
    try {
      createPlan(
        given ?? templates.first,
        name,
        dir: dir,
        checkout: checkout,
        overwrite: args.flag('force'),
        // createApp plans again, with the template chosen by then, and warns
        warn: false,
      );
    } on ValidationException catch (e) {
      for (final error in e.errors) {
        stderr.writeln('twk create: ${_hinted(error)}');
      }
      return 1;
    }
    final CreateAnswers answers;
    // a coding agent runs this with no terminal: nothing asked it, so the
    // next steps say how it gets the skill
    var skillUnoffered = false;
    if (given != null && agentsGiven != null) {
      answers = (template: given, agents: agentsGiven);
    } else {
      final terminal = _terminal();
      if (terminal == null) {
        skillUnoffered = agentsGiven == null;
        answers = (
          template: given ?? templates.first,
          agents: agentsGiven ?? const {},
        );
      } else {
        final asked = await Cli.run<CreateAnswers?>(
          (cli) {
            // a terminal nobody can answer at (CI is set) asks nothing too
            skillUnoffered =
                agentsGiven == null && cli.mode == CliMode.nonInteractive;
            return askCreate(cli, template: given, agents: agentsGiven);
          },
          open: ({ansi, interactive}) => terminal,
        );
        if (asked == null) {
          // cancelled: Cli.run said so and set the code (130 for Ctrl+C)
          return max(terminal.exitCode, 1);
        }
        answers = asked;
      }
    }
    final template = answers.template;
    final CreatedApp created;
    try {
      created = await createApp(
        template,
        name,
        dir: dir,
        checkout: checkout,
        overwrite: args.flag('force'),
        dryRun: dryRun,
        agents: answers.agents,
      );
    } on ValidationException catch (e) {
      for (final error in e.errors) {
        stderr.writeln('twk create: ${_hinted(error)}');
      }
      return 1;
    } on AgentsException catch (e) {
      stderr.writeln('twk create: $e');
      return 1;
    } on IOException catch (e) {
      stderr.writeln('twk create: $e');
      return 1;
    }
    final plan = created.plan;
    final files = plan.templateFiles.toList()
      ..sort((a, b) => a.to.compareTo(b.to));
    stdout
      ..writeln(
        '${dryRun ? 'twk create --dry-run: would write' : 'twk create:'} '
        '$name, of the template ${template.name}, in $dir:',
      )
      ..writeln(
        [
          for (final file in files)
            '  ${file.to}${switch (file) {
              PlannedFile(identicalToExisting: true) => ' (the same there)',
              PlannedFile(overwrites: true) => ' (over the one there)',
              _ => '',
            }}',
        ].join('\n'),
      )
      ..writeln(
        checkout == null
            ? 'twk, twk_test, twk_dev and twk_lints from pub, at '
                  '^$twkVersion.'
            : 'twk, twk_test, twk_dev and twk_lints by path, from '
                  '$checkout.',
      );
    if (created.agents case final agents?) {
      stdout.write(describeAgents(agents, dryRun: dryRun));
    }
    if (!dryRun) {
      stdout
        ..writeln()
        ..writeln('  cd ${_quoted(rest.single)}')
        ..writeln('  dart pub get')
        ..writeln('  dart run bin/main.dart')
        ..writeln('  dart run twk_dev:twk run bin/main.dart  # hot reloaded')
        ..writeln('  dart test');
      if (skillUnoffered) {
        stdout.writeln(
          '  dart run twk_dev:twk agents  # the twk skill, for coding agents',
        );
      }
    }
    return 0;
  }

  /// The files of `--agents` as [AgentsFile]s: `none` alone says no file,
  /// and a refusal with the other values.
  Set<AgentsFile> _agentsOf(List<String> values) {
    if (values.contains('none')) {
      if (values.length > 1) {
        usageException('--agents=none says no file: it takes no other value.');
      }
      return const {};
    }
    return {
      for (final a in CreateAgents.values)
        if (values.contains(a.flag)) ...a.files,
    };
  }
}

/// The files for coding agents `twk create` can write, the values of
/// `--agents`, and what each is among [AgentsFile]s.
enum CreateAgents {
  /// The block of `AGENTS.md`.
  agentsMd('agents-md', 'a block of AGENTS.md that points at the skill', {
    AgentsFile.agentsMd,
  }),

  /// The twk skill, a copy in each of the two directories agents look in:
  /// `.agents/skills/twk` and `.claude/skills/twk`, as `twk agents`
  /// writes them.
  skill('skill', 'the twk skill, in .agents/skills and .claude/skills', {
    AgentsFile.agentsSkill,
    AgentsFile.claudeSkill,
  });

  const CreateAgents(this.flag, this.description, this.files);

  /// What `--agents` calls it.
  final String flag;

  /// What it is, in a line.
  final String description;

  /// The files `twk agents` writes for it.
  final Set<AgentsFile> files;
}

/// What `twk create` is told or asks: the `template` and the `agents`
/// files to write.
typedef CreateAnswers = ({Template template, Set<AgentsFile> agents});

/// Whether somebody can be asked: stdin and stdout are both a terminal.
/// The one place that says so; a process an agent or CI starts has a pipe
/// at one of them at least, and is never asked.
bool canAsk({required bool stdinIsTerminal, required bool stdoutIsTerminal}) =>
    stdinIsTerminal && stdoutIsTerminal;

/// The process's own terminal to ask on where [canAsk] of its stdin and
/// stdout, else null.
CliTerminal? askTerminal() =>
    canAsk(
      stdinIsTerminal: stdin.hasTerminal,
      stdoutIsTerminal: stdout.hasTerminal,
    )
    ? CliTerminal.system()
    : null;

/// Asks on [cli] for what is null of [template] and [agents], and returns
/// all of it: the template is chosen from [templates], the files for
/// agents from [CreateAgents], both the recommended ones at first. What
/// was given is not asked.
///
/// Where [cli] cannot be answered ([CliMode.nonInteractive]: `CI` is set
/// though there is a terminal) it asks nothing and takes the defaults of
/// a run without a terminal: the first template, no files for agents.
/// Throws a [PromptCancelledException] where the person leaves a prompt
/// with Ctrl+C or Ctrl+D; nothing is written then, as nothing is by this.
Future<CreateAnswers> askCreate(
  Cli cli, {
  Template? template,
  Set<AgentsFile>? agents,
}) async {
  if (cli.mode == CliMode.nonInteractive) {
    return (template: template ?? templates.first, agents: agents ?? const {});
  }
  final chosen =
      template ??
      await cli.chooseOne<Template>(
        'Which app?',
        choices: templates,
        defaultValue: templates.first,
        display: (t) => '${t.name}  ${t.description}',
        filter: false,
      );
  if (agents != null) {
    return (template: chosen, agents: agents);
  }
  final files = await cli.chooseAny<CreateAgents>(
    'Files for coding agents?',
    choices: CreateAgents.values,
    defaultValues: CreateAgents.values,
    display: (a) => '${a.flag}  ${a.description}',
    filter: false,
  );
  return (
    template: chosen,
    agents: {for (final a in files) ...a.files},
  );
}

/// What [createApp] did, or in a dry run would do.
typedef CreatedApp = ({UnpackPlan plan, AgentsPlan? agents});

/// Makes the package [name] in [dir] of [template] ([createPlan], mold's
/// `Unbundler.apply`) and then writes [agents], the files for coding
/// agents, as `twk agents` does ([agentsPlan], [AgentsPlan.apply]): the
/// package first, so that they are written into a package that is there.
/// With [dryRun] nothing is written. The files for agents are planned
/// before anything is, so that a refusal of them (an `AGENTS.md` with
/// markers out of order) leaves the directory as it was.
///
/// Throws a [ValidationException] where mold refuses, an
/// [AgentsException] where the files for agents cannot be written.
Future<CreatedApp> createApp(
  Template template,
  String name, {
  required String dir,
  String? checkout,
  bool overwrite = false,
  bool dryRun = false,
  Set<AgentsFile> agents = const {},
}) async {
  final agentsFirst = agents.isEmpty ? null : agentsPlan(dir, files: agents);
  final plan = createPlan(
    template,
    name,
    dir: dir,
    checkout: checkout,
    overwrite: overwrite,
  );
  if (!dryRun) {
    await const Unbundler().apply(plan, onWarning: _warn);
    agentsFirst?.apply();
  }
  return (plan: plan, agents: agentsFirst);
}

/// What unpacking [template] as a package named [name] into [dir] does,
/// as mold plans it, its pubspec taking twk, twk_dev, twk_lints and
/// twk_test as [withTwkFrom] says for [checkout]: mold's `Unbundler.apply`
/// writes it, making [dir] and the directories on the way to it that are
/// not there.
///
/// Into a directory that is not empty with [overwrite] alone, each file
/// of the template over the one of the same path, the others left as
/// they are. Throws a [ValidationException] when mold refuses the unpack.
///
/// mold's variables put a value in place of a literal, while a package
/// taken by path or by version is a YAML of another shape, so the pubspec
/// is rewritten as mold plans it rather than by the template, so what
/// the plan says of it, whether the one there is the same among it, is
/// about the pubspec written.
UnpackPlan createPlan(
  Template template,
  String name, {
  required String dir,
  String? checkout,
  bool overwrite = false,
  bool warn = true,
}) => const Unbundler().plan(
  bytes: template.archive,
  targetDir: dir,
  vars: {packageNameVariable: name},
  overwrite: overwrite,
  withContent: false,
  rewrite: (path, bytes) => path == 'pubspec.yaml'
      ? utf8.encode(withTwkFrom(utf8.decode(bytes), checkout: checkout))
      : bytes,
  onWarning: warn ? _warn : null,
);

/// [error]'s message, with the option of `twk create` that gets past it
/// where there is one: mold's speaks of an overwrite, not of `--force`.
String _hinted(ValidationError error) => switch (error.code) {
  MoldCode.targetOccupied => '${error.message} --force writes into it.',
  _ => error.message,
};

void _warn(ValidationError warning) =>
    stderr.writeln('twk create: ${warning.message}');

/// [text] as a package name: in lower case, other characters than
/// letters, digits and `_` as `_`.
String packageNameOf(String text) =>
    text.toLowerCase().replaceAll(RegExp('[^a-z0-9_]'), '_');

/// What makes [name] no name for the package, null when it is one: a
/// lower case letter first, then lower case letters, digits and `_`, none
/// of the words pub refuses and none of the packages it depends on.
String? packageNameError(String name) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
    return '"$name" is not a package name: a lower case letter first, then '
        'lower case letters, digits and _';
  }
  if (_reserved.contains(name)) {
    return '"$name" is a reserved word';
  }
  if (_taken.contains(name)) {
    return '"$name" is the name of a package the app depends on';
  }
  return null;
}

/// The words pub refuses as a package's name, the reserved words of Dart
/// among them.
final Set<String> _reserved =
    'abstract as assert await break case catch class const continue '
            'covariant default deferred do else enum export extends '
            'external false final finally for hide if implements import in '
            'inline interface is late library mixin new null of on operator '
            'part required rethrow return sealed set super switch this '
            'throw true try type var void while with yield'
        .split(' ')
        .toSet();

/// The packages a project depends on, which it cannot be named as.
const _taken = {
  'pro_lints',
  'test',
  'twk',
  'twk_core',
  'twk_dev',
  'twk_lints',
  'twk_test',
};

/// Whether [dir] is a checkout of the twk repository: it has the packages
/// a project takes by path.
bool isCheckout(String dir) =>
    const [
      'twk',
      'twk_test',
      'twk_dev',
      'twk_lints',
    ].every(
      (package) =>
          File(p.join(dir, 'packages', package, 'pubspec.yaml')).existsSync(),
    );

/// The checkout of the twk repository this command runs from: the nearest
/// directory from this package's library up, or from the script's, that
/// [isCheckout]; null when there is none.
Future<String?> checkoutOfCommand() async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:twk_dev/twk_dev.dart'),
  );
  for (final uri in [?library, Platform.script]) {
    if (uri.scheme != 'file') {
      continue;
    }
    for (var dir = p.dirname(uri.toFilePath()); ; dir = p.dirname(dir)) {
      if (isCheckout(dir)) {
        return dir;
      }
      if (p.dirname(dir) == dir) {
        break;
      }
    }
  }
  return null;
}

/// [word] as a shell reads it back: quoted where it holds more than
/// letters, digits and `@%+=:,./-`.
String _quoted(String word) => RegExp(r'^[\w@%+=:,./-]+$').hasMatch(word)
    ? word
    : "'${word.replaceAll("'", r"'\''")}'";
