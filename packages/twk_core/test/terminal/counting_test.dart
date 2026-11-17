// The counters of CountingBackend: what a Terminal and a HeadlessTerminal
// read and were given to write, which a driver of the app compares with
// what the app says it took in.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'fake_link.dart';
import 'on_clock.dart';

/// What the terminal answers to the probe: synchronized output, the kitty
/// keyboard protocol, then DA1.
const _answers = '\x1b[?2026;2\$y\x1b[?0u\x1b[?62;22c';

const _options = TerminalOptions(probeTimeout: Duration(milliseconds: 100));

void main() {
  late FakeClock clock;
  setUp(() => clock = FakeClock());

  group('Terminal', () {
    test('counts the probe: its answers as read, its queries as written, '
        'both at once and apart', () async {
      final link = FakeLink()..type(_answers);
      final term = await clock.open(link, _options);
      expect(term.bytesReadAtOpen, utf8.encode(_answers).length);
      expect(term.bytesRead, term.bytesReadAtOpen);
      // the probe wrote its queries, and the modes were written after it
      expect(term.bytesWritten, link.output.length);
      expect(term.bytesWritten, greaterThan(0));
    });

    test('counts what it reads once open, and calls onRead after each read '
        'with the events queued', () async {
      final link = FakeLink()..type(_answers);
      final term = await clock.open(link, _options);
      final events = <InputEvent>[];
      term.events.listen(events.add);
      final seen = <(int, int)>[];
      term.onRead = () => seen.add((term.bytesRead, events.length));
      final open = term.bytesRead;
      link.type('ab');
      await clock.flushMicrotasks();
      link.type('c');
      await clock.flushMicrotasks();
      expect(term.bytesRead, open + 3);
      expect(term.bytesReadAtOpen, open);
      // the read is counted when its events are queued: the stream delivers
      // them a microtask later
      expect(seen, [(open + 2, 0), (open + 3, 2)]);
      expect(events, hasLength(3));
    });

    test('counts a lone ESC as pending until it is resolved', () async {
      final link = FakeLink()..type(_answers);
      final term = await clock.open(link, _options);
      term.events.listen((_) {});
      expect(term.inputPending, isFalse);
      link.type('\x1b');
      await clock.flushMicrotasks();
      expect(term.inputPending, isTrue);
      await clock.elapse(const Duration(seconds: 1));
      expect(term.inputPending, isFalse);
    });

    test(
      'counts an answer it keeps to itself, and calls onRead for it',
      () async {
        // the probe is not answered: its late answers are dropped
        final link = FakeLink();
        final term = await clock.open(link, _options);
        final events = <InputEvent>[];
        term.events.listen(events.add);
        var reads = 0;
        term.onRead = () => reads++;
        link.type('\x1b[?62;22c');
        await clock.flushMicrotasks();
        expect(events, isEmpty);
        expect(term.bytesRead, 9);
        expect(reads, 1);
      },
    );

    test('counts what is written while a flush is pending when it is '
        'accepted, not when it reaches the link', () async {
      final link = FakeLink()..type(_answers);
      final term = await clock.open(link, _options);
      final before = term.bytesWritten;
      final held = Completer<void>();
      link.stalled = held.future;
      final flushing = term.flush();
      term
        ..write(Uint8List.fromList(List.filled(10, 0x41)))
        ..setTitle('t');
      expect(term.bytesWritten, greaterThan(before + 10));
      expect(link.output.length, before, reason: 'held back by the flush');
      held.complete();
      await flushing;
      await clock.flushMicrotasks();
      expect(term.bytesWritten, link.output.length);
    });
  });

  group('HeadlessTerminal', () {
    test('counts the input it is given, calls onRead after each read, and '
        'tells what the parser holds', () {
      final term = HeadlessTerminal();
      final seen = <int>[];
      term.onRead = () => seen.add(term.bytesRead);
      term
        ..type('ab')
        ..input([0x1b]);
      expect(term.bytesRead, 3);
      expect(term.bytesReadAtOpen, 0);
      expect(seen, [2, 3]);
      expect(term.inputPending, isTrue);
      term.timeOutInput();
      expect(term.inputPending, isFalse);
      expect(term.bytesRead, 3, reason: 'a timeout reads nothing');
    });

    test('does not count the input of a suspended terminal: it is read by '
        'the other program', () async {
      final term = HeadlessTerminal();
      await term.suspend();
      term.type('x');
      expect(term.bytesRead, 0);
    });

    test('counts every byte written, what it was cleared of too', () {
      final term = HeadlessTerminal()
        ..write(Uint8List.fromList([1, 2, 3]))
        ..setTitle('hi');
      final written = term.bytesWritten;
      expect(written, 3 + utf8.encode(titleSequence('hi')).length);
      term.frames.clear();
      expect(term.bytesWritten, written);
    });
  });
}
