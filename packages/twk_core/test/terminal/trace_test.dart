// Byte traces: what TraceWriter writes, read back by Trace; an input trace
// fed to HeadlessTerminal; both traces of trace_app.dart in a
// pseudo-terminal (tool/pty_run.py), the output one replayed by
// tool/replay.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart'
    show FakeClock, compiledProgram, runProcess;

import '../support/environment.dart';

Uint8List bytesOf(String s) => utf8.encode(s);

void main() {
  // the programs run in processes of their own, compiled once
  late String traceFull;
  late String traceApp;
  late String replayTool;
  setUpAll(() async {
    final packages = (await Isolate.packageConfig)!.toFilePath();
    const cache = '.dart_tool/twk_test/programs';
    traceFull = await compiledProgram(
      'test/terminal/trace_full.dart',
      packages: packages,
      cache: cache,
    );
    traceApp = await compiledProgram(
      'test/terminal/trace_app.dart',
      packages: packages,
      cache: cache,
    );
    replayTool = await compiledProgram(
      '../../tool/replay.dart',
      packages: packages,
      cache: cache,
    );
  });

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('trace'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('TraceWriter and Trace', () {
    test('a header line, then each record as time, length, bytes', () async {
      final path = '${dir.path}/out.trace';
      // its times are a clock's of the test's
      final clock = FakeClock();
      final writer = TraceWriter.open(
        path,
        TraceDirection.output,
        80,
        24,
        clock: clock.stopwatch,
      )..add(bytesOf('\x1b[?1049h'));
      await clock.elapse(const Duration(milliseconds: 5));
      writer
        ..add(bytesOf('héllo\n'))
        ..add(<int>[0x1b, 0x5b, 0x48]);
      await writer.close();

      final text = utf8.decode(File(path).readAsBytesSync());
      expect(
        text,
        matches(
          RegExp(
            r'^twk-trace 1 output 80x24\n'
            r'\d+ 8\n\x1b\[\?1049h\n'
            r'\d+ 7\nhéllo\n\n'
            r'\d+ 3\n\x1b\[H\n$',
          ),
        ),
      );

      final trace = Trace.read(path);
      expect(trace.direction, TraceDirection.output);
      expect((trace.width, trace.height), (80, 24));
      expect(trace.truncated, isFalse);
      expect(trace.records.map((r) => utf8.decode(r.bytes)), [
        '\x1b[?1049h',
        'héllo\n',
        '\x1b[H',
      ]);
      final t = trace.records.map((r) => r.micros).toList();
      expect(t, [0, 5000, 5000]);
      expect(utf8.decode(trace.bytes), '\x1b[?1049hhéllo\n\x1b[H');
    });

    test('adding writes nothing at once; records pile up while a write is '
        'on its way and all reach the file, in order', () async {
      final path = '${dir.path}/out.trace';
      final writer = TraceWriter.open(path, TraceDirection.output, 80, 24);
      final header = File(path).lengthSync();
      final buffer = Uint8List(16);
      for (var i = 0; i < 3000; i++) {
        buffer.setAll(0, ascii.encode(i.toString().padLeft(16)));
        writer.add(buffer);
        if (i == 999) {
          expect(File(path).lengthSync(), header, reason: 'written at once');
        }
        if (i >= 999 && i % 100 == 0) {
          // writes start on their own once the caller lets them
          await Future<void>.delayed(Duration.zero);
        }
      }
      await writer.close();
      final trace = Trace.read(path);
      expect(trace.records, hasLength(3000));
      for (var i = 0; i < 3000; i++) {
        expect(
          ascii.decode(trace.records[i].bytes).trim(),
          '$i',
          reason: 'the caller reused its buffer',
        );
      }
    });

    test(
      'a write that fails: close throws what it failed with',
      () async {
        // the file may not grow past 512 bytes, and going past it fails the
        // write (EFBIG) instead of killing the process (SIGXFSZ)
        final res = await runProcess('sh', [
          '-c',
          r'''trap '' XFSZ; ulimit -f 1; exec "$0" "$1" "$2"''',
          Platform.resolvedExecutable,
          traceFull,
          '${dir.path}/out.trace',
        ]);
        expect(res.stderr, '');
        expect(res.stdout, 'close threw FileSystemException, errno 27\n');
      },
      testOn: 'linux',
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('a record added after close is dropped; close twice', () async {
      final path = '${dir.path}/in.trace';
      final writer = TraceWriter.open(path, TraceDirection.input, 10, 5)
        ..add(bytesOf('a'));
      await writer.close();
      writer.add(bytesOf('b'));
      await writer.close();
      final trace = Trace.read(path);
      expect(trace.direction, TraceDirection.input);
      expect(trace.records.map((r) => utf8.decode(r.bytes)), ['a']);
    });

    test('a file cut off inside a record keeps the records before it', () {
      final whole = bytesOf('twk-trace 1 input 80x24\n5 2\nab\n90 4\ncd');
      final trace = Trace.parse(whole);
      expect(trace.truncated, isTrue);
      expect(trace.records.map((r) => (r.micros, utf8.decode(r.bytes))), [
        (5, 'ab'),
      ]);
      for (final cut in ['\n9', '\n90 ', '\n90 2', '\n90 2\n', '\n90 2\ncd']) {
        final t = Trace.parse(bytesOf('twk-trace 1 input 80x24\n5 2\nab$cut'));
        expect(t.records, hasLength(1), reason: cut);
        expect(t.truncated, isTrue, reason: cut);
      }
      final whole2 = Trace.parse(
        bytesOf('twk-trace 1 input 80x24\n5 2\nab\n90 2\ncd\n'),
      );
      expect(whole2.records, hasLength(2));
      expect(whole2.truncated, isFalse);
    });

    test('not a trace, or a broken record: FormatException', () {
      for (final s in [
        '',
        'hello\n',
        'twk-trace 2 output 80x24\n',
        'twk-trace 1 sideways 80x24\n',
        'twk-trace 1 output 80\n',
        'twk-trace 1 output 80x24\nx 2\nab\n',
        'twk-trace 1 output 80x24\n5 2\nabc\n',
        'twk-trace 1 output 80x24\n5  2\nab\n',
      ]) {
        expect(
          () => Trace.parse(bytesOf(s)),
          throwsFormatException,
          reason: s,
        );
      }
    });
  });

  group('an input trace fed back', () {
    List<String> keys(List<InputEvent> events) => [
      for (final e in events)
        if (e case KeyEvent(:final code, :final char, :final modifiers))
          (modifiers == Mod.alt ? 'alt+' : '') +
              (code == KeyCode.char ? char : code.name),
    ];

    Future<List<String>> fed(Trace trace) async {
      final term = HeadlessTerminal();
      final events = <InputEvent>[];
      term.events.listen(events.add);
      trace.feed(
        term.input,
        waiting: () => term.inputTimeout,
        timeOut: term.timeOutInput,
      );
      await Future<void>.delayed(Duration.zero);
      return keys(events);
    }

    test('read by read, a pause longer than what is pending waits for '
        'resolving it first', () async {
      Trace trace(List<(int, String)> reads) => Trace(
        TraceDirection.input,
        80,
        24,
        [for (final (t, s) in reads) TraceRecord(t, bytesOf(s))],
      );
      // ESC then b at once is Alt+b; after a pause, Escape and b
      expect(await fed(trace([(0, 'a'), (100, '\x1b'), (200, 'b')])), [
        'a',
        'alt+b',
      ]);
      expect(await fed(trace([(0, 'a'), (100, '\x1b'), (40000, 'b')])), [
        'a',
        'escape',
        'b',
      ]);
      // a sequence whose parameters arrived waits 500 ms for the rest
      expect(await fed(trace([(0, '\x1b[2'), (300000, '~')])), ['insert']);
      expect(
        await fed(trace([(0, '\x1b[2'), (600000, '~')])),
        isNot(contains('insert')),
      );
    });
  });

  // The group's timeout, its setUpAll's too, is what a loaded machine may
  // take: the app's run, up to pty_run's own timeout, and a replay for
  // each look at the traces.
  group(
    'a Terminal in a pseudo-terminal',
    () {
      late Directory run;
      late String outTrace;
      late String inTrace;
      late String out;

      setUpAll(() async {
        run = Directory.systemTemp.createTempSync('trace_run');
        outTrace = '${run.path}/out.trace';
        inTrace = '${run.path}/in.trace';
        out = '${run.path}/out.bin';
        final res = await runProcess(
          'python3',
          [
            '../../tool/pty_run.py',
            // typed once the app has drawn: hi, and q once hi is shown
            '--when',
            'typed:',
            '--when',
            'hi',
            '--input',
            '#1:hi,#2:q',
            '--out',
            out,
            '--',
            Platform.resolvedExecutable,
            traceApp,
          ],
          environment: childEnvironment({
            'TWK_TRACE_INPUT': inTrace,
            'TWK_TRACE_OUTPUT': outTrace,
          }),
          includeParentEnvironment: false,
          group: true,
        );
        expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
      });
      tearDownAll(() => run.deleteSync(recursive: true));

      Future<ProcessResult> replay(List<String> args) => runProcess(
        Platform.resolvedExecutable,
        [replayTool, ...args],
      );

      /// The screen [replay] printed: what comes before its summary line.
      String screen(ProcessResult res) {
        final out = res.stdout as String;
        return out.substring(0, out.lastIndexOf('\n--- bytes='));
      }

      String firstRow(ProcessResult res) =>
          screen(res).split('\n').first.trimRight();

      test(
        'the output trace holds every byte written, from the probe on, and '
        'replays to the screen the capture does',
        () async {
          final trace = Trace.read(outTrace);
          expect(trace.direction, TraceDirection.output);
          expect((trace.width, trace.height), (100, 30));
          expect(trace.truncated, isFalse);
          expect(trace.bytes, File(out).readAsBytesSync());
          expect(
            utf8.decode(trace.records.first.bytes),
            startsWith('\x1b[?2026\$p'),
            reason: 'the probe comes first',
          );

          final fromCapture = await replay(['--fullscreen', out, '100', '30']);
          final fromTrace = await replay(['--fullscreen', '--trace', outTrace]);
          expect(fromCapture.exitCode, 0, reason: '${fromCapture.stdout}');
          expect(fromTrace.exitCode, 0, reason: '${fromTrace.stdout}');
          expect(screen(fromTrace), screen(fromCapture));
          expect(firstRow(fromTrace), 'typed: hi');

          final first = await replay([
            '--fullscreen',
            '--trace',
            '--frame=1',
            outTrace,
          ]);
          expect(first.exitCode, 0, reason: '${first.stdout}');
          expect(firstRow(first), '─', reason: 'the probe');

          final steps = await replay([
            '--fullscreen',
            '--trace',
            '--step',
            outTrace,
          ]);
          expect(steps.exitCode, 0, reason: '${steps.stdout}');
          final headers = RegExp(
            r'^=== frame (\d+)/(\d+) at \d+ µs, (\d+) bytes ===$',
            multiLine: true,
          ).allMatches(steps.stdout as String).toList();
          expect(headers, hasLength(trace.records.length));
          for (var i = 0; i < headers.length; i++) {
            expect(headers[i][1], '${i + 1}');
            expect(headers[i][3], '${trace.records[i].bytes.length}');
          }
          expect(
            (steps.stdout as String).split(headers.last[0]!).last,
            contains(screen(fromTrace)),
          );
        },
      );

      test(
        'the input trace holds the probe answers and the keys, and decodes '
        'to those keys again',
        () async {
          final trace = Trace.read(inTrace);
          expect(trace.direction, TraceDirection.input);
          expect(trace.truncated, isFalse);
          expect(utf8.decode(trace.bytes), endsWith('hiq'));
          expect(utf8.decode(trace.records.first.bytes), startsWith('\x1b['));
          final output = Trace.read(outTrace);
          expect(
            trace.records.first.micros,
            greaterThanOrEqualTo(output.records.first.micros),
            reason: 'answers come after the probe, on one clock',
          );

          final term = HeadlessTerminal();
          final events = <InputEvent>[];
          term.events.listen(events.add);
          trace.feed(
            term.input,
            waiting: () => term.inputTimeout,
            timeOut: term.timeOutInput,
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            [
              for (final e in events)
                if (e case KeyEvent(code: KeyCode.char, :final char)) char,
            ],
            ['h', 'i', 'q'],
          );
          expect(events.whereType<DeviceAttributes>(), hasLength(1));
        },
      );

      test(
        'a trace that cannot be written fails open() before the terminal is '
        'touched',
        () async {
          final capture = '${run.path}/failed.bin';
          final res = await runProcess(
            'python3',
            [
              '../../tool/pty_run.py',
              '--input',
              'none',
              '--expect-status',
              '255',
              '--out',
              capture,
              '--',
              Platform.resolvedExecutable,
              traceApp,
            ],
            environment: childEnvironment({
              'TWK_TRACE_OUTPUT': '${run.path}/missing/out.trace',
            }),
            includeParentEnvironment: false,
            group: true,
          );
          // pty_run checked the tty is as it was, and shows the program's
          // stderr
          expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
          expect(res.stdout, contains('PathNotFoundException'));
          expect(File(capture).lengthSync(), 0, reason: 'no probe, no mode');
        },
      );
    },
    testOn: 'linux || mac-os',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
