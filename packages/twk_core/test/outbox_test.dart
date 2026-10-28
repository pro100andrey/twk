// The outbox against a sink that behaves like dart:io's stdout: writes and
// flushes during a pending flush are errors there, so none may reach it.
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/terminal/outbox.dart';

final class FakeSink {
  /// The lists handed over, as handed over (not copied), and their bytes
  /// at that moment.
  final received = <List<int>>[];
  final receivedBytes = <List<int>>[];
  var flushes = 0;
  Completer<void>? pending;
  Object? failNextFlush;

  void add(List<int> bytes) {
    if (pending != null) {
      throw StateError('StreamSink is bound to a stream');
    }
    received.add(bytes);
    receivedBytes.add(List<int>.of(bytes));
  }

  Future<void> flush() {
    if (pending != null) {
      throw StateError('StreamSink is bound to a stream');
    }
    flushes++;
    final error = failNextFlush;
    failNextFlush = null;
    final c = pending = Completer<void>();
    if (error != null) {
      c.completeError(error);
    }
    return c.future.whenComplete(() => pending = null);
  }

  /// The pending flush reached the OS.
  void complete() => pending!.complete();
}

Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

String text(List<int> b) => String.fromCharCodes(b);

void main() {
  late FakeSink sink;
  late Outbox out;
  setUp(() {
    sink = FakeSink();
    out = Outbox(sink.add, sink.flush);
  });

  test('writes during a pending flush wait for it, in order', () async {
    out.add(bytes('a'));
    final f1 = out.flush();
    out
      ..add(bytes('b'))
      ..frame(bytes('c'))
      ..add(bytes('d'));
    expect(sink.receivedBytes.map(text), ['a'], reason: 'not yet');
    final f2 = out.flush();
    expect(sink.flushes, 1, reason: 'one flush at a time');
    sink.complete();
    await f1;
    expect(sink.receivedBytes.map(text), ['a', 'b', 'c', 'd']);
    await Future<void>.delayed(Duration.zero);
    expect(sink.flushes, 2, reason: 'the second flush follows the first');
    sink.complete();
    await f2;
  });

  test('a frame is copied: the caller may reuse its buffer at once', () {
    final buf = bytes('frame 1');
    out.frame(buf);
    buf.setAll(0, bytes('changed'));
    expect(sink.receivedBytes.map(text), ['frame 1']);
    expect(text(sink.received.single), 'frame 1');
  });

  test('frames reuse one buffer once the flush carried it completed', () async {
    out.frame(bytes('one'));
    final f = out.flush();
    sink.complete();
    await f;
    out.frame(bytes('two'));
    expect(sink.receivedBytes.map(text), ['one', 'two']);
    // the second frame went into the same buffer the first was handed
    // over in (which the sink had consumed by then): no garbage
    expect(text(sink.received[0]), 'two');
    expect(
      identical(sink.received[0], sink.received[1]),
      isTrue,
      reason: 'same length: even the view object is reused',
    );
  });

  test('a frame written before the flush completed gets its own copy', () {
    out
      ..frame(bytes('one'))
      ..frame(bytes('two'));
    expect(sink.received.map(text), ['one', 'two'], reason: 'both intact');
  });

  test('a frame larger than the buffer still arrives whole', () {
    final big = Uint8List(100000)..fillRange(0, 100000, 0x41);
    out.frame(big);
    expect(sink.received.single.length, 100000);
    expect(sink.received.single.every((b) => b == 0x41), isTrue);
  });

  test('empty writes send nothing', () {
    out
      ..add(const [])
      ..frame(Uint8List(0));
    expect(sink.received, isEmpty);
  });

  test('a failed flush is reported, and later writes still go out', () async {
    out.add(bytes('a'));
    sink.failNextFlush = StateError('stdout gone');
    out.add(bytes('b'));
    await expectLater(out.flush(), throwsA(isA<StateError>()));
    out.add(bytes('c'));
    final f = out.flush();
    sink.complete();
    await f;
    expect(sink.receivedBytes.map(text), ['a', 'b', 'c']);
  });
}
