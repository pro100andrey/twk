import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/cli.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/cli.dart';

const _enter = '\r';
const _down = '\x1B[B';
const _up = '\x1B[A';
const _right = '\x1B[C';
const _escape = '\x1B';
const _backspace = '\x7F';
const _ctrlC = '\x03';
const _ctrlD = '\x04';

/// A frame and then some: what the session draws in that time.
const _frame = Duration(milliseconds: 60);

Matcher _cancelled(String question, PromptCancelReason reason) =>
    isA<PromptCancelledException>()
        .having((e) => e.question, 'question', question)
        .having((e) => e.reason, 'reason', reason);

void main() {
  // The session runs on a fake clock: a frame is drawn when the test
  // moves the clock past it, never in real time, so how busy the machine
  // is changes nothing that is seen.
  late FakeClock clock;
  late FakeCliTerminal terminal;
  late Cli cli;

  setUp(() {
    clock = FakeClock();
    terminal = FakeCliTerminal.interactive(
      width: 40,
      height: 16,
      fakeClock: clock,
    );
    cli = Cli(terminal: terminal);
  });

  /// Moves the clock a frame on.
  Future<void> frame() => clock.elapse(_frame);

  /// [future], once the clock has moved on until it completed, a frame at
  /// a time: what is answered or cancelled is drawn and done in frames.
  /// Fails after 100 frames rather than hanging.
  Future<T> settle<T>(Future<T> future) =>
      clock.elapseUntil(future, step: _frame, within: _frame * 100);

  tearDown(() => settle(cli.close()));

  /// Types [keys] once what is asked is live, a frame for each: keys
  /// typed before a prompt is on the screen reach nothing.
  Future<void> type(List<String> keys) async {
    for (var i = 0; i < 100; i++) {
      if (terminal.screenLines.any((line) => line.startsWith('? '))) {
        break;
      }
      await frame();
    }
    // and a frame more, for its focus
    await frame();
    for (final key in keys) {
      terminal.type(key);
      await frame();
    }
  }

  /// Presses Escape: a lone ESC, which the terminal takes for the key
  /// once no more input follows it.
  Future<void> escape() async {
    terminal
      ..type(_escape)
      ..backend!.timeOutInput();
    await frame();
  }

  group('in the interactive mode, prompt', () {
    test('asks in a field and commits the answer in its place', () async {
      cli.info('before');
      final name = cli.prompt('Project name?', defaultValue: 'my_app');
      await type(['anna']);
      expect(terminal.screenLines, ['before', '? Project name? (my_app) anna']);

      terminal.type(_enter);
      expect(await settle(name), 'anna');
      expect(terminal.screenLines, ['before', '✔ Project name? anna']);
      await settle(cli.close());
      expect(terminal.backend!.closed, isTrue);
      expect(terminal.screenLines, ['before', '✔ Project name? anna']);
    });

    test('answers its default at an empty field', () async {
      final name = cli.prompt('Project name?', defaultValue: 'my_app');
      await type([_enter]);
      expect(await settle(name), 'my_app');
      expect(terminal.screenLines, ['✔ Project name? my_app']);
    });

    test('shows the placeholder while the field is empty', () async {
      final name = cli.prompt('Token?', placeholder: 'empty to skip');
      await type([]);
      expect(terminal.screenLines, ['? Token? empty to skip']);
      await type(['x']);
      expect(terminal.screenLines, ['? Token? x']);
      terminal.type(_enter);
      await settle(name);
    });

    test('shows why validate refused, until the text changes', () async {
      final port = cli.prompt(
        'Port?',
        validate: (v) => int.tryParse(v) == null ? 'not a number' : null,
      );
      await type(['x', _enter]);
      expect(terminal.screenLines, ['? Port? x', '✗ not a number']);
      // in the theme's error color
      expect(terminal.screen.cell(2, 1).fg, terminal.screen.cell(0, 1).fg);
      expect(
        terminal.screen.cell(0, 1).fg,
        isNot(terminal.screen.cell(2, 0).fg),
      );

      await type([_backspace]);
      expect(terminal.screenLines, ['? Port?']);
      await type(['80', _enter]);
      expect(await settle(port), '80');
      expect(terminal.screenLines, ['✔ Port? 80']);
    });

    test(
      'masks a hidden answer as typed, and as six stars once given',
      () async {
        final token = cli.prompt('Token?', hidden: true);
        await type(['abc']);
        expect(terminal.screenLines, ['? Token? ***']);
        terminal.type(_enter);
        expect(await settle(token), 'abc');
        expect(terminal.screenLines, ['✔ Token? ******']);
        expect(terminal.screen.lines.join(), isNot(contains('abc')));
      },
    );

    test('commits the styles of the theme', () async {
      final name = cli.prompt('Name?');
      await type(['a', _enter]);
      await settle(name);
      expect(terminal.screenLines, ['✔ Name? a']);
      final screen = terminal.screen;
      const theme = ThemeData.terminal(Brightness.dark);
      expect(screen.cell(0, 0).fg, theme.success.fg);
      expect(screen.cell(2, 0).attrs & Attr.bold, Attr.bold);
      expect(screen.cell(8, 0).fg, theme.primary.fg);
      expect(screen.cell(8, 0).attrs & Attr.bold, 0);
    });

    test('Ctrl+C cancels it as an interrupt, the session kept', () async {
      final name = cli.prompt('Name?');
      await type(['ko', _ctrlC]);
      await expectLater(
        settle(name),
        throwsA(_cancelled('Name?', PromptCancelReason.interrupt)),
      );
      expect(terminal.screenLines, ['✗ Name?']);
      expect(terminal.interrupts, 0);
      expect(terminal.backend!.closed, isFalse);

      final next = cli.prompt('Again?');
      await type(['y', _enter]);
      expect(await settle(next), 'y');
      expect(terminal.screenLines, ['✗ Name?', '✔ Again? y']);
    });

    test('Ctrl+D at an empty field cancels it as the end of input', () async {
      final name = cli.prompt('Name?');
      await type(['a', _ctrlD]);
      expect(terminal.screenLines, ['? Name? a']);
      await type([_backspace, _ctrlD]);
      await expectLater(
        settle(name),
        throwsA(_cancelled('Name?', PromptCancelReason.endOfInput)),
      );
      expect(terminal.screenLines, ['✗ Name?']);
    });

    test('suggests under the field, Enter putting one in', () async {
      final lang = cli.prompt(
        'Language?',
        // in a future, as from a lookup
        suggest: (typed) => Future.value([
          for (final l in ['dart', 'dash', 'go'])
            if (l.startsWith(typed)) l,
        ]),
      );
      await type(['d']);
      final shown = terminal.screenLines;
      expect(shown.first, '? Language? d');
      expect(shown[1].trim(), '▎dart');
      expect(shown[2].trim(), 'dash');
      // under the field, from its column
      expect(shown[1].indexOf('dart'), greaterThanOrEqualTo(12));

      await type([_down, _enter]);
      expect(terminal.screenLines, ['? Language? dash']);
      terminal.type(_enter);
      expect(await settle(lang), 'dash');
      expect(terminal.screenLines, ['✔ Language? dash']);
    });

    test('Escape hides the suggestions and their rows', () async {
      final lang = cli.prompt('Language?', suggest: (typed) => ['dart']);
      await type(['d']);
      expect(terminal.screenLines, hasLength(2));
      await escape();
      expect(terminal.screenLines, ['? Language? d']);
      await type(['a']);
      expect(terminal.screenLines, hasLength(2));
      await escape();
      expect(terminal.screenLines, ['? Language? da']);
      terminal.type(_enter);
      expect(await settle(lang), 'da');
    });

    test('lines logged while it is asked land above it', () async {
      final name = cli.prompt('Name?');
      await type([]);
      cli.info('a log line');
      await frame();
      expect(terminal.screenLines, ['a log line', '? Name?']);
      terminal.type(_enter);
      await settle(name);
      expect(terminal.screenLines, ['a log line', '✔ Name?']);
    });

    test('one asked while another is waits for it', () async {
      final first = cli.prompt('First?');
      final second = cli.prompt('Second?');
      await type([]);
      expect(terminal.screenLines, ['? First?']);
      await type(['1', _enter]);
      expect(await settle(first), '1');
      await type(['2', _enter]);
      expect(await settle(second), '2');
      expect(terminal.screenLines, ['✔ First? 1', '✔ Second? 2']);
    });

    test('after the session ended, throws as at the end of input', () async {
      final session = await settle(cli.session());
      session.mount(const Text('waiting'));
      await frame();
      terminal.type(_ctrlC);
      await settle(session.done);
      expect(terminal.interrupts, 1);
      await expectLater(
        settle(cli.prompt('Name?')),
        throwsA(_cancelled('Name?', PromptCancelReason.endOfInput)),
      );
    });
  });

  group('in the interactive mode, promptAny', () {
    test('splits the field on the separator', () async {
      final tags = cli.promptAny('Tags?', defaultValues: ['a', 'b']);
      await type([]);
      expect(terminal.screenLines, ['? Tags? (a, b)']);
      await type(['x,, y ', _enter]);
      expect(await settle(tags), ['x', 'y']);
      expect(terminal.screenLines, ['✔ Tags? x, y']);
    });

    test('answers its defaults at an empty field', () async {
      final tags = cli.promptAny('Tags?', defaultValues: ['a', 'b']);
      await type([_enter]);
      expect(await settle(tags), ['a', 'b']);
    });
  });

  group('in the interactive mode, confirm', () {
    test('y and n answer, either case', () async {
      final a = cli.confirm('A?');
      await type(['Y']);
      expect(await settle(a), isTrue);
      final b = cli.confirm('B?', defaultValue: true);
      await type(['n']);
      expect(await settle(b), isFalse);
      expect(terminal.screenLines, ['✔ A? yes', '✔ B? no']);
    });

    test('Enter answers its default, Right and Left moving it', () async {
      final a = cli.confirm('Proceed?', defaultValue: true);
      await type([]);
      expect(terminal.screenLines, ['? Proceed?  Yes   No']);
      await type([_enter]);
      expect(await settle(a), isTrue);
      final b = cli.confirm('Overwrite?', defaultValue: true);
      await type([_right, _enter]);
      expect(await settle(b), isFalse);
    });

    test(
      'without a default, Enter answers nothing until one is chosen',
      () async {
        final ok = cli.confirm('Delete?');
        var answered = false;
        unawaited(ok.then((_) => answered = true));
        await type([_enter, _enter]);
        expect(answered, isFalse);
        expect(terminal.screenLines, ['? Delete?  Yes   No']);
        await type([_right, _enter]);
        expect(await settle(ok), isFalse);
        expect(terminal.screenLines, ['✔ Delete? no']);
      },
    );

    test('Ctrl+C and Ctrl+D cancel it', () async {
      final a = cli.confirm('A?');
      await type([_ctrlC]);
      await expectLater(
        settle(a),
        throwsA(_cancelled('A?', PromptCancelReason.interrupt)),
      );
      final b = cli.confirm('B?', defaultValue: true);
      await type([_ctrlD]);
      await expectLater(
        settle(b),
        throwsA(_cancelled('B?', PromptCancelReason.endOfInput)),
      );
      expect(terminal.screenLines, ['✗ A?', '✗ B?']);
    });
  });

  group('in the interactive mode, chooseOne', () {
    test('picks with Up, Down and Enter', () async {
      final env = cli.chooseOne(
        'Target environment?',
        choices: ['dev', 'stage', 'prod'],
      );
      await type([]);
      expect(terminal.screenLines, [
        '? Target environment?',
        '▎dev',
        ' stage',
        ' prod',
      ]);
      await type([_down, _down, _up, _down, _enter]);
      expect(await settle(env), 'prod');
      expect(terminal.screenLines, ['✔ Target environment? prod']);
    });

    test('starts on its default, shown as display makes it', () async {
      final port = cli.chooseOne(
        'Port?',
        choices: [80, 443, 8080],
        defaultValue: 443,
        display: (p) => ':$p',
      );
      await type([]);
      expect(terminal.screenLines, ['? Port?', ' :80', '▎:443', ' :8080']);
      terminal.type(_enter);
      expect(await settle(port), 443);
      expect(terminal.screenLines, ['✔ Port? :443']);
    });

    test('shows seven at once, scrolled to the cursor', () async {
      final items = [for (var i = 1; i <= 12; i++) 'item$i'];
      final item = cli.chooseOne(
        'Item?',
        choices: items,
        defaultValue: 'item10',
        filter: false,
      );
      await type([]);
      expect(terminal.screenLines, [
        '? Item?',
        ' item4',
        ' item5',
        ' item6',
        ' item7',
        ' item8',
        ' item9',
        '▎item10',
      ]);
      await type([_down, _down]);
      expect(terminal.screenLines.last, '▎item12');
      await type(['\x1B[H']);
      expect(terminal.screenLines.skip(1).first, '▎item1');
      terminal.type(_enter);
      expect(await settle(item), 'item1');
    });

    test('filters a list of more than seven by what is typed', () async {
      final items = [for (var i = 1; i <= 12; i++) 'item$i'];
      final item = cli.chooseOne('Item?', choices: items);
      await type([]);
      expect(terminal.screenLines.first, '? Item? (type to filter)');
      await type(['1', '1']);
      expect(terminal.screenLines, ['? Item? 11', '▎item11']);
      await type(['z']);
      expect(terminal.screenLines, ['? Item? 11z', '  no match']);
      await type([_enter]);
      expect(terminal.screenLines, ['? Item? 11z', '  no match']);
      await type([_backspace, _backspace]);
      expect(terminal.screenLines, [
        '? Item? 1',
        '▎item1',
        ' item10',
        ' item11',
        ' item12',
      ]);
      await type([_down, _enter]);
      expect(await settle(item), 'item10');
      expect(terminal.screenLines, ['✔ Item? item10']);
    });

    test(
      'a short list is filtered when asked, a long one not when told',
      () async {
        final a = cli.chooseOne('A?', choices: ['dev', 'prod'], filter: true);
        await type(['p']);
        expect(terminal.screenLines, ['? A? p', '▎prod']);
        terminal.type(_enter);
        expect(await settle(a), 'prod');

        final b = cli.chooseOne(
          'B?',
          choices: [for (var i = 1; i <= 9; i++) '$i'],
          filter: false,
        );
        await type(['9']);
        // typed, 9 neither filters nor moves
        expect(terminal.screenLines.sublist(1, 3), ['? B?', '▎1']);
        terminal.type(_enter);
        expect(await settle(b), '1');
      },
    );

    test('Ctrl+C cancels it, Ctrl+D with nothing typed to filter', () async {
      final a = cli.chooseOne('A?', choices: ['x'], filter: true);
      await type(['x', _ctrlD]);
      expect(terminal.screenLines.first, '? A? x');
      await type([_ctrlC]);
      await expectLater(
        settle(a),
        throwsA(_cancelled('A?', PromptCancelReason.interrupt)),
      );
      final b = cli.chooseOne('B?', choices: ['x']);
      await type([_ctrlD]);
      await expectLater(
        settle(b),
        throwsA(_cancelled('B?', PromptCancelReason.endOfInput)),
      );
    });
  });

  group('in the interactive mode, chooseAny', () {
    test(
      'toggles with Space and answers in the order of the choices',
      () async {
        final features = cli.chooseAny(
          'Features?',
          choices: ['Linter', 'Docker', 'Tests'],
          defaultValues: ['Tests'],
        );
        await type([]);
        expect(terminal.screenLines, [
          '? Features? (space to toggle)',
          ' [ ] Linter',
          ' [ ] Docker',
          '▎[x] Tests',
        ]);
        await type([_up, _up, ' ', _down, ' ', _down, ' ', _enter]);
        expect(await settle(features), ['Linter', 'Docker']);
        expect(terminal.screenLines, ['✔ Features? Linter, Docker']);
      },
    );

    test('refuses fewer than min and more than max, saying why', () async {
      final features = cli.chooseAny(
        'F?',
        choices: ['a', 'b', 'c'],
        min: 1,
        max: 2,
      );
      await type([_enter]);
      expect(terminal.screenLines.last, '✗ choose at least 1');
      await type([' ']);
      expect(terminal.screenLines.last, ' [ ] c');
      await type([_down, ' ', _down, ' ', _enter]);
      expect(terminal.screenLines.last, '✗ choose at most 2');
      await type([' ', _enter]);
      expect(await settle(features), ['a', 'b']);
    });

    test('commits none for nothing chosen', () async {
      final features = cli.chooseAny('F?', choices: ['a']);
      await type([_enter]);
      expect(await settle(features), isEmpty);
      expect(terminal.screenLines, ['✔ F? none']);
    });

    test('filters by what is typed but Space, which toggles', () async {
      final features = cli.chooseAny(
        'F?',
        choices: ['Linter', 'Docker', 'Tests'],
        filter: true,
      );
      await type(['d', ' ', _backspace, _enter]);
      expect(await settle(features), ['Docker']);
    });
  });
}
