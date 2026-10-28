// The socket a LogSink serves on, where a client misbehaves: what the
// tests of test/log/ leave out.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('twk_log_server'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('cuts off a client that sends no line in its first '
      '256 bytes', () async {
    final sink = LogSink()..add(LogRecord(DateTime(2026), LogLevel.info, 'x'));
    final address = await sink.serve(directory: dir.path);
    addTearDown(sink.close);
    final client = await address.connect();
    final got = <int>[];
    final done = client.listen(got.addAll).asFuture<void>();
    client.add(List.filled(300, 0x61));
    await done.timeout(const Duration(seconds: 4));
    expect(got, isEmpty);
    client.destroy();
  });
}
