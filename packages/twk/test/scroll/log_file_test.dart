// A LogController following a file being written: the lines written from
// now on, each once it ends; from its start when asked; a file truncated
// read again from its start; a file not there yet waited for. Its writes
// come by the system's watch or the poll, which the fake clock moves.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const poll = Duration(milliseconds: 200);

/// The texts of [c]'s lines.
List<String> texts(LogController c) => [
  for (var i = 0; i < c.length; i++) c[i].text,
];

void main() {
  late Directory dir;
  late String path;
  late FakeClock clock;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('twk_log_file');
    path = '${dir.path}${Platform.pathSeparator}app.log';
    clock = FakeClock();
  });
  tearDown(() => dir.delete(recursive: true));

  /// Follows [path] into a new controller, on the fake clock.
  LogController follow({bool fromEnd = true}) {
    final c = LogController();
    final subscription = clock.run(
      () => c.followFile(path, fromEnd: fromEnd, poll: poll),
    );
    addTearDown(subscription.cancel);
    return c;
  }

  /// Waits for [c] to hold [lines], the poll moved on between looks.
  Future<void> holds(LogController c, List<String> lines) => waitUntil(
    () => '${texts(c)}' == '$lines',
    'the lines $lines, not ${texts(c)}',
    between: () => clock.elapse(poll),
  );

  test('the lines written from now on, each once it ends; a file truncated '
      'is read again from its start', () async {
    File(path).writeAsStringSync('old\n');
    final c = follow();
    await clock.elapse(poll);
    File(path).writeAsStringSync('new 1\npart', mode: FileMode.append);
    await holds(c, ['new 1']);
    File(path).writeAsStringSync('ial\n', mode: FileMode.append);
    await holds(c, ['new 1', 'partial']);
    File(path).writeAsStringSync('fresh\n');
    await holds(c, ['new 1', 'partial', 'fresh']);
  });

  test('from its start when asked, in its colors, and a file not there yet '
      'waited for', () async {
    final c = follow(fromEnd: false);
    await clock.elapse(poll);
    expect(c.length, 0);
    File(path).writeAsStringSync('\x1B[31mfirst\x1B[0m\nsecond\n');
    await holds(c, ['first', 'second']);
    expect(c[0].spans?.first.style.fg, Color.red);
  });
}
