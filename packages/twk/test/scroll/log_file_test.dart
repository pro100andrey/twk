// A LogController following a file being written: the lines written from
// the moment it is followed, each once it ends; from its start when
// asked; a file truncated read again from its start; a file not there yet
// waited for. Its writes come by the system's watch or the poll, which the
// fake clock moves.
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

  test(
    'from the moment it is followed: a write right after it is read',
    () async {
      File(path).writeAsStringSync('old\n');
      final c = follow();
      // an end read later, on the I/O thread as a busy machine delays it,
      // would take this write for what was there
      File(path).writeAsStringSync('new\n', mode: FileMode.append);
      await holds(c, ['new']);
    },
  );

  test('from its start when asked, in its colors, and a file not there yet '
      'waited for', () async {
    final c = follow(fromEnd: false);
    await clock.elapse(poll);
    expect(c.length, 0);
    File(path).writeAsStringSync('\x1B[31mfirst\x1B[0m\nsecond\n');
    await holds(c, ['first', 'second']);
    expect(c[0].spans?.first.style.fg, Color.red);
  });

  test(
    'a longer file renamed over it is read from its start',
    () async {
      File(path).writeAsStringSync('old\n');
      final c = follow();
      await clock.elapse(poll);
      final other = '${dir.path}${Platform.pathSeparator}rotated.log';
      File(other).writeAsStringSync('replacement 1\nreplacement 2\n');
      File(other).renameSync(path);
      await waitUntil(
        () =>
            texts(c).length >= 2 &&
            '${texts(c).sublist(texts(c).length - 2)}' ==
                '[replacement 1, replacement 2]',
        'the replacement from its start, not ${texts(c)}',
        between: () => clock.elapse(poll),
      );
    },
    skip: FileSystemEntity.isWatchSupported
        ? false
        : 'no directory watch here: the poll cannot tell a replaced file',
  );

  test('a file of another name ending with it is not it: made beside the '
      'file followed, it does not read that again', () async {
    File(path).writeAsStringSync('one\ntwo\n');
    final c = follow(fromEnd: false);
    await holds(c, ['one', 'two']);
    File(
      '${dir.path}${Platform.pathSeparator}old_app.log',
    ).writeAsStringSync('other\n');
    await clock.elapse(poll);
    await clock.elapse(poll);
    expect(texts(c), ['one', 'two']);
  });

  test('a file cut short drops the line the old one left unended', () async {
    File(path).writeAsStringSync('first\n');
    final c = follow();
    await clock.elapse(poll);
    File(path).writeAsStringSync('second\nabc', mode: FileMode.append);
    await holds(c, ['second']);
    File(path).writeAsStringSync('x\n');
    await holds(c, ['second', 'x']);
  });

  test('disposed without cancelling: the stream and the file are let go of, '
      'and the subscription returned cancels again', () async {
    final out = StreamController<String>();
    addTearDown(out.close);
    final listened = LogController();
    final fromStream = listened.addOutput(out.stream);
    expect(out.hasListener, isTrue);
    listened.dispose();
    expect(out.hasListener, isFalse);
    expect(() => out.add('late\n'), returnsNormally);
    await fromStream.cancel();

    File(path).writeAsStringSync('old\n');
    final followed = LogController();
    final fromFile = clock.run(
      () => followed.followFile(path, poll: poll),
    );
    await clock.elapse(poll);
    followed.dispose();
    File(path).writeAsStringSync('new\n', mode: FileMode.append);
    await clock.elapse(poll);
    await clock.elapse(poll);
    await fromFile.cancel();
  });

  test('followFile takes the tabWidth', () async {
    File(path).writeAsStringSync('a\tb\n');
    final c = LogController();
    addTearDown(c.dispose);
    final source = clock.run(
      () => c.followFile(path, fromEnd: false, poll: poll, tabWidth: 4),
    );
    addTearDown(source.cancel);
    await holds(c, ['a   b']);
  });
}
