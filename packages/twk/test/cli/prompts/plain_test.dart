import 'package:test/test.dart';
import 'package:twk/cli.dart';
import 'package:twk_test/cli.dart';

Matcher _cancelled(String question) => isA<PromptCancelledException>()
    .having((e) => e.question, 'question', question)
    .having((e) => e.reason, 'reason', PromptCancelReason.endOfInput);

void main() {
  group('on a plain terminal, prompt', () {
    test('reads a line after the question and its default', () async {
      final terminal = FakeCliTerminal.plain(lines: ['anna']);
      final cli = Cli(terminal: terminal);
      expect(await cli.prompt('Name?', defaultValue: 'my_app'), 'anna');
      expect(terminal.screenLines, ['? Name? (my_app) anna']);
    });

    test('answers its default for an empty line', () async {
      final terminal = FakeCliTerminal.plain(lines: ['']);
      final cli = Cli(terminal: terminal);
      expect(await cli.prompt('Name?', defaultValue: 'my_app'), 'my_app');
      expect(
        await Cli(terminal: FakeCliTerminal.plain(lines: [''])).prompt(
          'Name?',
        ),
        '',
      );
    });

    test('asks again after an answer validate refuses, saying why', () async {
      final terminal = FakeCliTerminal.plain(lines: ['x', '8080']);
      final cli = Cli(terminal: terminal);
      expect(
        await cli.prompt(
          'Port?',
          validate: (v) => int.tryParse(v) == null ? 'not a number' : null,
        ),
        '8080',
      );
      expect(terminal.screenLines, [
        '? Port? x',
        '✗ not a number',
        '? Port? 8080',
      ]);
      expect(terminal.reads, 2);
    });

    test('reads a hidden line without echo, the default not shown', () async {
      final terminal = FakeCliTerminal.plain(lines: ['secret']);
      final cli = Cli(terminal: terminal);
      expect(
        await cli.prompt('Token?', hidden: true, defaultValue: 'old'),
        'secret',
      );
      expect(terminal.screenLines, ['? Token?']);
      expect(terminal.out.toString(), isNot(contains('secret')));
    });

    test('throws at the end of input', () async {
      final terminal = FakeCliTerminal.plain();
      final cli = Cli(terminal: terminal);
      await expectLater(cli.prompt('Name?'), throwsA(_cancelled('Name?')));
    });
  });

  test('closing the console lets go of the input', () async {
    final terminal = FakeCliTerminal.plain(lines: ['a', 'b']);
    final cli = Cli(terminal: terminal);
    expect(await cli.prompt('A?'), 'a');
    await cli.close();
    expect(terminal.closed, isTrue);
  });

  group('on a plain terminal, promptAny', () {
    test('splits the line on the separator, the blanks dropped', () async {
      final terminal = FakeCliTerminal.plain(lines: [' a, b,, c ', 'x y']);
      final cli = Cli(terminal: terminal);
      expect(await cli.promptAny('Tags?'), ['a', 'b', 'c']);
      expect(await cli.promptAny('Words?', separator: ' '), ['x', 'y']);
    });

    test('answers its defaults for an empty line, shown joined', () async {
      final terminal = FakeCliTerminal.plain(lines: ['']);
      final cli = Cli(terminal: terminal);
      expect(await cli.promptAny('Tags?', defaultValues: ['a', 'b']), [
        'a',
        'b',
      ]);
      expect(terminal.screenLines, ['? Tags? (a, b)']);
    });

    test('asks again after values validate refuses', () async {
      final terminal = FakeCliTerminal.plain(lines: ['', 'a']);
      final cli = Cli(terminal: terminal);
      expect(
        await cli.promptAny(
          'Tags?',
          validate: (v) => v.isEmpty ? 'at least one' : null,
        ),
        ['a'],
      );
      expect(terminal.screenLines, ['? Tags?', '✗ at least one', '? Tags? a']);
    });
  });

  group('on a plain terminal, confirm', () {
    test('takes y, yes, n and no in any case', () async {
      final terminal = FakeCliTerminal.plain(lines: ['Y', 'yes', 'N', 'No']);
      final cli = Cli(terminal: terminal);
      expect(await cli.confirm('A?'), isTrue);
      expect(await cli.confirm('B?'), isTrue);
      expect(await cli.confirm('C?'), isFalse);
      expect(await cli.confirm('D?'), isFalse);
    });

    test('asks again after anything else', () async {
      final terminal = FakeCliTerminal.plain(lines: ['maybe', 'y']);
      final cli = Cli(terminal: terminal);
      expect(await cli.confirm('Proceed?', defaultValue: false), isTrue);
      expect(terminal.screenLines, [
        '? Proceed? [y/N] maybe',
        '✗ answer y or n',
        '? Proceed? [y/N] y',
      ]);
    });

    test('takes an empty answer for its default only', () async {
      final terminal = FakeCliTerminal.plain(lines: ['', '', 'n']);
      final cli = Cli(terminal: terminal);
      expect(await cli.confirm('A?', defaultValue: true), isTrue);
      expect(await cli.confirm('B?'), isFalse);
      expect(terminal.screenLines, [
        '? A? [Y/n]',
        '? B? [y/n]',
        '✗ answer y or n',
        '? B? [y/n] n',
      ]);
    });

    test('throws at the end of input', () async {
      final cli = Cli(terminal: FakeCliTerminal.plain());
      await expectLater(
        cli.confirm('Proceed?', defaultValue: true),
        throwsA(_cancelled('Proceed?')),
      );
    });
  });

  group('on a plain terminal, chooseOne', () {
    test('numbers the choices and reads a number', () async {
      final terminal = FakeCliTerminal.plain(lines: ['3']);
      final cli = Cli(terminal: terminal);
      expect(
        await cli.chooseOne('Env?', choices: ['dev', 'stage', 'prod']),
        'prod',
      );
      expect(terminal.screenLines, [
        '? Env?',
        '  1) dev',
        '  2) stage',
        '  3) prod',
        'Enter a number (1): 3',
      ]);
    });

    test('takes a choice as it reads, in any case', () async {
      final terminal = FakeCliTerminal.plain(lines: ['Stage']);
      final cli = Cli(terminal: terminal);
      expect(
        await cli.chooseOne(
          'Env?',
          choices: [1, 2],
          display: (n) => n == 1 ? 'dev' : 'stage',
        ),
        2,
      );
    });

    test('answers its default for an empty line, else the first', () async {
      final terminal = FakeCliTerminal.plain(lines: ['', '']);
      final cli = Cli(terminal: terminal);
      expect(
        await cli.chooseOne('A?', choices: ['x', 'y'], defaultValue: 'y'),
        'y',
      );
      expect(await cli.chooseOne('B?', choices: ['x', 'y']), 'x');
      expect(terminal.screenLines, contains('Enter a number (2):'));
    });

    test('asks again for a number out of range or no choice', () async {
      final terminal = FakeCliTerminal.plain(lines: ['4', 'qa', '1']);
      final cli = Cli(terminal: terminal);
      expect(await cli.chooseOne('Env?', choices: ['dev', 'prod']), 'dev');
      expect(terminal.screenLines.skip(3), [
        'Enter a number (1): 4',
        '✗ answer a number from 1 to 2',
        'Enter a number (1): qa',
        '✗ answer a number from 1 to 2',
        'Enter a number (1): 1',
      ]);
    });

    test('throws at the end of input', () async {
      final cli = Cli(terminal: FakeCliTerminal.plain());
      await expectLater(
        cli.chooseOne('Env?', choices: ['dev']),
        throwsA(_cancelled('Env?')),
      );
    });
  });

  group('on a plain terminal, chooseAny', () {
    test('reads numbers separated by commas or blanks, in order', () async {
      final terminal = FakeCliTerminal.plain(lines: ['3,1', '2 3']);
      final cli = Cli(terminal: terminal);
      const choices = ['Linter', 'Docker', 'Tests'];
      expect(await cli.chooseAny('A?', choices: choices), ['Linter', 'Tests']);
      expect(await cli.chooseAny('B?', choices: choices), ['Docker', 'Tests']);
      expect(terminal.screenLines.take(5), [
        '? A?',
        '  1) Linter',
        '  2) Docker',
        '  3) Tests',
        'Enter numbers separated by commas: 3,1',
      ]);
    });

    test('answers its defaults for an empty line', () async {
      final terminal = FakeCliTerminal.plain(lines: ['']);
      final cli = Cli(terminal: terminal);
      expect(
        await cli.chooseAny(
          'F?',
          choices: ['a', 'b', 'c'],
          defaultValues: ['c', 'a'],
        ),
        ['a', 'c'],
      );
      expect(
        terminal.screenLines.last,
        'Enter numbers separated by commas (1,3):',
      );
    });

    test(
      'asks again for fewer than min, more than max, or no choice',
      () async {
        final terminal = FakeCliTerminal.plain(
          lines: ['', '1,2,3', '1,9', '2,3'],
        );
        final cli = Cli(terminal: terminal);
        expect(
          await cli.chooseAny('F?', choices: ['a', 'b', 'c'], min: 1, max: 2),
          ['b', 'c'],
        );
        expect(
          terminal.screenLines.where((line) => line.startsWith('✗')),
          [
            '✗ choose at least 1',
            '✗ choose at most 2',
            '✗ answer numbers from 1 to 3',
          ],
        );
      },
    );

    test('throws at the end of input', () async {
      final cli = Cli(terminal: FakeCliTerminal.plain());
      await expectLater(
        cli.chooseAny('F?', choices: ['a']),
        throwsA(_cancelled('F?')),
      );
    });
  });
}
