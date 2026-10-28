// TwkApp's frames on dart:developer's Timeline: timeline_app.dart run with
// the VM's Dart timeline stream recorded to a file, with TWK_DEBUG naming
// the timeline or not.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

import '../support/environment.dart';

const _names = {
  'Frame',
  'Build',
  'Layout',
  'Paint',
  'Commit',
  'Present',
  'Finalize',
};

/// timeline_app.dart, compiled once.
late String _app;

/// The begin and end events of a frame's phases timeline_app.dart left
/// on the timeline with `TWK_DEBUG` set to [debug], in the order written,
/// and how many of the app's own marks there were on the Dart stream.
Future<(List<String>, int)> phases(String debug) async {
  final dir = Directory.systemTemp.createTempSync('timeline');
  addTearDown(() => dir.deleteSync(recursive: true));
  final path = '${dir.path}/timeline.json';
  final res = await runProcess(
    Platform.resolvedExecutable,
    [
      '--timeline_streams=Dart',
      '--timeline_recorder=file:$path',
      _app,
    ],
    environment: childEnvironment({'TWK_DEBUG': debug}),
    includeParentEnvironment: false,
  );
  expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
  final events = (jsonDecode(File(path).readAsStringSync()) as List<Object?>)
      .cast<Map<String, Object?>>();
  final dart = events.where((e) => e['cat'] == 'Dart').toList();
  return (
    [
      for (final e in dart)
        if (_names.contains(e['name'])) '${e['ph']} ${e['name']}',
    ],
    dart.where((e) => e['name'] == 'timeline_app').length,
  );
}

void main() {
  setUpAll(
    () async => _app = await compiledProgram(
      'test/terminal/timeline_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test(
    'TWK_DEBUG=timeline: each frame and its build, layout, paint, '
    'present and what runs after it as slices',
    () async {
      const frame = [
        'B Frame',
        'B Build',
        'E Build',
        'B Layout',
        'E Layout',
        'B Paint',
        'E Paint',
        'B Present',
        'E Present',
        'B Finalize',
        'E Finalize',
        'E Frame',
      ];
      final (ours, _) = await phases('frames,timeline');
      expect(ours, [...frame, ...frame, ...frame]);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'without it nothing goes on the timeline, though it records',
    () async {
      final (ours, marks) = await phases('frames');
      expect(ours, isEmpty);
      expect(marks, 1, reason: 'the Dart stream was recorded');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
