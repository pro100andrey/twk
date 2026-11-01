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

  test(
    'a file renamed over it that starts with the same bytes is a '
    'replacement all the same: a FileReset, then it from its start',
    () async {
      File(path).writeAsStringSync('header\n');
      final told = follow(fromEnd: false);
      await holds(told, ['header\n']);
      // the directory watch is live once an append is told with the poll's
      // clock not moved on (one made before it is lost): renamed before it, the
      // replacement would go unseen
      await waitUntil(
        () => told.length > 1,
        'an append told by the watch, not $told',
        between: () async {
          File(path).writeAsStringSync('x\n', mode: FileMode.append);
          await clock.elapse(Duration.zero);
        },
      );
      final other = '${dir.path}${Platform.pathSeparator}other.log';
      // begins with what the old one did, the lines the probe appended
      final rotated = 'header\n${'x\n' * 20}';
      File(other).writeAsStringSync(rotated);
      File(other).renameSync(path);
      await waitUntil(
        () =>
            told.length > 2 &&
            told[told.length - 2] == 'reset' &&
            told.last == rotated,
        'the reset and the replacement from its start, not $told',
        between: () => clock.elapse(poll),
      );
    },
  );

  test('a file not there yet that appears is read from its start once, '
      'whenever its create event comes', () async {
    final told = follow(fromEnd: false);
    await clock.elapse(poll);
    File(path).writeAsStringSync('first\n');
    await clock.elapse(poll);
    await holds(told, ['first\n']);
    // the create event of the appearance, late or not, has come by now: an
    // append is read on, and told nothing else
    File(path).writeAsStringSync('second\n', mode: FileMode.append);
    await holds(told, ['first\n', 'second\n']);
    await clock.elapse(poll);
    expect(told, ['first\n', 'second\n']);
  });

  test('a look in flight when the stream is cancelled adds nothing after '
      'the close', () async {
    File(path).writeAsStringSync('old old\n');
    final inner = File(path);
    final answer = Completer<int>();
    final errors = <Object>[];
    await runZonedGuarded(() async {
      final subscription = IOOverrides.runZoned(
        () => tailFile(path, fromEnd: true, poll: poll).listen((_) {}),
        createFile: (p) => _SlowLength(inner, answer.future),
      );
      // the first look has asked the length and waits for it; the stream is
      // cancelled and closed, then the answer comes: the file was cut short
      await subscription.cancel();
      await pumpEventQueue();
      answer.complete(0);
      await pumpEventQueue();
    }, (e, _) => errors.add(e));
    expect(errors, isEmpty);
  });
}

/// A file whose length is `answer`, when it comes.
class _SlowLength implements File {
  _SlowLength(this._file, this._answer);

  final File _file;
  final Future<int> _answer;

  @override
  Future<int> length() => _answer;

  @override
  Uri get uri => _file.uri;

  @override
  Directory get parent => _file.parent;

  @override
  int lengthSync() => _file.lengthSync();

  @override
  bool existsSync() => _file.existsSync();

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      _file.openRead(start, end);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
