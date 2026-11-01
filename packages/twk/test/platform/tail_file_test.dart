// tailFile's events: the bytes written, and a FileReset where the file is
// cut short or replaced, told by the type of the event, in order.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/src/platform/platform.dart';
import 'package:twk_test/twk_test.dart';

const poll = Duration(milliseconds: 200);

void main() {
  late Directory dir;
  late String path;
  late FakeClock clock;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('twk_tail_file');
    path = '${dir.path}${Platform.pathSeparator}app.log';
    clock = FakeClock();
  });
  tearDown(() => dir.delete(recursive: true));

  /// What [tailFile] tells of [path], as `text` for bytes and `reset`.
  List<String> follow({bool fromEnd = true}) {
    final told = <String>[];
    final subscription = clock.run(
      () => tailFile(path, fromEnd: fromEnd, poll: poll).listen(
        (e) => told.add(switch (e) {
          FileBytes(:final bytes) => String.fromCharCodes(bytes),
          FileReset() => 'reset',
        }),
      ),
    );
    addTearDown(subscription.cancel);
    return told;
  }

  Future<void> holds(List<String> told, List<String> events) => waitUntil(
    () => told.join() == events.join(),
    'the events $events, not $told',
    between: () => clock.elapse(poll),
  );

  test('bytes written are FileBytes; a file cut short is a FileReset, then '
      'its bytes from the start', () async {
    File(path).writeAsStringSync('old\n');
    final told = follow();
    await clock.elapse(poll);
    File(path).writeAsStringSync('more\n', mode: FileMode.append);
    await holds(told, ['more\n']);
    File(path).writeAsStringSync('x\n');
    await holds(told, ['more\n', 'reset', 'x\n']);
  });

  test('a file made over it that starts with what was read is the same file, '
      'a create event late: only the rest is told', () async {
    File(path).writeAsStringSync('same\n');
    final told = follow(fromEnd: false);
    await holds(told, ['same\n']);
    final other = '${dir.path}${Platform.pathSeparator}other.log';
    File(other).writeAsStringSync('same\nmore\n');
    File(other).renameSync(path);
    await holds(told, ['same\n', 'more\n']);
  });
}
