// The words Cli writes on its own, another language's when the console is
// given TwkStrings: in a log, in the interactive prompts and in the
// closing line of a progress.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/cli.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/cli.dart';

const _enter = '\r';
const _right = '\x1B[C';
const _frame = Duration(milliseconds: 60);

String _inGerman(String took) => ' nach $took';
String _fromOne(int count) => 'antworte 1 bis $count';
String _manyFromOne(int count) => 'antworte Zahlen von 1 bis $count';
String _atLeast(int min) => 'mindestens $min';
String _atMost(int max) => 'hoechstens $max';

const _german = TwkStrings(
  tookIn: _inGerman,
  confirmHintYes: 'J/n',
  confirmHintNo: 'j/N',
  confirmHint: 'j/n',
  yes: 'ja',
  no: 'nein',
  none: 'keine',
  yesLabel: 'Ja',
  noLabel: 'Nein',
  answerYesOrNo: 'antworte j oder n',
  enterNumber: 'Zahl eingeben',
  enterNumbers: 'Zahlen mit Komma eingeben',
  answerNumber: _fromOne,
  answerNumbers: _manyFromOne,
  chooseAtLeast: _atLeast,
  chooseAtMost: _atMost,
  typeToFilter: 'tippen zum Filtern',
  spaceToToggle: 'Leertaste zum Umschalten',
  typeToFilterAndToggle: 'tippen, Leertaste',
);

void main() {
  group('TwkStrings', () {
    test('are English by default and equal when their words are', () {
      expect(const TwkStrings(), const TwkStrings());
      expect(const TwkStrings().hashCode, const TwkStrings().hashCode);
      expect(const TwkStrings(yes: 'ja'), isNot(const TwkStrings()));
      expect(const TwkStrings().eta('00:07'), 'ETA 00:07');
      expect(const TwkStrings().tookIn('3 s'), ' in 3 s');
    });
  });

  group('on a plain terminal, a console with strings', () {
    test('asks and refuses a yes or no in them', () async {
      final terminal = FakeCliTerminal.plain(
        lines: ['maybe', 'j', '', 'Nein', 'y', 'ja'],
      );
      final cli = Cli(terminal: terminal, strings: _german);
      expect(await cli.confirm('Weiter?', defaultValue: false), isTrue);
      expect(await cli.confirm('A?', defaultValue: true), isTrue);
      // the words of the language answer, English ones still do
      expect(await cli.confirm('B?'), isFalse);
      expect(await cli.confirm('C?'), isTrue);
      expect(await cli.confirm('D?'), isTrue);
      expect(terminal.screenLines.take(4), [
        '? Weiter? [j/N] maybe',
        '✗ antworte j oder n',
        '? Weiter? [j/N] j',
        '? A? [J/n]',
      ]);
    });

    test('asks for a number and refuses one out of range in them', () async {
      final terminal = FakeCliTerminal.plain(lines: ['9', '2']);
      final cli = Cli(terminal: terminal, strings: _german);
      expect(await cli.chooseOne('A?', choices: ['a', 'b']), 'b');
      expect(terminal.screenLines, [
        '? A?',
        '  1) a',
        '  2) b',
        'Zahl eingeben (1): 9',
        '✗ antworte 1 bis 2',
        'Zahl eingeben (1): 2',
      ]);
    });

    test('asks for numbers and says why they are refused in them', () async {
      final terminal = FakeCliTerminal.plain(lines: ['', '1,2,3', '1,9', '2']);
      final cli = Cli(terminal: terminal, strings: _german);
      expect(
        await cli.chooseAny('F?', choices: ['a', 'b', 'c'], min: 1, max: 2),
        ['b'],
      );
      expect(terminal.screenLines.where((l) => l.startsWith('✗')), [
        '✗ mindestens 1',
        '✗ hoechstens 2',
        '✗ antworte Zahlen von 1 bis 3',
      ]);
      expect(terminal.screenLines, contains('Zahlen mit Komma eingeben: 2'));
    });

    test('writes what was assumed in them', () async {
      final terminal = FakeCliTerminal();
      final cli = Cli(terminal: terminal, strings: _german);
      expect(await cli.confirm('A?', defaultValue: false), isFalse);
      expect(
        await cli.chooseAny('B?', choices: ['x'], defaultValues: <String>[]),
        <String>[],
      );
      expect(terminal.out.toString(), contains('nein'));
      expect(terminal.out.toString(), contains('keine'));
    });

    test('shows widgets in them', () async {
      final terminal = FakeCliTerminal(columns: 20);
      await Cli(terminal: terminal, strings: _german).show(
        Builder(builder: (context) => Text(TwkStrings.of(context).yesLabel)),
      );
      expect(terminal.out.toString(), 'Ja\n');
    });

    test('Cli.run hands its strings to the console', () async {
      final terminal = FakeCliTerminal.plain(lines: ['x', 'j']);
      await Cli.run<void>(
        (cli) async {
          expect(cli.strings, _german);
          await cli.confirm('A?');
        },
        strings: _german,
        open: ({ansi, interactive}) => terminal,
      );
      expect(terminal.screenLines, contains('✗ antworte j oder n'));
    });
  });

  group('in the interactive mode, a console with strings', () {
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
      cli = Cli(terminal: terminal, strings: _german);
    });

    Future<T> settle<T>(Future<T> future) =>
        clock.elapseUntil(future, step: _frame, within: _frame * 100);

    tearDown(() => settle(cli.close()));

    Future<void> type(List<String> keys) async {
      for (var i = 0; i < 100; i++) {
        if (terminal.screenLines.any((line) => line.startsWith('? '))) {
          break;
        }
        await clock.elapse(_frame);
      }
      await clock.elapse(_frame);
      for (final key in keys) {
        terminal.type(key);
        await clock.elapse(_frame);
      }
    }

    test('writes a yes or no, its labels and refusal in them', () async {
      final ok = cli.confirm('Loeschen?');
      var answered = false;
      unawaited(ok.then((_) => answered = true));
      await type([]);
      expect(terminal.screenLines, ['? Loeschen? (j/n)  Ja   Nein']);
      await type([_enter]);
      expect(answered, isFalse);
      expect(terminal.screenLines.last, '✗ antworte j oder n');
      await type([_right, _enter]);
      expect(await settle(ok), isFalse);
      expect(terminal.screenLines, ['✔ Loeschen? nein']);
    });

    test('shows widgets in them', () async {
      await settle(
        cli.show(
          Builder(builder: (context) => Text(TwkStrings.of(context).yesLabel)),
        ),
      );
      expect(terminal.screenLines, ['Ja']);
    });

    test('hints at filtering and toggling in them', () async {
      final features = cli.chooseAny(
        'F?',
        choices: ['a', 'b'],
        filter: true,
        defaultValues: [],
      );
      await type([]);
      expect(terminal.screenLines.first, '? F? (tippen, Leertaste)');
      await type([_enter]);
      expect(await settle(features), isEmpty);
      expect(terminal.screenLines, ['✔ F? keine']);
    });

    test('closes a progress with the time it took in them', () async {
      final progress = cli.progress('Bauen');
      await clock.elapse(const Duration(milliseconds: 3100));
      progress.complete('Gebaut');
      await clock.elapse(const Duration(milliseconds: 50));
      expect(terminal.screenLines, ['✓ Gebaut nach 3.1 s']);
    });
  });
}
