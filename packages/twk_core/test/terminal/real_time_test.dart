// The I/O adapters keep to real time: the timers of a terminal's close, a
// log server's token wait and a trace's drain are made where the adapter
// was made, or in the root zone, never in the zone of whoever calls it.
// A driver of an app (TWK_DRIVEN) gives the app's code a zone whose timers
// are a clock it moves: an adapter that made its timers there would wait
// for a clock that moves only when the driver says, and a closing terminal
// that stops reading would never end.
//
// A zone that counts the timers made in it stands for that zone here.
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_core/terminal.dart' show LogLevel, LogRecord, LogSink;
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show waitFor;

import 'fake_link.dart';

/// What the terminal answers to the probe: synchronized output, the kitty
/// keyboard protocol, then DA1.
const _answers = '\x1b[?2026;2\$y\x1b[?0u\x1b[?62;22c';

/// A zone, child of this one, that notes each timer made in it, one-shot
/// or periodic, and makes it as the zone it came from does.
(Zone, List<Duration>) _counting() {
  final made = <Duration>[];
  final zone = Zone.current.fork(
    specification: ZoneSpecification(
      createTimer: (self, parent, zone, after, callback) {
        made.add(after);
        return parent.createTimer(zone, after, callback);
      },
      createPeriodicTimer: (self, parent, zone, every, callback) {
        made.add(every);
        return parent.createPeriodicTimer(zone, every, callback);
      },
    ),
  );
  return (zone, made);
}

void main() {
  test("close's flush guards are made where the terminal was, not in the "
      'zone that closes it', () async {
    final link = FakeLink()..type(_answers);
    final term = await Terminal.overLink(
      link,
      const TerminalOptions(probeTimeout: Duration(seconds: 5)),
    );
    final stalled = Completer<void>();
    link
      ..taken = 0
      ..stalled = stalled.future;
    final (zone, made) = _counting();
    final closed = zone.run(term.close);
    await pumpEventQueue();
    expect(link.raw, isTrue, reason: 'close is waiting for the flush');
    expect(made, isEmpty);
    stalled.complete();
    await closed;
    expect(link.raw, isFalse);
    expect(made, isEmpty);
  });

  test("a blind link's close guard is the terminal's too", () async {
    final link = FakeLink()..type(_answers);
    final term = await Terminal.overLink(
      link,
      const TerminalOptions(probeTimeout: Duration(seconds: 5)),
    );
    final stalled = Completer<void>();
    link.stalled = stalled.future;
    final (zone, made) = _counting();
    final closed = zone.run(term.close);
    await pumpEventQueue();
    expect(made, isEmpty);
    stalled.complete();
    await closed;
  });

  test(
    "a log server's token wait is real time, whichever zone serves",
    () async {
      final dir = Directory.systemTemp.createTempSync('twk_real_time');
      addTearDown(() => dir.deleteSync(recursive: true));
      final sink = LogSink()
        ..add(LogRecord(DateTime(2026), LogLevel.info, 'x'));
      final (zone, made) = _counting();
      final address = await zone.run(() => sink.serve(directory: dir.path));
      addTearDown(sink.close);
      final client = await address.connect();
      final got = <int>[];
      final done = client.listen(got.addAll).asFuture<void>();
      // a client that sends no line in 256 bytes is cut off: the server took
      // it in, and started the wait for its token
      client.add(List.filled(300, 0x61));
      await waitFor(done, 'the server to cut the client off');
      client.destroy();
      expect(made, isEmpty);
    },
  );

  test("a trace's drain is real time, whichever zone writes", () async {
    final dir = Directory.systemTemp.createTempSync('twk_real_time');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (zone, made) = _counting();
    final writer = zone.run(
      () => TraceWriter.open(
        '${dir.path}/out.trace',
        TraceDirection.output,
        80,
        24,
      )..add([0x61]),
    );
    await writer.close();
    expect(made, isEmpty);
  });
}
