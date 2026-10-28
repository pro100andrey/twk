import 'package:test/test.dart';
import 'package:twk/twk.dart' show LogLevel;
import 'package:twk_cli/testing.dart';
import 'package:twk_cli/twk_cli.dart';

Matcher _required(String question, {Object? invalidDefault}) =>
    isA<PromptAnswerRequiredException>()
        .having((e) => e.question, 'question', question)
        .having((e) => e.invalidDefault, 'invalidDefault', invalidDefault);

void main() {
  late FakeCliTerminal terminal;
  late Cli cli;

  setUp(() {
    // a pipe with something in it, which is never read
    terminal = FakeCliTerminal(lines: ['typed']);
    cli = Cli(terminal: terminal);
  });

  tearDown(() => expect(terminal.reads, 0));

  group('where nobody can answer, prompt', () {
    test('answers its default and writes what it assumed', () async {
      expect(
        await cli.prompt('Project name?', defaultValue: 'my_app'),
        'my_app',
      );
      expect(terminal.out.toString(), '? Project name? my_app\n');
    });

    test('without a default throws, naming the question', () async {
      await expectLater(
        cli.prompt('Project name?'),
        throwsA(_required('Project name?')),
      );
      expect(terminal.out.toString(), isEmpty);
    });

    test('throws with the message of a default validate refuses', () async {
      await expectLater(
        cli.prompt(
          'Port?',
          defaultValue: 'x',
          validate: (v) => int.tryParse(v) == null ? 'not a number' : null,
        ),
        throwsA(_required('Port?', invalidDefault: 'not a number')),
      );
      expect(terminal.out.toString(), isEmpty);
    });

    test('writes a hidden default as six stars, whatever its length', () async {
      expect(
        await cli.prompt('Token?', defaultValue: 'abc', hidden: true),
        'abc',
      );
      expect(terminal.out.toString(), '? Token? ******\n');
    });

    test('styles the line where the output takes ANSI', () async {
      final terminal = FakeCliTerminal(ansi: true);
      await Cli(terminal: terminal).prompt('Name?', defaultValue: 'a');
      // `?` and the answer in the primary color, the question bold
      expect(
        terminal.out.toString(),
        '\x1B[34m? \x1B[0;1mName?\x1B[0;34m a\x1B[0m\n',
      );
    });

    test('is written whatever the level', () async {
      cli.level = LogLevel.error;
      await cli.prompt('Name?', defaultValue: 'a');
      expect(terminal.out.toString(), '? Name? a\n');
    });
  });

  group('where nobody can answer, promptAny', () {
    test('answers its defaults, written joined by commas', () async {
      expect(
        await cli.promptAny('Tags?', defaultValues: ['cli', 'dart']),
        ['cli', 'dart'],
      );
      expect(terminal.out.toString(), '? Tags? cli, dart\n');
    });

    test('without defaults throws', () async {
      await expectLater(cli.promptAny('Tags?'), throwsA(_required('Tags?')));
    });

    test('throws with defaults validate refuses', () async {
      await expectLater(
        cli.promptAny(
          'Tags?',
          defaultValues: [],
          validate: (v) => v.isEmpty ? 'at least one' : null,
        ),
        throwsA(_required('Tags?', invalidDefault: 'at least one')),
      );
    });
  });

  group('where nobody can answer, confirm', () {
    test('answers its default, written as yes or no', () async {
      expect(await cli.confirm('Proceed?', defaultValue: true), isTrue);
      expect(await cli.confirm('Overwrite?', defaultValue: false), isFalse);
      expect(terminal.out.toString(), '? Proceed? yes\n? Overwrite? no\n');
    });

    test('without a default agrees to nothing: it throws', () async {
      await expectLater(cli.confirm('Delete?'), throwsA(_required('Delete?')));
      expect(terminal.out.toString(), isEmpty);
    });
  });

  group('where nobody can answer, chooseOne', () {
    test('answers its default, written as it is displayed', () async {
      expect(
        await cli.chooseOne(
          'Port?',
          choices: [80, 443],
          defaultValue: 443,
          display: (p) => ':$p',
        ),
        443,
      );
      expect(terminal.out.toString(), '? Port? :443\n');
    });

    test('throws without a default, or with one not of the choices', () async {
      await expectLater(
        cli.chooseOne('Env?', choices: ['dev', 'prod']),
        throwsA(_required('Env?')),
      );
      await expectLater(
        cli.chooseOne('Env?', choices: ['dev', 'prod'], defaultValue: 'qa'),
        throwsA(_required('Env?')),
      );
    });

    test('refuses an empty list of choices', () async {
      await expectLater(
        cli.chooseOne<String>('Env?', choices: []),
        throwsArgumentError,
      );
    });
  });

  group('where nobody can answer, chooseAny', () {
    test('answers its defaults in the order of the choices', () async {
      expect(
        await cli.chooseAny(
          'Features?',
          choices: ['Linter', 'Docker', 'Tests'],
          defaultValues: ['Tests', 'Linter', 'Helm'],
        ),
        ['Linter', 'Tests'],
      );
      expect(terminal.out.toString(), '? Features? Linter, Tests\n');
    });

    test('writes none for no defaults', () async {
      expect(
        await cli.chooseAny('Features?', choices: ['a'], defaultValues: []),
        isEmpty,
      );
      expect(terminal.out.toString(), '? Features? none\n');
    });

    test('throws without defaults', () async {
      await expectLater(
        cli.chooseAny('Features?', choices: ['a', 'b']),
        throwsA(_required('Features?')),
      );
    });

    test('throws with defaults fewer than min or more than max', () async {
      await expectLater(
        cli.chooseAny('F?', choices: ['a', 'b'], defaultValues: [], min: 1),
        throwsA(_required('F?', invalidDefault: 'choose at least 1')),
      );
      await expectLater(
        cli.chooseAny(
          'F?',
          choices: ['a', 'b', 'c'],
          defaultValues: ['a', 'b'],
          max: 1,
        ),
        throwsA(_required('F?', invalidDefault: 'choose at most 1')),
      );
    });

    test('refuses a min it cannot meet and a max below it', () async {
      await expectLater(
        cli.chooseAny('F?', choices: ['a'], min: 2),
        throwsRangeError,
      );
      await expectLater(
        cli.chooseAny('F?', choices: ['a', 'b'], min: 2, max: 1),
        throwsRangeError,
      );
    });
  });

  test('a prompt waits for the one asked before it', () async {
    final first = cli.prompt('First?', defaultValue: '1');
    final second = cli.prompt('Second?', defaultValue: '2');
    expect(await Future.wait([second, first]), ['2', '1']);
    expect(terminal.out.toString(), '? First? 1\n? Second? 2\n');
  });

  test('one that threw does not hold the next back', () async {
    await expectLater(cli.prompt('First?'), throwsA(isA<PromptException>()));
    expect(await cli.prompt('Second?', defaultValue: '2'), '2');
  });
}
