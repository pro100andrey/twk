// `twk completion <shell>`: the script of each shell names every subcommand
// and option the command has (written from its parsers), the files each
// command takes, and the command refuses an unknown shell.
import 'package:args/command_runner.dart';
import 'package:test/test.dart';
import 'package:twk_dev/src/cli.dart';
import 'package:twk_dev/src/completion.dart';

import 'twk.dart';

void main() {
  final runner = twkRunner();

  for (final shell in CompletionShell.values) {
    group(shell.name, () {
      final script = completionScript(runner, shell);

      test('names every subcommand', () {
        for (final c in runner.commands.values) {
          expect(script, contains(c.name), reason: 'command ${c.name}');
        }
      });

      test('names every option of every subcommand', () {
        for (final Command<Object?> c in runner.commands.values) {
          for (final o in c.argParser.options.values) {
            expect(
              script,
              contains(o.name),
              reason: '--${o.name} of ${c.name}',
            );
            if (o.isFlag && (o.negatable ?? false)) {
              expect(script, contains('no-${o.name}'));
            }
          }
        }
      });

      test('takes the recordings, tapes and programs by extension', () {
        expect(script, contains('cast'));
        expect(script, contains('tape'));
        expect(script, contains('dart'));
        // The allowed values of an option.
        expect(script, contains('dashboard'));
      });
    });
  }

  test('twk completion <shell> prints the script and gives 0', () async {
    for (final shell in CompletionShell.values) {
      final result = await twkHere(['completion', shell.name]);
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        startsWith(switch (shell) {
          CompletionShell.bash => '# bash completion',
          CompletionShell.zsh => '#compdef twk',
          CompletionShell.fish => '# fish completion',
        }),
      );
    }
  });

  test('twk completion with no shell or an unknown one gives 64', () async {
    expect((await twkHere(['completion'])).exitCode, 64);
    final result = await twkHere(['completion', 'powershell']);
    expect(result.exitCode, 64);
    expect(result.stderr, contains('Unknown shell "powershell"'));
  });

  test('fish: a backslash in a help text is escaped before the quotes', () {
    final odd = CommandRunner<int>('twk', 'x')..addCommand(_Odd());
    final script = completionScript(odd, CompletionShell.fish);
    // help `ends\` and `it\'s`: every backslash doubled, then the quote
    expect(script, contains(r"-d 'ends\\'"));
    expect(script, contains(r"-d 'it\\\'s'"));
  });

  test('every command of twk says what its arguments are completed with', () {
    for (final c in runner.commands.values) {
      if (c.name == 'help') {
        continue; // the runner's own
      }
      expect(c, isA<Completes>(), reason: '${c.name} has no completion kind');
      for (final o in c.argParser.options.values) {
        if (const {'path', 'dir', 'file'}.contains(o.valueHelp)) {
          expect(
            (c as Completes).optionPaths,
            contains(o.name),
            reason: '--${o.name} of ${c.name} takes a path',
          );
        }
      }
      for (final name in (c as Completes).optionPaths.keys) {
        expect(c.argParser.options, contains(name), reason: c.name);
      }
    }
  });
}

final class _Odd extends Command<int> with Completes {
  _Odd() {
    argParser
      ..addFlag('one', help: r'ends\')
      ..addFlag('two', help: r"it\'s");
  }

  @override
  Positionals get positionals => const Positionals.none();

  @override
  String get name => 'odd';

  @override
  String get description => 'Odd.';
}
