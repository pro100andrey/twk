// FakeCliTerminal's answers: an entry typed as each question shows, so a
// wizard of several questions is one list, and onPrompt told of each.
import 'package:test/test.dart';
import 'package:twk/cli.dart';
import 'package:twk_test/cli.dart';

const _frame = Duration(milliseconds: 60);

void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock());

  Future<T> settle<T>(Future<T> future) =>
      clock.elapseUntil(future, step: _frame, within: _frame * 100);

  test('each question gets its own answer', () async {
    final terminal = FakeCliTerminal.interactive(
      answers: ['ada\r', 'y', 'n'],
      fakeClock: clock,
    );
    final cli = Cli(terminal: terminal);
    Future<List<Object>> wizard() async => [
      await cli.prompt('Name?'),
      await cli.confirm('Sure?'),
      await cli.confirm('Really?'),
    ];
    expect(await settle(wizard()), ['ada', true, false]);
    await settle(cli.close());
  });

  test('onPrompt is told of each question before its answer', () async {
    final seen = <String>[];
    final terminal = FakeCliTerminal.interactive(
      answers: ['y', 'n'],
      fakeClock: clock,
    )..onPrompt = seen.add;
    final cli = Cli(terminal: terminal);
    await settle(cli.confirm('A?'));
    expect(seen, ['A?']);
    await settle(cli.confirm('B?'));
    expect(seen, ['A?', 'B?']);
    await settle(cli.close());
  });

  test('onPrompt is told on a plain terminal too', () async {
    final seen = <String>[];
    final terminal = FakeCliTerminal.plain(lines: ['y'])..onPrompt = seen.add;
    final cli = Cli(terminal: terminal);
    expect(await cli.confirm('A?'), isTrue);
    expect(seen, ['A?']);
    await cli.close();
  });
}
