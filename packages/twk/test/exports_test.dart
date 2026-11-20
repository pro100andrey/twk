// The analyzer resolves the packages once for the file, which takes seconds
// on a quiet machine and longer on a loaded one.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk/format.dart';
import 'package:twk/log.dart';
// Imported so that this file fails to load when a library that twk.dart
// exports is missing or does not compile.
// ignore: unused_import
import 'package:twk/twk.dart';
import 'package:twk_api_names/export_surface.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'sample_app.dart' as sample;

/// The topics of the package, each a library `src/<topic>/<topic>.dart`.
const topics = [
  'animation',
  'ansi',
  'binding',
  'controls',
  'data',
  'debug',
  'editing',
  'finders',
  'focus',
  'foundation',
  'framework',
  'gestures',
  'layout',
  'navigation',
  'overlay',
  'scroll',
  'semantics',
  'style',
  'text',
];

/// The twk_core declarations a public signature of this package, or a
/// constructor of a core class twk.dart exports, names that twk.dart does
/// not export: the render objects the widgets create and the parent data
/// they put on them, named by their `createRenderObject`,
/// `updateRenderObject` and supertypes only (the widgets are final), the
/// core's app the binding drives (`AppBinding.twkApp`), and what the
/// constructors of `Canvas` and `PaintContext` take, the frame loop's
/// machinery: the loop makes those and hands them to the render objects
/// that paint, and an app never makes one.
const notExported = {
  'FlexParentData',
  'GlyphTable',
  'GridParentData',
  'Presenter',
  'RenderConstrainedBox',
  'RenderDivider',
  'RenderErrorBox',
  'RenderFlex',
  'RenderFractionallySizedBox',
  'RenderGrid',
  'RenderIntrinsicHeight',
  'RenderIntrinsicWidth',
  'RenderPadding',
  'RenderParagraph',
  'RenderPositionedBox',
  'RenderStack',
  'RenderWrap',
  'StackParentData',
  'Surface',
  'TwkApp',
};

void main() {
  // one analysis for the file
  final surface = ExportSurface.open();
  late final Map<String, Declaration> exported;

  setUpAll(() async {
    exported = await surface.exports('package:twk/twk.dart');
  });

  test('format.dart exports formatBytes and formatTook, for an app to write '
      'sizes and times as the widgets do', () {
    expect(formatBytes(4096), '4.1 kB');
    expect(formatBytes(4096, byteUnits: ByteUnits.binary), '4.0 KiB');
    expect(formatTook(const Duration(milliseconds: 3100)), '3.1 s');
  });

  test('twk.dart exports the library of every topic', () async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:twk/twk.dart'),
    );
    final source = File.fromUri(uri!).readAsStringSync();
    final exports = RegExp(
      "^export '([^']*)';",
      multiLine: true,
    ).allMatches(source).map((match) => match[1]).toList();
    expect(exports, [for (final topic in topics) 'src/$topic/$topic.dart']);
  });

  test('cli.dart, format.dart, hooks.dart, log.dart and provider.dart are '
      'libraries of their own, '
      'besides twk.dart, which exports none of their names', () async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:twk/twk.dart'),
    );
    expect(
      [
        for (final entity in File.fromUri(uri!).parent.listSync())
          if (entity is File && entity.path.endsWith('.dart'))
            entity.uri.pathSegments.last,
      ]..sort(),
      [
        'cli.dart',
        'format.dart',
        'hooks.dart',
        'log.dart',
        'provider.dart',
        'twk.dart',
      ],
    );
    for (final (library, declared) in [
      ('format', {'ByteUnits', 'formatBytes', 'formatTook'}),
      ('log', {'LogData', 'LogLevel', 'LogRecord', 'LogSink', 'log'}),
    ]) {
      final names = await surface.exports('package:twk/$library.dart');
      expect(names.keys, declared);
      expect(
        [
          for (final name in names.keys)
            if (exported.containsKey(name)) name,
        ],
        isEmpty,
        reason: 'twk.dart exports no name of $library.dart',
      );
    }
    for (final (library, widget) in [
      ('cli', 'Cli'),
      ('hooks', 'HookWidget'),
      ('provider', 'Provider'),
    ]) {
      final names = await surface.exports('package:twk/$library.dart');
      expect(names, contains(widget));
      expect(
        [
          for (final d in names.values)
            if (!d.library.path.startsWith('twk/src/$library/')) d.name,
        ],
        isEmpty,
        reason: '$library.dart exports its own declarations only',
      );
      expect(
        [
          for (final name in names.keys)
            if (exported.containsKey(name)) name,
        ],
        isEmpty,
        reason: 'twk.dart exports no name of $library.dart',
      );
    }
  });

  test('twk.dart exports the core types that public signatures name, and '
      'those a core class it exports is made with, but the render objects '
      'of its widgets, and those of the log, which log.dart has', () async {
    final named = <String, String>{};
    for (final d in exported.values) {
      for (final use in [
        if (d.package == 'twk')
          ...d.signature()
        // a core class twk.dart exports: what an app makes one with (a
        // HeadlessTerminal for a test)
        else if (d.isInterface)
          ...d.constructorSignatures(),
      ]) {
        for (final type in use.types) {
          if (type.package == 'twk_core') {
            named.putIfAbsent(type.name, () => use.where);
          }
        }
      }
    }
    expect(named.keys, containsAll(notExported));
    // the log's names are in log.dart, which an app that logs imports
    final logged = await surface.exports('package:twk/log.dart');
    expect({
      for (final MapEntry(:key, :value) in named.entries)
        if (!exported.containsKey(key) &&
            !logged.containsKey(key) &&
            !notExported.contains(key))
          key: value,
    }, isEmpty);
  });

  test('an app that imports only twk.dart builds every public widget and '
      'names every core declaration twk.dart exports', () async {
    final source = File('test/sample_app.dart').readAsStringSync();
    expect(
      [
        for (final m in RegExp(
          "^import '([^']*)';",
          multiLine: true,
        ).allMatches(source))
          if (!m[1]!.startsWith('dart:')) m[1],
      ],
      [
        'package:twk/format.dart',
        'package:twk/log.dart',
        'package:twk/twk.dart',
      ],
    );
    final parts = [
      for (final m in RegExp(
        "^part '([^']*)';",
        multiLine: true,
      ).allMatches(source))
        m[1]!,
    ];
    expect(parts, [for (final topic in topics) 'sample_app/$topic.dart']);
    final code = [
      source,
      for (final part in parts) File('test/$part').readAsStringSync(),
    ].join('\n').replaceAll(RegExp('//.*'), '');
    final words = {for (final m in RegExp(r'\w+').allMatches(code)) m[0]};
    expect([
      for (final d in exported.values)
        if (!words.contains(d.name))
          if (d.package == 'twk_core')
            '${d.name}: name it in test/sample_app.dart or a part of it'
          else if (d.isInterface &&
              d.package == 'twk' &&
              d.isSubclassOf('Widget', inPackage: 'twk'))
            '${d.name}: build it in test/sample_app/${_topic(d)}.dart',
    ], isEmpty);
    expect(sample.snapshot(), 'snap');
    final clock = FakeClock();
    final logged = await clock.elapseUntil(
      clock.run(() => sample.runInMemory(clock: clock.clock)),
    );
    expect([
      for (final r in logged)
        if (r.level.index >= LogLevel.warning.index) '${r.message}: ${r.error}',
    ], isEmpty);
  });
}

/// The topic of the library that declares [d], `package:twk/src/<topic>/`.
String _topic(Declaration d) => d.library.pathSegments[2];
