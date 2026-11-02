// A LogController's lines from a program's output: read from a stream as
// it comes, a line once it ends, in the colors of its escape sequences, a
// progress bar's last state, the line not ended added when the stream is
// done; lines of spans, searched across them.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// The rows of the screen with text.
List<String> shown(TwkTester t) => [
  for (final line in t.lines)
    if (line.isNotEmpty) line,
];

/// A view of [c], its lines bare.
Widget plain(LogController c) => Theme.terminal(
  child: LogView(
    controller: c,
    showTime: false,
    showLevel: false,
    autofocus: true,
    scrollbar: ScrollbarVisibility.never,
  ),
);

void main() {
  testTwk('the lines of a stream once each ends, in their colors; a '
      'piece may end in a sequence or a line; a carriage return writes the '
      'line over; the last line once the stream is done', (t) async {
    final c = LogController();
    final output = StreamController<String>();
    addTearDown(output.close);
    final subscription = c.addOutput(output.stream);
    addTearDown(subscription.cancel);
    await t.pumpWidget(plain(c), size: (20, 5));
    output
      ..add('\x1B[3')
      ..add('1mFAIL\x1B[0m one\nbuil')
      ..add('ding 10%\rbuilding 100%\n')
      ..add('\x1B[2Jdone');
    await t.pump();
    expect(c.length, 2);
    expect(shown(t), ['FAIL one', 'building 100%']);
    expect(t.cell(0, 0), hasFg(Color.red));
    expect(t.cell(5, 0), isNot(hasFg(Color.red)));
    expect(c[0].text, 'FAIL one');
    await output.close();
    await t.pump();
    expect(shown(t), ['FAIL one', 'building 100%', 'done']);
  });

  testTwk('a line of spans keeps their colors over its level; the query '
      'found across two of them marks both', (t) async {
    final c = LogController()
      ..addSpans(const [
        Span('ab', Style(fg: Color.red)),
        Span('cd', Style(fg: Color.green)),
      ]);
    await t.pumpWidget(plain(c), size: (20, 3));
    expect(shown(t), ['abcd']);
    c.query = 'bc';
    await t.pump();
    // the matches in reverse video, each cell in its span's color
    for (final (x, fg, marked) in [
      (0, Color.red, false),
      (1, Color.red, true),
      (2, Color.green, true),
      (3, Color.green, false),
    ]) {
      expect(t.cell(x, 0), hasFg(fg));
      expect(t.cell(x, 0).attrs & Attr.reverse != 0, marked, reason: '$x');
    }
  });

  test('done completes when the stream ends, with its last unended line '
      'added', () async {
    final c = LogController();
    addTearDown(c.dispose);
    final output = StreamController<String>();
    addTearDown(output.close);
    final source = c.addOutput(output.stream);
    var done = false;
    unawaited(source.done.then((_) => done = true));
    output.add('one\ntail');
    await pumpEventQueue();
    expect(done, isFalse);
    expect(c.length, 1);
    await output.close();
    await source.done;
    expect(c.length, 2);
    expect(c[1].text, 'tail');
  });

  test('cancel stops the lines, frees the stream and completes done; the '
      'unended line is not added', () async {
    final c = LogController();
    addTearDown(c.dispose);
    final output = StreamController<String>();
    addTearDown(output.close);
    final source = c.addOutput(output.stream);
    output.add('a\nb');
    await pumpEventQueue();
    await source.cancel();
    expect(output.hasListener, isFalse);
    await source.done;
    output.add('c\n');
    await pumpEventQueue();
    expect(c.length, 1);
    await source.cancel();
  });

  test(
    'an error of the stream ends the source: done completes with it',
    () async {
      final c = LogController();
      addTearDown(c.dispose);
      final output = StreamController<String>();
      addTearDown(output.close);
      addTearDown(output.close);
      final source = c.addOutput(output.stream);
      output.addError(StateError('boom'));
      await expectLater(source.done, throwsStateError);
      expect(output.hasListener, isFalse);
    },
  );

  test('a tab goes to the multiple of the tabWidth', () async {
    final c = LogController();
    addTearDown(c.dispose);
    await c.addOutput(Stream.value('a\tb\n'), tabWidth: 4).done;
    expect(c[0].text, 'a   b');
  });
}
