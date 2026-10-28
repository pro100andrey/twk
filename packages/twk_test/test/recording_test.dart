// Frame recording: each frame the app wrote with its time on the clock and
// the screen it left, an output trace of them for tool/replay.dart, and the
// last of them printed when a test fails.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show Trace, TraceDirection;
import 'package:twk_test/twk_test.dart';

import 'fixtures/ticker.dart';

/// The frames of [t] that changed the screen: the time of each and the
/// rows it left.
List<List<Object>> changes(TwkTester t) {
  final out = <List<Object>>[];
  var before = '';
  for (final f in t.frames) {
    final screen = f.lines.join('\n');
    if (screen != before) {
      out.add([f.time, f.lines]);
    }
    before = screen;
  }
  return out;
}

void main() {
  testTwk('frames are the writes of the app in order, each with its time on '
      'the clock and the screen it left', (t) async {
    await t.pumpWidget(
      const TickingCounter(Duration(milliseconds: 100), to: 2),
      size: (10, 2),
    );
    await t.pump(const Duration(milliseconds: 250));
    final frames = t.frames;
    expect(
      [for (final f in frames) f.number],
      [
        for (var i = 1; i <= t.terminal.frames.length; i++) i,
      ],
    );
    expect([for (final f in frames) f.bytes], t.terminal.frames);
    expect(changes(t), [
      [
        Duration.zero,
        ['tick 0', ''],
      ],
      [
        const Duration(milliseconds: 100),
        ['tick 1', ''],
      ],
      [
        const Duration(milliseconds: 200),
        ['tick 2', ''],
      ],
    ]);
    expect(frames.last.lines, t.lines);
  });

  testTwk('the screens of the frames follow a resize as the terminal did', (
    t,
  ) async {
    await t.pumpWidget(const Text('a b c d e f'), size: (12, 3));
    await t.resize(5, 2);
    await t.pump();
    expect(t.frames.last.lines, ['a b c', 'd e f']);
    expect(t.lines, ['a b c', 'd e f']);
  });

  testTwk('in the inline mode the screens of the frames are below the '
      'history, as the screen is', (t) async {
    await t.pumpWidget(
      const Text('app'),
      size: (10, 3),
      mode: ScreenMode.inline,
      history: [r'$ run'],
    );
    expect(t.frames.last.lines, [r'$ run', 'app', '']);
    expect(t.lines, [r'$ run', 'app', '']);
  });

  testTwk('a frame prints as its number, time and size, then the screen as a '
      'failing matcher shows it', (t) async {
    await t.pumpWidget(
      const Text('hi', style: Style(attrs: Attr.bold)),
      size: (6, 3),
    );
    final frame = t.frames.lastWhere((f) => f.lines.isNotEmpty);
    expect(
      '$frame',
      'frame ${frame.number} at 0.000 s, ${frame.bytes.length} bytes:\n'
          '0│[bold]hi[/]\n'
          '(rows 1–2 blank)',
    );
  });

  testTwk('writeTrace writes the frames as an output trace, each at its '
      'time on the clock, at the size the app started at', (t) async {
    final dir = Directory.systemTemp.createTempSync('twk_test_trace');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/app.trace';
    await t.pumpWidget(
      const TickingCounter(Duration(milliseconds: 100), to: 2),
      size: (10, 2),
    );
    await t.pump(const Duration(milliseconds: 250));
    await t.resize(8, 2);
    await t.pump();
    t.writeTrace(path);
    final trace = Trace.read(path);
    final frames = t.frames;
    expect(trace.direction, TraceDirection.output);
    expect((trace.width, trace.height), (10, 2));
    expect(trace.truncated, isFalse);
    expect(
      [for (final r in trace.records) r.bytes],
      [
        for (final f in frames) f.bytes,
      ],
    );
    expect(
      [for (final r in trace.records) r.micros],
      [
        for (final f in frames) f.time.inMicroseconds,
      ],
    );
  });

  testTwk('without an app there are no frames to record', (t) {
    expect(() => t.frames, throwsStateError);
    expect(() => t.writeTrace('unused'), throwsStateError);
  });

  test('a test that fails prints the last frames of its app that changed '
      'the screen, as many as it asks for; none when none did', () async {
    final run = await runProcess(Platform.resolvedExecutable, [
      'test',
      '--reporter=json',
      'test/fixtures/frames_on_failure.dart',
    ], group: true);
    final names = <int, String>{};
    final prints = <String, List<String>>{};
    for (final line in LineSplitter.split('${run.stdout}')) {
      if (!line.startsWith('{')) {
        continue;
      }
      final event = jsonDecode(line) as Map<String, Object?>;
      switch (event) {
        case {
          'type': 'testStart',
          'test': {'id': final int id, 'name': final String name},
        }:
          names[id] = name;
        case {
          'type': 'print',
          'testID': final int id,
          'message': final String message,
        }:
          (prints[names[id]!] ??= []).add(message);
      }
    }
    expect(prints.keys, [
      'a test that fails',
      'a test that fails, printing one frame',
      'an app that fails as it ends',
    ]);
    final three = prints['a test that fails']!.single;
    expect(
      three,
      matches(
        RegExp(
          r'^the app wrote \d+ frames; the last 3 that changed the screen:\n'
          r'\n'
          r'frame \d+ at 0\.300 s, \d+ bytes:\n'
          r'0│tick 3\n'
          r'\(row 1 blank\)\n'
          r'\n'
          r'frame \d+ at 0\.400 s, \d+ bytes:\n'
          r'0│tick 4\n'
          r'\(row 1 blank\)\n'
          r'\n'
          r'frame \d+ at 0\.500 s, \d+ bytes:\n'
          r'0│tick 5\n'
          r'\(row 1 blank\)$',
        ),
      ),
    );
    final one = prints['a test that fails, printing one frame']!.single;
    expect(one, contains('the last 1 that changed the screen'));
    expect(one, contains('0│tick 5'));
    expect(one, isNot(contains('tick 4')));
    expect(
      prints['an app that fails as it ends']!.single,
      matches(
        RegExp(
          r'^the app wrote 1 frame; the last 1 that changed the screen:\n'
          r'\n'
          r'frame 1 at 0\.000 s, \d+ bytes:\n'
          r'0│tick 0\n'
          r'\(row 1 blank\)$',
        ),
      ),
    );
  });
}
