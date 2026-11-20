// The trace a session writes (part 8 of DESIGN.md) against the fakes of the
// ports: the cast cut at the frames' boundaries, a marker and a line for
// each step, the failing tap's covered target, a program without an app
// service.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart' show ElementFinder;
import 'package:twk_driver/twk_driver.dart';
import 'package:twk_test/twk_test.dart' show screenFrames;

import 'fakes.dart';

late Directory dir;

/// A session on fakes writing a trace; the app's first frame wrote
/// "start".
Future<({Session session, FakeProcess process, FakeService service})> started({
  List<String> Function()? log,
}) async {
  final process = FakeProcess();
  final service = FakeService();
  final starting = Session.start(
    const ProcessSpec('app.dart'),
    ports: SessionPorts(
      process: process,
      screen: (_, _) => FakeScreen(),
      connect: (_) async => service,
    ),
    trace: TraceOptions('${dir.path}/t/run', log: log, profile: 'plain'),
  );
  await pumpEventQueue();
  process.launched.terminal.app('start');
  service
    ..frame(frame: 1, inputRead: 0, outputWritten: 5)
    ..frames = 1
    ..statusWritten = 5;
  return (session: await starting, process: process, service: service);
}

List<Map<String, Object?>> lines(Session s) => [
  for (final l in File(s.trace!.tracePath).readAsLinesSync())
    jsonDecode(l) as Map<String, Object?>,
];

void main() {
  setUp(() => dir = Directory.systemTemp.createTempSync('twk_trace_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a step is a marker in the cast, a line in the trace, and the cast '
      'is cut at the frames', () async {
    final t = await started(log: () => ['one record']);
    final term = t.process.launched.terminal;
    final press = t.session.press('a');
    await pumpEventQueue();
    term.app('X');
    t.service.frame(frame: 2, inputRead: 3, outputWritten: 6);
    await press;
    await t.session.close();

    final cast = Cast.read(t.session.trace!.castPath);
    expect(
      [for (final e in cast.events) (e.code, e.data)],
      [('o', 'start'), ('m', '1 press {"keys":"a"}'), ('o', 'X')],
    );
    expect(cast.header.width, 80);

    final all = lines(t.session);
    expect(all.first, containsPair('type', 'header'));
    expect(all.first, containsPair('profile', 'plain'));
    expect(all.first['size'], [80, 24]);
    expect(
      [for (final l in all.where((l) => l['type'] == 'frame')) l],
      [
        {
          'type': 'frame',
          'frame': 1,
          'castEvent': 0,
          'outputWritten': 5,
          'raw': 5,
        },
        {
          'type': 'frame',
          'frame': 2,
          'castEvent': 2,
          'outputWritten': 6,
          'raw': 6,
        },
      ],
    );
    final step = all.singleWhere((l) => l['type'] == 'step');
    expect(step, containsPair('step', 1));
    expect(step, containsPair('action', 'press'));
    expect(step, containsPair('args', {'keys': 'a'}));
    expect(step, containsPair('castEvent', 1));
    expect(step, containsPair('frameBefore', 1));
    expect(step, containsPair('frame', 2));
    expect(step, containsPair('result', 'ok'));
    expect(step['log'], ['one record']);
    // the cast to the end of a frame's event is that frame's screen
    final screens = screenFrames(80, 24, cast.writes);
    expect(screens.last.lines.first, startsWith('startX'));
  });

  test("the records the app posts (twk.log) are the step's log and the "
      'tail of the session', () async {
    final t = await started();
    final term = t.process.launched.terminal;
    final press = t.session.press('a');
    await pumpEventQueue();
    t.service.post('twk.log', {
      'version': 1,
      'records': [
        {
          'time': '2026-01-01T09:05:07.042',
          'level': 'warning',
          'message': 'low disk',
        },
      ],
    });
    term.app('X');
    t.service.frame(frame: 2, inputRead: 3, outputWritten: 6);
    await press;
    final other = t.session.press('b');
    await pumpEventQueue();
    term.app('Y');
    t.service.frame(frame: 3, inputRead: 6, outputWritten: 7);
    await other;
    await t.session.close();
    final steps = lines(t.session).where((l) => l['type'] == 'step').toList();
    expect(steps[0]['log'], ['09:05:07.042 warning low disk']);
    expect(steps[1]['log'], isEmpty);
    expect(t.session.log, ['09:05:07.042 warning low disk']);
  });

  test('the trace of a failing tap holds the covered target and the '
      'screens around it', () async {
    final t = await started();
    t.service.answers['find'] = (_) => {
      'version': 1,
      'frame': 1,
      'count': 1,
      'matches': [
        {
          'id': 7,
          'type': 'Button',
          'key': null,
          'text': 'Save',
          'rect': {'x': 4, 'y': 2, 'width': 8, 'height': 1},
          'shown': {'x': 4, 'y': 2, 'width': 8, 'height': 1},
        },
      ],
    };
    t.service.answers['hitTest'] = (_) => {
      'version': 1,
      'frame': 1,
      'takenBy': null,
      'path': [
        {'id': 51, 'type': 'Dialog', 'render': 52},
      ],
      'listeners': <Object>[],
      'absorbedBy': null,
    };
    await expectLater(
      t.session.tap(const ElementFinder.text('Save')),
      throwsA(isA<DriverError>()),
    );
    await t.session.close();

    final step = lines(t.session).singleWhere((l) => l['type'] == 'step');
    expect(step['action'], 'tap');
    expect(step['result'], 'error');
    expect(step['error'], contains('is covered by Dialog'));
    expect(step['finder'], const ElementFinder.text('Save').toJson());
    expect(step['target'], containsPair('id', 7));
    expect(step['target'], containsPair('type', 'Button'));
    expect((step['hit']! as Map)['path'], [
      {'id': 51, 'type': 'Dialog', 'render': 52},
    ]);
    // the screen before and after: the frame before's boundary is in the
    // cast, ahead of the marker
    expect(step['frameBefore'], 1);
    expect(step['frame'], 1);
    final cast = Cast.read(t.session.trace!.castPath);
    final marker = step['castEvent']! as int;
    expect(cast.events[marker].code, 'm');
    expect(cast.events.take(marker).map((e) => e.data).join(), 'start');
  });

  test('an inline app: the LFs the pty made CR LF are kept, and a frame '
      'ends at an event', () async {
    final t = await started();
    final write = t.process.launched.terminal.app;
    // the app wrote "ab\ncd\n" in two frames, the pty gave "ab\r\ncd\r\n"
    write('ab\r\n');
    t.service.frame(frame: 2, inputRead: 0, outputWritten: 8);
    await pumpEventQueue();
    write('cd\r\n');
    t.service.frame(frame: 3, inputRead: 0, outputWritten: 11);
    await pumpEventQueue();
    await t.session.close();

    final cast = Cast.read(t.session.trace!.castPath);
    expect(cast.events.map((e) => e.data).toList(), [
      'start',
      'ab\r\n',
      'cd\r\n',
    ]);
    final frames = [
      for (final l in lines(t.session))
        if (l['type'] == 'frame') l,
    ];
    expect(frames.map((f) => (f['frame'], f['castEvent'], f['raw'])), [
      (1, 0, 5),
      (2, 1, 9),
      (3, 2, 13),
    ]);
    expect(frames.map((f) => f['outputWritten']), [5, 8, 11]);
  });

  test('the same screen twice keeps one tree', () async {
    final t = await started();
    t.service.answers['tree'] = (_) => {
      'version': 1,
      'root': {'id': 1, 'name': 'App', 'children': <Object>[]},
    };
    await t.session.clock.advance(const Duration(milliseconds: 5));
    await t.session.clock.advance(const Duration(milliseconds: 5));
    await t.session.clock.advance(const Duration(milliseconds: 5));
    await t.session.close();
    final all = lines(t.session);
    final steps = all.where((l) => l['type'] == 'step').toList();
    expect(steps.map((s) => s['action']), List.filled(3, 'clock.advance'));
    expect(all.where((l) => l['type'] == 'tree'), hasLength(1));
    expect(steps.map((s) => s['tree']).toSet(), {'t1'});
  });

  test('a program without an app service has a frame for each chunk', () async {
    final process = FakeProcess();
    final session = await Session.compose(
      const ProcessSpec('sh'),
      process: process,
      screen: FakeScreen(),
      trace: TraceOptions('${dir.path}/plain'),
    );
    process.launched.terminal.app(r'$ ');
    await pumpEventQueue();
    await session.type('ls');
    process.launched.terminal.app('ls\r\n');
    await pumpEventQueue();
    await session.close();
    final cast = Cast.read(session.trace!.castPath);
    expect(cast.events.map((e) => (e.code, e.data)), [
      ('o', r'$ '),
      ('m', '1 type {"text":"ls"}'),
      ('o', 'ls\r\n'),
    ]);
    final all = lines(session);
    // the screen at the start, then a frame for each chunk
    expect(all.where((l) => l['type'] == 'frame'), hasLength(3));
    final step = all.singleWhere((l) => l['type'] == 'step');
    expect(step['tree'], isNull);
    expect(step['frameBefore'], 2);
  });

  test('delete removes both files', () async {
    final t = await started();
    await t.session.close();
    final trace = t.session.trace!;
    expect(File(trace.castPath).existsSync(), isTrue);
    trace.delete();
    expect(File(trace.castPath).existsSync(), isFalse);
    expect(File(trace.tracePath).existsSync(), isFalse);
  });

  test(
    'a failure opening the JSON file closes the cast opened before it',
    () async {
      Directory('${dir.path}/t/run.trace.jsonl').createSync(recursive: true);
      final process = FakeProcess();
      final service = FakeService();
      // the fake's kill ends its output, which a closing stream completes
      // only once listened to
      process.launched.terminal.output.listen((_) {});
      final starting = Session.start(
        const ProcessSpec('app.dart'),
        ports: SessionPorts(
          process: process,
          screen: (_, _) => FakeScreen(),
          connect: (_) async => service,
        ),
        trace: TraceOptions('${dir.path}/t/run'),
      );
      await expectLater(starting, throwsA(isA<FileSystemException>()));
      expect(process.launched.killed, isTrue);
      // On platforms that keep an open file from being removed this checks the
      // rollback too; everywhere it checks the partial trace can be cleaned up.
      File('${dir.path}/t/run.cast').deleteSync();
    },
  );

  test(
    'a trace that cannot be opened ends the app that was launched',
    () async {
      // the trace's directory would be below a file
      final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
      final process = FakeProcess();
      final service = FakeService();
      // the fake's kill ends its output, which a closing stream completes
      // only once listened to
      process.launched.terminal.output.listen((_) {});
      final starting = Session.start(
        const ProcessSpec('app.dart'),
        ports: SessionPorts(
          process: process,
          screen: (_, _) => FakeScreen(),
          connect: (_) async => service,
        ),
        trace: TraceOptions('${blocker.path}/t/run'),
      );
      await expectLater(starting, throwsA(isA<FileSystemException>()));
      expect(process.launched.killed, isTrue);
    },
  );
}
