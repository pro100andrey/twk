// The sink on its own: the ring, its listeners, the file, log() outside
// an app, and the zone a sink runs code in.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

final _at = DateTime(2026, 10, 19, 9, 5, 7, 42);

LogRecord record(String message) => LogRecord(_at, LogLevel.info, message);

void main() {
  test('the ring keeps the newest records, oldest first', () {
    final sink = LogSink(capacity: 3);
    List<String> messages() => [for (final r in sink.records) r.message];
    sink
      ..add(record('1'))
      ..add(record('2'));
    expect(messages(), ['1', '2']);
    sink
      ..add(record('3'))
      ..add(record('4'));
    expect(messages(), ['2', '3', '4']);
    sink
      ..add(record('5'))
      ..add(record('6'))
      ..add(record('7'));
    expect(messages(), ['5', '6', '7']);
  });

  test('listeners get each record as it is added', () {
    final sink = LogSink();
    final got = <String>[];
    void listener(LogRecord r) => got.add(r.message);
    sink
      ..add(record('before'))
      ..addListener(listener)
      ..add(record('a'))
      ..add(record('b'))
      ..removeListener(listener)
      ..add(record('after'));
    expect(got, ['a', 'b']);
  });

  test('a listener may remove itself while it is called', () {
    final sink = LogSink();
    final got = <String>[];
    late void Function(LogRecord r) once;
    once = (r) {
      got.add('once ${r.message}');
      sink.removeListener(once);
    };
    sink
      ..addListener(once)
      ..addListener((r) => got.add(r.message))
      ..add(record('a'))
      ..add(record('b'));
    expect(got, ['once a', 'a', 'b']);
  });

  test('formatTime is the time of day a record, the console, a log view and '
      'twk logs show, every part padded', () {
    expect(LogRecord.formatTime(_at), '09:05:07.042');
    expect(LogRecord.formatTime(DateTime(2026)), '00:00:00.000');
    expect(
      LogRecord.formatTime(DateTime(2026, 1, 1, 23, 59, 59, 999, 999)),
      '23:59:59.999',
    );
    expect(
      LogRecord.formatTime(DateTime(2026, 1, 1, 1, 2, 3, 4)),
      '01:02:03.004',
    );
    expect('${record('one')}', startsWith('${LogRecord.formatTime(_at)} '));
  });

  test('a path gets every record appended as it comes', () {
    final dir = Directory.systemTemp.createTempSync('twk_log');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/app.log')
      ..writeAsStringSync('an earlier run\n');
    // the file keeps what the ring drops
    final sink = LogSink(capacity: 1, path: file.path)..add(record('one'));
    expect(file.readAsLinesSync(), [
      'an earlier run',
      '09:05:07.042 info one',
    ]);
    sink.add(
      LogRecord(
        _at,
        LogLevel.error,
        'two',
        error: StateError('broken'),
        stack: StackTrace.fromString('#0      main (app.dart:1:1)\n'),
      ),
    );
    expect(file.readAsLinesSync(), [
      'an earlier run',
      '09:05:07.042 info one',
      '09:05:07.042 error two: Bad state: broken',
      '#0      main (app.dart:1:1)',
    ]);
  });

  test('log() outside an app prints the record', () {
    final printed = <String>[];
    runZoned(
      () => log('alone', level: LogLevel.warning),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );
    expect(printed, [matches(r'^\d\d:\d\d:\d\d\.\d\d\d warning alone$')]);
  });

  test(
    'run sends log() and print in its body, and in what the body '
    'schedules, to the sink, and returns and throws what the body does',
    () async {
      final sink = LogSink();
      final got = sink.run(() {
        log('saved', level: LogLevel.warning);
        print('printed');
        scheduleMicrotask(() => print('later'));
        return 7;
      });
      await Future<void>.value();
      expect(got, 7);
      expect(
        [for (final r in sink.records) (r.level, r.message)],
        [
          (LogLevel.warning, 'saved'),
          (LogLevel.info, 'printed'),
          (LogLevel.info, 'later'),
        ],
      );
      expect(() => sink.run(() => throw StateError('no')), throwsStateError);
      await expectLater(
        sink.run(() => Future<void>.error(StateError('later'))),
        throwsStateError,
      );
    },
  );
}
