// The kitty keyboard protocol's flags on a Terminal over an in-memory
// link: asked whether the terminal has the protocol, the flags the app
// asks for pushed with disambiguation as the modes are entered, on the
// screen the app draws on, and popped there as they are left, by close,
// by suspend (pushed again by resume) and by what the link is told puts
// the terminal back; repeats and releases come as a key's kind.
import 'package:test/test.dart';
import 'package:twk_core/src/terminal/terminal.dart' show openOwnOrShell;
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'fake_link.dart';
import 'on_clock.dart';

/// What the terminal answers to the probe: synchronized output, the kitty
/// keyboard protocol (no flags on), then DA1.
const _answers = '\x1b[?2026;2\$y\x1b[?0u\x1b[?62;22c';

/// The same from a terminal without the kitty keyboard protocol.
const _noKitty = '\x1b[?2026;2\$y\x1b[?62;22c';

/// A push of kitty keyboard flags (and not XTVERSION's `CSI > 0 q`).
final _push = RegExp(r'\x1b\[>\d*u');
const _pop = '\x1b[<u';

TerminalOptions _options({
  bool kittyKeyboard = true,
  int flags = KittyKeyboardFlags.disambiguate,
  bool alternateScreen = true,
}) => TerminalOptions(
  kittyKeyboard: kittyKeyboard,
  kittyKeyboardFlags: flags,
  alternateScreen: alternateScreen,
  probeTimeout: const Duration(seconds: 5),
);

int _count(String text, Pattern of) => of.allMatches(text).length;

void main() {
  test('by default disambiguation alone is pushed, on the alternate screen, '
      'and popped there as the terminal closes', () async {
    final link = FakeLink()..type(_answers);
    final term = await Terminal.overLink(link, _options());
    expect(term.info.kittyKeyboard, isTrue);
    expect(term.info.kittyKeyboardFlags, KittyKeyboardFlags.disambiguate);
    expect(const TerminalOptions().kittyKeyboardFlags, 1);
    final opened = link.text;
    expect(opened, contains('\x1b[?u'));
    expect(_count(opened, _push), 1);
    expect(
      opened.indexOf('\x1b[>1u'),
      greaterThan(opened.indexOf('\x1b[?1049h')),
    );
    expect(link.restoring, contains(_pop));

    await term.close();
    final exit = link.text.substring(opened.length);
    expect(_count(exit, _pop), 1);
    expect(exit.indexOf(_pop), lessThan(exit.indexOf('\x1b[?1049l')));
  });

  test('the flags asked for are pushed with disambiguation; repeats and '
      'releases come as the key kind', () async {
    for (final (flags, pushed) in [
      (KittyKeyboardFlags.eventTypes, 3),
      (KittyKeyboardFlags.disambiguate | KittyKeyboardFlags.eventTypes, 3),
      (KittyKeyboardFlags.allKeysAsEscapes, 9),
      (
        KittyKeyboardFlags.eventTypes |
            KittyKeyboardFlags.alternateKeys |
            KittyKeyboardFlags.allKeysAsEscapes |
            KittyKeyboardFlags.associatedText,
        31,
      ),
    ]) {
      final link = FakeLink()..type(_answers);
      final term = await Terminal.overLink(link, _options(flags: flags));
      expect(term.info.kittyKeyboardFlags, pushed, reason: '$flags');
      expect(link.text, contains('\x1b[>${pushed}u'), reason: '$flags');
      expect(_count(link.text, _push), 1, reason: '$flags');
      await term.close();
      expect(_count(link.text, _pop), 1, reason: '$flags');
    }

    // on a clock of the test's: what the link is given comes in as it
    // flushes
    final clock = FakeClock();
    final link = FakeLink()..type(_answers);
    final term = await clock.open(
      link,
      _options(flags: KittyKeyboardFlags.eventTypes),
    );
    final events = <InputEvent>[];
    term.events.listen(events.add);
    link.type('a\x1b[97;1:3u\x1b[1;1:2A\x1b[1;1:3A');
    await clock.flushMicrotasks();
    expect(events, const [
      KeyEvent(KeyCode.char, char: 'a'),
      KeyEvent(KeyCode.char, char: 'a', kind: KeyKind.release),
      KeyEvent(KeyCode.up, kind: KeyKind.repeat),
      KeyEvent(KeyCode.up, kind: KeyKind.release),
    ]);
    await clock.runUntil(term.close);
  });

  test('in the inline mode they are pushed and popped on the normal '
      'screen', () async {
    final link = FakeLink()..type(_answers);
    final term = await Terminal.overLink(
      link,
      _options(flags: KittyKeyboardFlags.eventTypes, alternateScreen: false),
    );
    expect(term.info.kittyKeyboardFlags, 3);
    await term.close();
    // the probe's queries on the alternate screen, the flags after it
    final probed = link.text.indexOf('\x1b[?1049l');
    expect(link.text.substring(probed), isNot(contains('\x1b[?1049h')));
    expect(link.text.indexOf('>3u'), greaterThan(probed));
    expect(_count(link.text, '\x1b[>3u'), 1);
    expect(_count(link.text, _pop), 1);
    expect(link.text.indexOf(_pop), greaterThan(link.text.indexOf('>3u')));
  });

  test('without kittyKeyboard nothing is asked, pushed or popped, and no '
      'flags are on, whatever is asked for', () async {
    final link = FakeLink()..type(_noKitty);
    final term = await Terminal.overLink(
      link,
      _options(kittyKeyboard: false, flags: KittyKeyboardFlags.eventTypes),
    );
    expect(term.info.kittyKeyboard, isFalse);
    expect(term.info.kittyKeyboardFlags, 0);
    await term.close();
    expect(link.text, isNot(contains('\x1b[?u')));
    expect(link.text, isNot(contains(_push)));
    expect(link.text, isNot(contains(_pop)));
  });

  test('a terminal without the protocol has no flags on; they are pushed '
      'and popped all the same, which it ignores', () async {
    final link = FakeLink()..type(_noKitty);
    final term = await Terminal.overLink(
      link,
      _options(flags: KittyKeyboardFlags.eventTypes),
    );
    expect(term.info.kittyKeyboard, isFalse);
    expect(term.info.kittyKeyboardFlags, 0);
    await term.close();
    expect(_count(link.text, '\x1b[>3u'), 1);
    expect(_count(link.text, _pop), 1);
  });

  test('a TerminalInfo made by hand has disambiguation on with the '
      'protocol, none without', () {
    TerminalInfo info({required bool kitty, int? flags}) => TerminalInfo(
      caps: const TerminalCaps(),
      textMode: TextMode.graphemes,
      ambiguousWidth: 1,
      colorMode: ColorMode.none,
      foregroundRgb: null,
      backgroundRgb: null,
      inBandResize: false,
      graphemeMode: false,
      kittyKeyboard: kitty,
      answeredQueries: true,
      kittyKeyboardFlags: flags,
    );
    expect(info(kitty: true).kittyKeyboardFlags, 1);
    expect(info(kitty: true, flags: 3).kittyKeyboardFlags, 3);
    expect(info(kitty: false).kittyKeyboardFlags, 0);
    expect(info(kitty: false, flags: 3).kittyKeyboardFlags, 0);
  });

  for (final alternateScreen in [true, false]) {
    final mode = alternateScreen ? 'fullscreen' : 'inline';
    test('$mode: suspend pops the flags and resume pushes them again; what '
        'the link is told puts the terminal back pops them while they are '
        'pushed', () async {
      // on a clock of the test's: what the link is given comes in as it
      // flushes
      final clock = FakeClock();
      // inline, the cursor is asked where it is in a round of its own
      final link = FakeLink()
        ..type(alternateScreen ? _answers : '\x1b[1;1R\x1b[?62c$_answers');
      final term = await clock.runUntil(
        () => openOwnOrShell(
          link,
          _options(
            flags: KittyKeyboardFlags.eventTypes,
            alternateScreen: alternateScreen,
          ),
        ),
      );
      addTearDown(() => clock.runUntil(term.close));
      var at = 0;
      String since() {
        final s = link.text.substring(at);
        at = link.text.length;
        return s;
      }

      expect(_count(since(), '\x1b[>3u'), 1);
      expect(link.restoring, contains(_pop));

      await clock.runUntil(term.suspend);
      final suspended = since();
      expect(_count(suspended, _pop), 1);
      expect(suspended, isNot(contains(_push)));
      expect(link.restoring, isEmpty);

      // where the cursor is, which resume asks (read once input resumes)
      link.type('\x1b[1;1R');
      await clock.runUntil(term.resume);
      final resumed = since();
      expect(_count(resumed, '\x1b[>3u'), 1);
      expect(resumed, isNot(contains(_pop)));
      expect(link.restoring, contains(_pop));
      if (alternateScreen) {
        expect(
          resumed.indexOf('\x1b[>3u'),
          greaterThan(resumed.indexOf('\x1b[?1049h')),
        );
      }

      final events = <InputEvent>[];
      term.events.listen(events.add);
      link.type('\x1b[97;1:3u');
      await clock.flushMicrotasks();
      expect(events, const [
        KeyEvent(KeyCode.char, char: 'a', kind: KeyKind.release),
      ]);

      await clock.runUntil(term.close);
      expect(_count(since(), _pop), 1);
      expect(_count(link.text, _push), _count(link.text, _pop));
    });
  }
}
