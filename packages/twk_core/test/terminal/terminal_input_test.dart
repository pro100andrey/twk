// A Terminal over a link in memory, on what the probe's answers turn on
// (in-band resize reports, grapheme clusters, the ambiguous width, the
// cursor's column inline), on input that takes a while to complete (a
// lone ESC, a sequence cut across reads, a paste whose end got lost), on
// keys typed during the probe and a link that fails during it, and on
// desktop notifications.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'fake_link.dart';
import 'on_clock.dart';

/// DA1, the probe's last answer.
const _da1 = '\x1b[?62;22c';

/// The clock the terminals run on: their escape and paste timeouts fire
/// as the test moves it on, what their link is given comes in as it
/// flushes.
late FakeClock clock;

/// Opens a terminal on [clock] over a new [FakeLink] that answers the
/// probe with [answers] and DA1, in [environment]; closed when the test
/// ends.
Future<(Terminal, FakeLink)> answered(
  String answers, {
  TerminalOptions options = const TerminalOptions(),
  Map<String, String> environment = const {'TERM': 'xterm-256color'},
}) async {
  final link = FakeLink(environment: environment)..type('$answers$_da1');
  return (await clock.open(link, options), link);
}

/// The events [term] delivers, as they come.
List<InputEvent> eventsOf(Terminal term) {
  final events = <InputEvent>[];
  term.events.listen(events.add);
  return events;
}

void main() {
  setUp(() => clock = FakeClock());

  test('in-band resize reports, where the terminal has them, are turned '
      'on and give the size; off again on close', () async {
    final (term, link) = await answered('\x1b[?2048;2\$y');
    expect(term.info.inBandResize, isTrue);
    expect(link.text, contains('\x1b[?2048h'));
    final events = eventsOf(term);
    link.type('\x1b[48;30;100;600;1000t');
    await clock.flushMicrotasks();
    expect(events, [const ResizeEvent(100, 30)]);
    expect((term.width, term.height), (100, 30));
    final opening = link.text.length;
    await clock.runUntil(term.close);
    expect(link.text.substring(opening), contains('\x1b[?2048l'));
  });

  test('grapheme clusters, where the terminal has mode 2027, are turned '
      'on and text is measured by them; off again on close', () async {
    final (term, link) = await answered('\x1b[?2027;2\$y');
    expect(term.info.graphemeMode, isTrue);
    expect(term.info.textMode, TextMode.graphemes);
    expect(link.text, contains('\x1b[?2027h'));
    final opening = link.text.length;
    await clock.runUntil(term.close);
    expect(link.text.substring(opening), contains('\x1b[?2027l'));
  });

  test('the ambiguous width is where the cursor went after U+2500 on the '
      'alternate screen', () async {
    final (wide, _) = await answered('\x1b[1;3R');
    expect(wide.info.ambiguousWidth, 2);
    final (narrow, _) = await answered('\x1b[1;2R');
    expect(narrow.info.ambiguousWidth, 1);
  });

  test("inline, the cursor's column is asked for the region to start "
      'on', () async {
    final (term, link) = await answered(
      '\x1b[7;5R',
      options: const TerminalOptions(alternateScreen: false),
    );
    expect(term.info.cursorColumn, 4);
    expect(term.info.ambiguousWidth, 1);
    expect(link.text, isNot(contains('\x1b[?1049h')));
  });

  test('keys typed while the probe waits come first, in order', () async {
    final link = FakeLink()..type('ab\x1b[?2026;2\$y$_da1');
    final term = await clock.open(link);
    final events = eventsOf(term);
    link.type('c');
    await clock.flushMicrotasks();
    expect(events, const [
      KeyEvent(KeyCode.char, char: 'a'),
      KeyEvent(KeyCode.char, char: 'b'),
      KeyEvent(KeyCode.char, char: 'c'),
    ]);
  });

  test('a link whose input fails during the probe: opening throws that, '
      'the link put back and closed', () async {
    final link = FakeLink()..fail(const SocketException('gone'));
    await expectLater(
      Terminal.overLink(link),
      throwsA(isA<SocketException>()),
    );
    expect(link.rawChanges, [true, false]);
    expect(link.closed, isTrue);
  });

  group('without the kitty keyboard protocol', () {
    const options = TerminalOptions(
      escapeTimeout: Duration(milliseconds: 20),
      pasteTimeout: Duration(milliseconds: 30),
    );

    test('a lone ESC is the Escape key once escapeTimeout passes', () async {
      final (term, link) = await answered('', options: options);
      final events = eventsOf(term);
      link.type('\x1b');
      await clock.elapse(const Duration(milliseconds: 19));
      expect(events, isEmpty);
      // not the 500 ms a sequence whose parameters came waits
      await clock.elapse(const Duration(milliseconds: 1));
      expect(events, const [KeyEvent(KeyCode.escape)]);
    });

    test('a sequence whose parameters came waits for the rest longer than '
        'a lone ESC', () async {
      final (term, link) = await answered('', options: options);
      final events = eventsOf(term);
      link.type('\x1b[1;');
      await clock.elapse(const Duration(milliseconds: 150));
      expect(events, isEmpty);
      link.type('5A');
      await clock.flushMicrotasks();
      expect(events, const [KeyEvent(KeyCode.up, modifiers: Mod.ctrl)]);
    });

    test('a paste whose end marker got lost ends after pasteTimeout with '
        'what arrived', () async {
      final (term, link) = await answered('', options: options);
      final events = eventsOf(term);
      link.type('\x1b[200~pasted\r');
      await clock.elapse(const Duration(milliseconds: 29));
      expect(events, isEmpty);
      await clock.elapse(const Duration(milliseconds: 1));
      expect(events, const [PasteEvent('pasted\n')]);
      link.type('k');
      await clock.flushMicrotasks();
      expect(events, hasLength(2));
      expect(events.last, const KeyEvent(KeyCode.char, char: 'k'));
    });
  });

  group('notify', () {
    test("sends the terminal's notification, numbered for this "
        'process', () async {
      final (term, link) = await answered(
        '',
        environment: const {'TERM': 'xterm-kitty'},
      );
      expect(term.info.notifications, NotificationProtocol.osc99);
      final opened = link.text.length;
      term
        ..notify('Build', 'done')
        ..notify('Tests', '');
      expect(
        link.text.substring(opened),
        '\x1b]99;i=$pid.1:d=0;Build\x1b\\'
        '\x1b]99;i=$pid.1:p=body;done\x1b\\'
        '\x1b]99;i=$pid.2;Tests\x1b\\',
      );
    });

    test("rings Terminal.app's bell only while its window doesn't have the "
        'focus', () async {
      final (term, link) = await answered(
        '',
        environment: const {'TERM_PROGRAM': 'Apple_Terminal'},
      );
      expect(term.info.notifications, NotificationProtocol.bell);
      final events = eventsOf(term);
      final opened = link.text.length;
      term.notify('Build', 'done');
      expect(link.text.length, opened, reason: 'focused, as with no report');
      link.type('\x1b[O');
      await clock.flushMicrotasks();
      expect(events, const [FocusEvent(false)]);
      term.notify('Build', 'done');
      expect(link.text.substring(opened), '\x07');
      link.type('\x1b[I');
      await clock.flushMicrotasks();
      term.notify('Build', 'done');
      expect(link.text.substring(opened), '\x07');
    });

    test('sends nothing where no notification is known to show, nor once '
        'closed', () async {
      final (term, link) = await answered('');
      expect(term.info.notifications, NotificationProtocol.none);
      final opened = link.text.length;
      term.notify('Build', 'done');
      expect(link.text.length, opened);

      final (kitty, kittyLink) = await answered(
        '',
        environment: const {'TERM': 'xterm-kitty'},
      );
      await clock.runUntil(kitty.close);
      final closed = kittyLink.text.length;
      kitty.notify('Build', 'done');
      expect(kittyLink.text.length, closed);
    });
  });

  test('a TerminalException prints what went wrong', () {
    expect(
      '${const TerminalException('not a terminal')}',
      'TerminalException: not a terminal',
    );
  });
}
