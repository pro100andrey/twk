// The command-line tool's tests: the Recipes guide.
import '../../example/guides/deploy.dart';
import 'package:test/test.dart';
import 'package:twk/cli.dart';
import 'package:twk_test/cli.dart';

void main() {
  test('where nobody can answer, the default is taken', () async {
    final terminal = FakeCliTerminal();
    await deploy(Cli(terminal: terminal), []);
    expect(terminal.out.toString(), contains('Deployed to dev'));
  });

  test('on a plain terminal, a choice is answered by its number', () async {
    final terminal = FakeCliTerminal.plain(lines: ['3', 'n']);
    await deploy(Cli(terminal: terminal), []);
    expect(terminal.out.toString(), contains('Nothing deployed.'));
  });

  test('at a terminal, each answer collapses into its line', () async {
    final terminal = FakeCliTerminal.interactive(input: ['\x1B[B', '\r']);
    final cli = Cli(terminal: terminal);
    await deploy(cli, []);
    await cli.close();
    expect(terminal.screenLines, contains('✔ Target environment? stage'));
  });
}
