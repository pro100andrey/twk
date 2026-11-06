// tailFile's events: the bytes written, and a FileReset where the file is
// cut short or replaced, told by the type of the event, in order.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

  test(
    'a longer file renamed over the name before its event comes is read '
    'from its start: no fragment of it is told, however late the event',
    () async {
      File(path).writeAsStringSync('old line one\n');
      final inner = File(path);
      final replacement = [for (var i = 0; i < 5; i++) 'NEW LINE $i\n'].join();
      final events = StreamController<FileSystemEvent>();
      addTearDown(events.close);
      final told = <String>[];
      final subscription = clock.run(
        () => IOOverrides.runZoned(
          () => tailFile(path, fromEnd: true, poll: poll).listen(
            (e) => told.add(switch (e) {
              FileBytes(:final bytes) => String.fromCharCodes(bytes),
              FileReset() => 'reset',
            }),
          ),
          createFile: (p) => _Hooked(inner, watched: events.stream),
        ),
      );
      addTearDown(subscription.cancel);
      await clock.elapse(poll);
      File('${dir.path}${Platform.pathSeparator}other.log')
        ..writeAsStringSync(replacement)
        ..renameSync(path);
      // the poll comes first, the watch has told nothing yet
      await waitUntil(
        () => told.join().endsWith(replacement),
        'the replacement, not $told',
        between: () => clock.elapse(poll),
      );
      expect(told, ['reset', replacement]);
      events.add(FileSystemCreateEvent(path, false));
      await clock.elapse(poll);
      await clock.elapse(poll);
      expect(told, ['reset', replacement]);
    },
    testOn: 'mac-os || linux',
  );

  test('a file deleted and made again, longer, is read from its start, '
      'though ext4 gives it the inode it had', () async {
    File(path).writeAsStringSync('old line one\n');
    final told = follow();
    await clock.elapse(poll);
    File(path).deleteSync();
    final replacement = [for (var i = 0; i < 5; i++) 'NEW LINE $i\n'].join();
    File(path).writeAsStringSync(replacement);
    await waitUntil(
      () => told.join().endsWith(replacement),
      'the replacement, not $told',
      between: () => clock.elapse(poll),
    );
    expect(told.skipWhile((e) => e != 'reset').skip(1).join(), replacement);
  }, testOn: 'mac-os || linux');

  test('a look in flight when the stream is cancelled adds nothing after '
      'the close, and the cancel ends with its handle closed, under a clock '
      'nobody moves', () async {
    File(path).writeAsStringSync('old old\n');
    final inner = File(path);
    final asked = Completer<void>();
    final answer = Completer<int>();
    final errors = <Object>[];
    var closed = false;
    var cancelled = false;
    await runZonedGuarded(() async {
      final subscription = clock.run(
        () => IOOverrides.runZoned(
          () => tailFile(path, fromEnd: false, poll: poll).listen((_) {}),
          createFile: (p) => _Hooked(
            inner,
            onLength: (_) {
              asked.complete();
              return answer.future;
            },
            onClose: () => closed = true,
          ),
        ),
      );
      // the first look has asked the length and waits for it; the stream is
      // cancelled, then the answer comes: the file was cut short
      await waitFor(asked.future, 'the look to ask the length');
      final cancel = subscription.cancel().then((_) => cancelled = true);
      await pumpEventQueue();
      expect(cancelled, isFalse);
      answer.complete(0);
      await waitFor(cancel, 'the cancel to end with the look');
      expect(closed, isTrue);
      await pumpEventQueue();
    }, (e, _) => errors.add(e));
    expect(errors, isEmpty);
  });

  test('a look the name tells nothing new to opens nothing, so that Windows '
      'does not refuse the writer a rename: the next write opens it', () async {
    File(path).writeAsStringSync('old\n');
    final inner = File(path);
    final told = <String>[];
    var named = 0;
    var opened = 0;
    final subscription = clock.run(
      () => IOOverrides.runZoned(
        () => tailFile(path, fromEnd: true, poll: poll).listen(
          (e) => told.add(switch (e) {
            FileBytes(:final bytes) => String.fromCharCodes(bytes),
            FileReset() => 'reset',
          }),
        ),
        createFile: (p) => _Hooked(
          inner,
          onNamedLength: () => named++,
          onOpen: () => opened++,
        ),
      ),
    );
    addTearDown(subscription.cancel);
    await waitUntil(
      () => named >= 3,
      'three looks',
      between: () => clock.elapse(poll),
    );
    expect(opened, 0);
    File(path).writeAsStringSync('more\n', mode: FileMode.append);
    await waitUntil(
      () => told.isNotEmpty,
      'the write',
      between: () => clock.elapse(poll),
    );
    expect(told, ['more\n']);
    expect(opened, 1);
  });

  test('a read that fails midway is not told again by the next look: the '
      'chunks already told are not read twice', () async {
    File(path).writeAsStringSync('first\nsecond\n');
    final inner = File(path);
    var reads = 0;
    final told = <String>[];
    final subscription = clock.run(
      () => IOOverrides.runZoned(
        () => tailFile(path, fromEnd: false, poll: poll).listen(
          (e) => told.add(switch (e) {
            FileBytes(:final bytes) => String.fromCharCodes(bytes),
            FileReset() => 'reset',
          }),
        ),
        // 'first\n' is read, the next read fails as if rotated away midway;
        // the later looks read as asked
        createFile: (p) => _Hooked(
          inner,
          onRead: (raf, count) {
            reads++;
            if (reads == 1) {
              return raf.read(6);
            }
            if (reads == 2) {
              return Future.error(const FileSystemException('gone'));
            }
            return raf.read(count);
          },
        ),
      ),
    );
    addTearDown(subscription.cancel);
    await holds(told, ['first\n', 'second\n']);
    await clock.elapse(poll);
    expect(told, ['first\n', 'second\n']);
  });

  // Windows refuses a rename over a file open anywhere: it cannot happen there
  test('a file renamed over the name right after its length was taken is '
      'not read at the old range: nothing of it is told before the reset, '
      'then it is told from its start', () async {
    File(path).writeAsStringSync('old line one\n');
    final inner = File(path);
    final other = '${dir.path}${Platform.pathSeparator}other.log';
    final staged = File(other);
    final replacement = [for (var i = 0; i < 5; i++) 'NEW LINE $i\n'].join();
    var armed = false;
    final told = <String>[];
    final subscription = clock.run(
      () => IOOverrides.runZoned(
        () => tailFile(path, fromEnd: true, poll: poll).listen(
          (e) => told.add(switch (e) {
            FileBytes(:final bytes) => String.fromCharCodes(bytes),
            FileReset() => 'reset',
          }),
        ),
        createFile: (p) => _Hooked(
          inner,
          onLength: (raf) async {
            final size = await raf.length();
            if (armed) {
              armed = false;
              staged
                ..writeAsStringSync(replacement)
                ..renameSync(path);
            }
            return size;
          },
        ),
      ),
    );
    addTearDown(subscription.cancel);
    await clock.elapse(poll);
    armed = true;
    File(path).writeAsStringSync('second\n', mode: FileMode.append);
    await waitUntil(
      () => told.contains('reset') && told.join().endsWith(replacement),
      'the reset and the replacement from its start, not $told',
      between: () => clock.elapse(poll),
    );
    // the old file's own bytes may be told before the reset, the new
    // file's middle may not
    expect(told.takeWhile((e) => e != 'reset').join(), isIn(['', 'second\n']));
    expect(told.skipWhile((e) => e != 'reset').skip(1).join(), replacement);
  }, testOn: '!windows');

  test(
    'a file put at the name while a look holds the one it replaced: the '
    'look is made again, nothing of the old file told after the reset',
    () async {
      File(path).writeAsStringSync('old line one\n');
      final inner = File(path);
      final staged = File('${dir.path}${Platform.pathSeparator}other.log');
      final replacement = [for (var i = 0; i < 5; i++) 'NEW LINE $i\n'].join();
      final events = StreamController<FileSystemEvent>();
      addTearDown(events.close);
      var armed = false;
      final told = <String>[];
      final subscription = clock.run(
        () => IOOverrides.runZoned(
          () => tailFile(path, fromEnd: true, poll: poll).listen(
            (e) => told.add(switch (e) {
              FileBytes(:final bytes) => String.fromCharCodes(bytes),
              FileReset() => 'reset',
            }),
          ),
          createFile: (p) => _Hooked(
            inner,
            watched: events.stream,
            onLength: (raf) async {
              final size = await raf.length();
              if (armed) {
                armed = false;
                staged
                  ..writeAsStringSync(replacement)
                  ..renameSync(path);
                // the watch tells it before the look goes on
                events.add(FileSystemCreateEvent(path, false));
                await pumpEventQueue();
              }
              return size;
            },
          ),
        ),
      );
      addTearDown(subscription.cancel);
      await clock.elapse(poll);
      armed = true;
      File(path).writeAsStringSync('second\n', mode: FileMode.append);
      await waitUntil(
        () => told.join().endsWith(replacement),
        'the replacement, not $told',
        between: () => clock.elapse(poll),
      );
      // where identity tells files apart the look ends with the old file's own
      // bytes and the next one resets; what follows the reset is the new file
      expect(
        told.takeWhile((e) => e != 'reset').join(),
        isIn(['', 'second\n']),
      );
      expect(told.skipWhile((e) => e != 'reset').skip(1).join(), replacement);
    },
    testOn: '!windows',
  );
}

/// A file whose handles ask `onLength` for the length and `onRead` for each
/// read, in place of the file's own where given, and that says when its
/// length is asked by the name, a handle is opened and one is closed.
class _Hooked implements File {
  _Hooked(
    this._file, {
    this.onLength,
    this.onRead,
    this.onNamedLength,
    this.onOpen,
    this.onClose,
    this.watched,
  });

  final File _file;
  final Future<int> Function(RandomAccessFile)? onLength;
  final Future<Uint8List> Function(RandomAccessFile, int)? onRead;
  final void Function()? onNamedLength;
  final void Function()? onOpen;
  final void Function()? onClose;

  /// What the watch of the directory tells, in place of the system's.
  final Stream<FileSystemEvent>? watched;

  @override
  Future<int> length() {
    onNamedLength?.call();
    return _file.length();
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    onOpen?.call();
    return _Handle(await _file.open(), onLength, onRead, onClose);
  }

  @override
  Uri get uri => _file.uri;

  @override
  Directory get parent => switch (watched) {
    final Stream<FileSystemEvent> events => _Watched(events),
    null => _file.parent,
  };

  @override
  int lengthSync() => _file.lengthSync();

  @override
  bool existsSync() => _file.existsSync();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A directory whose watch is [_events].
class _Watched implements Directory {
  _Watched(this._events);

  final Stream<FileSystemEvent> _events;

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => _events;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Handle implements RandomAccessFile {
  _Handle(this._raf, this._onLength, this._onRead, this._onClose);

  final RandomAccessFile _raf;
  final Future<int> Function(RandomAccessFile)? _onLength;
  final Future<Uint8List> Function(RandomAccessFile, int)? _onRead;
  final void Function()? _onClose;

  @override
  Future<int> length() => _onLength?.call(_raf) ?? _raf.length();

  @override
  Future<RandomAccessFile> setPosition(int position) async {
    await _raf.setPosition(position);
    return this;
  }

  @override
  Future<Uint8List> read(int count) =>
      _onRead?.call(_raf, count) ?? _raf.read(count);

  @override
  Future<void> close() async {
    await _raf.close();
    _onClose?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
