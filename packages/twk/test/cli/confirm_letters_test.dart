// An interactive yes or no answers to the first letters of the words of the
// TwkStrings in use too, as a plain terminal does, besides y and n.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/cli.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/cli.dart';

const _frame = Duration(milliseconds: 60);

const _russian = TwkStrings(
  yes: 'да',
  no: 'нет',
  yesLabel: 'Да',
  noLabel: 'Нет',
);

void main() {
  late FakeClock clock;
  late FakeCliTerminal terminal;
  late Cli cli;

  setUp(() {
    clock = FakeClock();
    terminal = FakeCliTerminal.interactive(
      width: 50,
      height: 16,
      fakeClock: clock,
    );
    cli = Cli(terminal: terminal, strings: _russian);
  });

  tearDown(() => clock.elapseUntil(cli.close(), step: _frame));

  Future<bool> answerWith(String key) async {
    final answer = cli.confirm('Удалить?');
    var done = false;
    unawaited(answer.then((_) => done = true));
    for (var i = 0; i < 100; i++) {
      if (terminal.screenLines.any((line) => line.startsWith('? '))) {
        break;
      }
      await clock.elapse(_frame);
    }
    await clock.elapse(_frame);
    terminal.type(key);
    await clock.elapse(_frame);
    expect(done, isTrue, reason: 'answered to $key');
    return answer;
  }

  test('takes the first letter of yes, in either case', () async {
    expect(await answerWith('д'), isTrue);
  });

  test('takes the first letter of no', () async {
    expect(await answerWith('Н'), isFalse);
  });

  test('still takes y', () async {
    expect(await answerWith('y'), isTrue);
  });

  test('a progress closes with the time in the decimal separator', () async {
    final comma = Cli(
      terminal: terminal,
      strings: const TwkStrings(decimalSeparator: ','),
    );
    final progress = comma.progress('Build');
    await clock.elapse(const Duration(milliseconds: 3100));
    progress.complete('Built');
    await clock.elapse(const Duration(milliseconds: 50));
    expect(terminal.screenLines, ['✓ Built in 3,1 s']);
    await clock.elapseUntil(comma.close(), step: _frame);
  });
}
