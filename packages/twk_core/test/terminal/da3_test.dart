// The probe asks the tertiary device attributes (DA3, `CSI = c`) beside DA2,
// before DA1 that ends the round; Terminology, which answers `~~TY`, is
// shown 256 colors where its TERM does not say so, and so is a TERM of
// `terminology` or `fbterm`; the Linux console is not asked.
import 'package:test/test.dart';
import 'package:twk_core/src/terminal/terminal.dart';
import 'package:twk_core/terminal.dart';

import 'fake_link.dart';

Future<(ColorMode, String)> open(
  Map<String, String> env,
  String answers,
) async {
  final link = FakeLink(environment: env)..type('$answers\x1b[?62;22c');
  final term = await openOwnOrShell(
    link,
    const TerminalOptions(probeTimeout: Duration(seconds: 5)),
  );
  await term.close();
  return (term.info.colorMode, link.text);
}

const _terminologyReply = '\x1bP!|7E7E5459\x1b\\';

void main() {
  test('DA3 is asked after DA2 and before DA1', () async {
    final (_, text) = await open(const {'TERM': 'xterm'}, '');
    expect(text, contains('\x1b[>c\x1b[=c'));
    expect(text.indexOf('\x1b[=c'), lessThan(text.lastIndexOf('\x1b[c')));
  });

  test('the Linux console is not asked it', () async {
    final (_, text) = await open(const {'TERM': 'linux'}, '');
    expect(text, isNot(contains('\x1b[=c')));
  });

  test('Terminology that answers ~~TY by DA3 is shown 256 colors', () async {
    final (mode, _) = await open(const {'TERM': 'xterm'}, _terminologyReply);
    expect(mode, ColorMode.ansi256);
  });

  test('a BEL ends the answer as well as ST', () async {
    final (mode, _) = await open(const {
      'TERM': 'xterm',
    }, '\x1bP!|7E7E5459\x07');
    expect(mode, ColorMode.ansi256);
  });

  test("another unit id, VTE's or foot's, changes no color", () async {
    expect(
      (await open(const {'TERM': 'xterm'}, '\x1bP!|7E565445\x1b\\')).$1,
      ColorMode.ansi16,
    );
    expect(
      (await open(const {'TERM': 'xterm'}, '\x1bP!|464F4F54\x1b\\')).$1,
      ColorMode.ansi16,
    );
    // not text, odd in digits
    expect(
      (await open(const {'TERM': 'xterm'}, '\x1bP!|0000\x1b\\')).$1,
      ColorMode.ansi16,
    );
    expect(
      (await open(const {'TERM': 'xterm'}, '\x1bP!|7E7E545\x1b\\')).$1,
      ColorMode.ansi16,
    );
  });

  test(
    'a multiplexer answering DA3 itself is not taken for Terminology',
    () async {
      final (mode, _) = await open(
        const {'TERM': 'screen', 'TMUX': '/tmp/tmux-1/default,1,0'},
        _terminologyReply,
      );
      expect(mode, ColorMode.ansi16);
    },
  );

  test('the reply is not left as input', () async {
    final link = FakeLink(environment: const {'TERM': 'xterm'})
      ..type('$_terminologyReply\x1b[?62;22c');
    final term = await openOwnOrShell(
      link,
      const TerminalOptions(probeTimeout: Duration(seconds: 5)),
    );
    final seen = <InputEvent>[];
    final sub = term.events.listen(seen.add);
    await pumpEventQueue();
    await sub.cancel();
    await term.close();
    expect(seen.whereType<UnknownSequence>(), isEmpty);
  });

  test('TERM terminology and fbterm give 256 colors', () {
    expect(colorModeFor(const {'TERM': 'terminology'}), ColorMode.ansi256);
    expect(colorModeFor(const {'TERM': 'fbterm'}), ColorMode.ansi256);
    expect(colorModeFor(const {'TERM': 'linux'}), ColorMode.ansi16);
  });
}
