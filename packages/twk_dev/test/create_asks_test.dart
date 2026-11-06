// What `twk create` asks, and when: the template and the files for coding
// agents that the flags left, in a terminal; nothing without one. The asking
// runs on twk_test's FakeCliTerminal, the command in this process (`TwkHere`)
// with that terminal given to it, so that no `dart pub get` and no process
// is in it: what a real process does without a terminal is
// create_no_terminal_test.dart's.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk/cli.dart';
import 'package:twk_dev/src/agents.dart';
import 'package:twk_dev/src/create.dart';
import 'package:twk_dev/src/templates/templates.dart';
import 'package:twk_dev/twk_dev.dart';
import 'package:twk_test/cli.dart';

import 'create_cycle.dart';
import 'twk.dart';

const _enter = '\r';
const _down = '\x1B[B';
const _ctrlC = '\x03';

/// A terminal somebody answers at, `answers` typed as each question shows,
/// and the questions it was asked in [asked].
FakeCliTerminal terminalWith(List<String> answers, List<String> asked) =>
    FakeCliTerminal.interactive(answers: answers)..onPrompt = asked.add;

void main() {
  late String root;
  late String dir;

  setUp(() async {
    root = await temporary();
    dir = p.join(root, 'my_app');
  });

  /// `twk create` with [arguments] in this process, `terminal` the one it
  /// may ask on (null: none).
  Future<ProcessResult> create(
    List<String> arguments,
    CliTerminal? Function() terminal,
  ) async {
    final run = TwkHere.start(
      ['create', dir, ...arguments],
      twk: (arguments) async {
        final runner = CommandRunner<int>('twk', '')
          ..addCommand(CreateCommand(terminal: terminal));
        try {
          return await runner.run(arguments) ?? 0;
        } on UsageException catch (error) {
          stderr.writeln(error);
          return usageExitCode;
        }
      },
    );
    final code = await run.exitCode;
    return ProcessResult(0, code, '${run.out}', '${run.err}');
  }

  bool has(String path) =>
      FileSystemEntity.typeSync(p.join(dir, path)) !=
      FileSystemEntityType.notFound;

  String pubspecName() => File(
    p.join(dir, 'pubspec.yaml'),
  ).readAsLinesSync().firstWhere((l) => l.startsWith('name:'));

  group('canAsk', () {
    test('only where stdin and stdout are both a terminal', () {
      for (final (i, o, asks) in [
        (true, true, true),
        (true, false, false),
        (false, true, false),
        (false, false, false),
      ]) {
        expect(
          canAsk(stdinIsTerminal: i, stdoutIsTerminal: o),
          asks,
          reason: 'stdin $i, stdout $o',
        );
      }
    });

    test('the process the tests run in, stdin a pipe or none, has none to '
        'ask on', () {
      // dart test gives a pipe or a file at one of them at least
      expect(
        askTerminal() == null,
        !(stdin.hasTerminal && stdout.hasTerminal),
      );
    });
  });

  group('askCreate', () {
    test(
      'asks the template and the files, the first and both at Enter',
      () async {
        final asked = <String>[];
        final cli = Cli(terminal: terminalWith([_enter, _enter], asked));
        final answers = await askCreate(cli);
        await cli.close();

        expect(asked, ['Which app?', 'Files for coding agents?']);
        expect(answers.template.name, 'app');
        expect(answers.agents, {...AgentsFile.values});
      },
    );

    test('takes the template the cursor is moved to, and the files '
        'unticked', () async {
      final asked = <String>[];
      // form: two down; of the files, Space unticks the first (agents-md)
      final cli = Cli(
        terminal: terminalWith([_down + _down + _enter, ' $_enter'], asked),
      );
      final answers = await askCreate(cli);
      await cli.close();

      expect(answers.template.name, 'form');
      expect(answers.agents, CreateAgents.skill.files);
    });

    test('asks only what the flags left', () async {
      final asked = <String>[];
      final cli = Cli(terminal: terminalWith([_enter], asked));
      final answers = await askCreate(cli, template: templates[2]);
      await cli.close();
      expect(asked, ['Files for coding agents?']);
      expect(answers.template.name, 'form');

      asked.clear();
      final other = Cli(terminal: terminalWith([_down + _enter], asked));
      final templateOnly = await askCreate(other, agents: const {});
      await other.close();
      expect(asked, ['Which app?']);
      expect(templateOnly.template.name, 'inline');
      expect(templateOnly.agents, isEmpty);
    });

    test('asks nothing where all is said', () async {
      final asked = <String>[];
      final cli = Cli(terminal: terminalWith([], asked));
      final answers = await askCreate(
        cli,
        template: templates.first,
        agents: {AgentsFile.agentsMd},
      );
      await cli.close();
      expect(asked, isEmpty);
      expect(answers.agents, {AgentsFile.agentsMd});
    });

    test('asks nothing where nobody can answer, though it was called: the '
        'defaults of a run without a terminal', () async {
      final terminal = FakeCliTerminal();
      final asked = <String>[];
      terminal.onPrompt = asked.add;
      final cli = Cli(terminal: terminal);
      final answers = await askCreate(cli);
      await cli.close();
      expect(asked, isEmpty);
      expect(answers.template.name, templates.first.name);
      expect(answers.agents, isEmpty);
    });

    test('Ctrl+C is a cancel', () async {
      final cli = Cli(terminal: terminalWith([_ctrlC], []));
      await expectLater(
        askCreate(cli),
        throwsA(
          isA<PromptCancelledException>().having(
            (e) => e.reason,
            'reason',
            PromptCancelReason.interrupt,
          ),
        ),
      );
      await cli.close();
    });
  });

  group('the command', () {
    test('in a terminal asks both, and writes the package and the files '
        'for agents after it', () async {
      final asked = <String>[];
      final terminal = terminalWith([_down + _down + _enter, _enter], asked);
      final result = await create([], () => terminal);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(asked, ['Which app?', 'Files for coding agents?']);
      expect(result.stdout, contains('of the template form'));
      expect(result.stdout, contains('.agents/skills/twk'));
      expect(result.stdout, contains('AGENTS.md'));
      expect(pubspecName(), 'name: my_app');
      expect(has('lib/my_app.dart'), isTrue);
      expect(has('AGENTS.md'), isTrue);
      expect(has('.agents/skills/twk/SKILL.md'), isTrue);
      expect(has('.claude/skills/twk/SKILL.md'), isTrue);
      expect(File(p.join(dir, 'AGENTS.md')).readAsStringSync(), agentsBlock);
    });

    test('--template asks only for the files', () async {
      final asked = <String>[];
      final terminal = terminalWith([_enter], asked);
      final result = await create(['--template=inline'], () => terminal);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(asked, ['Files for coding agents?']);
      expect(result.stdout, contains('of the template inline'));
      expect(has('AGENTS.md'), isTrue);
    });

    test('--agents asks only for the template', () async {
      final asked = <String>[];
      final terminal = terminalWith([_enter], asked);
      final result = await create(['--agents=skill'], () => terminal);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(asked, ['Which app?']);
      expect(has('.agents/skills/twk/SKILL.md'), isTrue);
      expect(has('.claude/skills/twk/SKILL.md'), isTrue);
      expect(has('AGENTS.md'), isFalse);
    });

    test('--agents=agents-md writes the block alone', () async {
      final result = await create([
        '--template=app',
        '--agents=agents-md',
      ], () => throw StateError('asked'));

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(has('AGENTS.md'), isTrue);
      expect(has('.agents'), isFalse);
      expect(has('.claude'), isFalse);
    });

    test('--agents=agents-md,skill writes all three', () async {
      final result = await create([
        '-t',
        'app',
        '--agents=agents-md,skill',
      ], () => throw StateError('asked'));

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(has('AGENTS.md'), isTrue);
      expect(has('.agents/skills/twk/SKILL.md'), isTrue);
      expect(has('.claude/skills/twk/SKILL.md'), isTrue);
    });

    test(
      '--agents=none writes none, and with --template asks nothing',
      () async {
        final result = await create([
          '--template=app',
          '--agents=none',
        ], () => throw StateError('asked'));

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(has('lib/my_app.dart'), isTrue);
        expect(has('AGENTS.md'), isFalse);
        expect(has('.agents'), isFalse);
      },
    );

    test('--agents=none leaves the template to ask', () async {
      final asked = <String>[];
      final terminal = terminalWith([_enter], asked);
      final result = await create(['--agents=none'], () => terminal);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(asked, ['Which app?']);
      expect(has('AGENTS.md'), isFalse);
    });

    test('a value it does not know, or none with another, is a usage error '
        'and writes nothing', () async {
      for (final value in ['bogus', 'skill,bogus', 'none,skill']) {
        final result = await create([
          '--template=app',
          '--agents=$value',
        ], () => throw StateError('asked'));
        expect(result.exitCode, 64, reason: value);
        expect(result.stderr, contains('agents'), reason: value);
        expect(Directory(dir).existsSync(), isFalse, reason: value);
      }
    });

    test('without a terminal asks nothing and takes the defaults: the app, '
        'no files for agents', () async {
      final result = await create([], () => null);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('of the template app'));
      expect(has('lib/my_app.dart'), isTrue);
      expect(has('AGENTS.md'), isFalse);
      expect(has('.agents'), isFalse);
      expect(has('.claude'), isFalse);
      // nobody could be asked: the next steps say how an agent gets the skill
      expect(result.stdout, contains('twk_dev:twk agents  # the twk skill'));
    });

    test('with a terminal nobody can answer at (CI set on a tty) nothing is '
        'asked, and the next steps say how an agent gets the skill', () async {
      final result = await create([], FakeCliTerminal.new);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(has('lib/my_app.dart'), isTrue);
      expect(has('AGENTS.md'), isFalse);
      expect(result.stdout, contains('twk_dev:twk agents  # the twk skill'));
    });

    test('in a terminal that is asked the hint is not shown', () async {
      final result = await create(
        [],
        () => terminalWith([_enter, _enter], []),
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, isNot(contains('# the twk skill')));
    });

    test('without a terminal --agents=none says no file, and hears no more '
        'of it', () async {
      final result = await create(['--agents=none'], () => null);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, isNot(contains('# the twk skill')));
    });

    test('without a terminal, what the flags say is taken as it is', () async {
      final result = await create([
        '--template=dashboard',
        '--agents=skill',
      ], () => null);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('of the template dashboard'));
      expect(has('.agents/skills/twk/SKILL.md'), isTrue);
      expect(has('AGENTS.md'), isFalse);
      expect(result.stdout, isNot(contains('# the twk skill')));
    });

    test('Ctrl+C at the first question writes nothing and exits non-zero '
        'with the interrupt code', () async {
      final asked = <String>[];
      final terminal = terminalWith([_ctrlC], asked);
      final result = await create([], () => terminal);

      expect(result.exitCode, 130);
      expect(asked, ['Which app?']);
      expect(Directory(dir).existsSync(), isFalse);
    });

    test('Ctrl+C at the second writes nothing either', () async {
      final asked = <String>[];
      final terminal = terminalWith([_enter, _ctrlC], asked);
      final result = await create([], () => terminal);

      expect(result.exitCode, 130);
      expect(asked, ['Which app?', 'Files for coding agents?']);
      expect(Directory(dir).existsSync(), isFalse);
    });

    test('Ctrl+D is a cancel too, with the code 1', () async {
      final terminal = terminalWith(['\x04'], []);
      final result = await create([], () => terminal);

      expect(result.exitCode, 1);
      expect(Directory(dir).existsSync(), isFalse);
    });

    test('--dry-run asks, and writes none of it', () async {
      final terminal = terminalWith([_enter, _enter], []);
      final result = await create(['--dry-run'], () => terminal);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('would write'));
      expect(result.stdout, contains('twk agents --dry-run'));
      expect(Directory(dir).existsSync(), isFalse);
    });

    test('an AGENTS.md it cannot merge into leaves the directory as it '
        'was', () async {
      Directory(dir).createSync(recursive: true);
      File(p.join(dir, 'AGENTS.md')).writeAsStringSync(agentsEnd);
      final result = await create([
        '--force',
        '--template=app',
        '--agents=agents-md',
      ], () => null);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('AGENTS.md'));
      expect(has('pubspec.yaml'), isFalse);
    });

    test('a directory that is not empty is refused before any question, with '
        'the message it has without a terminal', () async {
      Directory(dir).createSync(recursive: true);
      File(p.join(dir, 'mine.txt')).writeAsStringSync('mine');
      final asked = <String>[];
      final terminal = terminalWith([_enter, _enter], asked);
      final result = await create([], () => terminal);

      expect(result.exitCode, 1);
      expect(asked, isEmpty);
      expect(
        result.stderr,
        'twk create: Target already exists and is not empty: $dir; only an '
        'overwrite unpack writes into one. --force writes into it.\n',
      );
      expect(has('pubspec.yaml'), isFalse);
      final without = await create([], () => null);
      expect(without.stderr, result.stderr);
    });

    test('with --force a directory that is not empty is asked about, as '
        'before', () async {
      Directory(dir).createSync(recursive: true);
      File(p.join(dir, 'mine.txt')).writeAsStringSync('mine');
      final asked = <String>[];
      final terminal = terminalWith([_enter, _enter], asked);
      final result = await create(['--force'], () => terminal);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(asked, ['Which app?', 'Files for coding agents?']);
      expect(has('pubspec.yaml'), isTrue);
      expect(has('mine.txt'), isTrue);
    });

    test('--help lists --agents with its values', () async {
      final result = await twkHere(['create', '--help']);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('--agents'));
      expect(result.stdout, contains('agents-md'));
      expect(result.stdout, contains('none'));
    });

    test('--list still lists the templates', () async {
      final result = await create(['--list'], () => throw StateError('x'));
      expect(result.exitCode, 0);
      expect(result.stdout, contains('dashboard'));
    });
  });
}
