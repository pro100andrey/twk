// The terminal's cursor color: the probe asks for it (OSC 12) beside the
// default colors, keeps what is answered, and asks again after the color
// scheme changed where it was answered.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'fake_link.dart';
import 'on_clock.dart';

const _options = TerminalOptions(probeTimeout: Duration(seconds: 5));

/// DA1, the probe's last answer.
const _da1 = '\x1b[?62;22c';

late FakeClock _clock;

Future<(Terminal, FakeLink)> _open(String answers) async {
  final link = FakeLink()..type(answers);
  return (await _clock.open(link, _options), link);
}

void main() {
  setUp(() => _clock = FakeClock());

  test('the probe asks for the cursor color after the background, in the '
      'same write, before DA1', () async {
    final (_, link) = await _open(_da1);
    final text = link.text;
    expect(
      text,
      contains('\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]12;?\x1b\\\x1b]4;0;?'),
    );
    expect(
      text.indexOf('\x1b]12;?'),
      lessThan(text.indexOf('\x1b[c')),
    );
  });

  test('the cursor color the terminal answers is kept', () async {
    final (term, _) = await _open(
      '\x1b]10;rgb:fcfc/fcfc/fcfc\x1b\\'
      '\x1b]12;rgb:ff/88/00\x1b\\'
      '$_da1',
    );
    expect(term.info.cursorRgb, 0xff8800);
    expect(term.info.foregroundRgb, 0xfcfcfc);
  });

  test('a terminal that answers OSC 10 but not 12 (Konsole) has no cursor '
      'color, and one that answers neither has none either', () async {
    final (konsole, _) = await _open('\x1b]10;rgb:fcfc/fcfc/fcfc\x1b\\$_da1');
    expect(konsole.info.cursorRgb, isNull);
    expect(konsole.info.foregroundRgb, 0xfcfcfc);
    final (silent, _) = await _open(_da1);
    expect(silent.info.cursorRgb, isNull);
  });

  test('after the color scheme changed the cursor color is asked for again '
      'where the terminal told it, and comes as a ColorReport', () async {
    final (term, link) = await _open(
      '\x1b[?2031;2\$y'
      '\x1b]10;rgb:d0/d0/d0\x1b\\'
      '\x1b]11;rgb:10/12/18\x1b\\'
      '\x1b]12;rgb:ff/88/00\x1b\\'
      '$_da1',
    );
    final reports = <ColorReport>[];
    final sub = term.events.listen((e) {
      if (e is ColorReport) {
        reports.add(e);
      }
    });
    addTearDown(sub.cancel);
    final before = link.text.length;
    link.type('\x1b[?997;2n');
    await _clock.flushMicrotasks();
    expect(
      link.text.substring(before),
      contains('\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]12;?\x1b\\'),
    );
    link.type('\x1b]12;rgb:11/22/33\x1b\\');
    await _clock.flushMicrotasks();
    expect([for (final r in reports) (r.which, r.rgb)], [(12, 0x112233)]);
  });

  test('a cursor color not told is not asked for again', () async {
    final (_, link) = await _open(
      '\x1b[?2031;2\$y\x1b]11;rgb:10/12/18\x1b\\$_da1',
    );
    final before = link.text.length;
    link.type('\x1b[?997;2n');
    await _clock.flushMicrotasks();
    expect(link.text.substring(before), isNot(contains('\x1b]12;?')));
  });

  test('a HeadlessTerminal tells the cursor color it is given', () {
    expect(HeadlessTerminal(cursorRgb: 0x123456).info.cursorRgb, 0x123456);
    expect(HeadlessTerminal().info.cursorRgb, isNull);
  });
}
