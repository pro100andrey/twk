/// The options of the alloc tools and the lines of their report.
library;

import 'dart:convert';
import 'dart:io';

import 'profiler.dart';

final class AllocOptions {
  AllocOptions({
    required this.width,
    required this.height,
    required this.frames,
    required this.top,
    required this.only,
    required this.json,
    this.cpu = false,
    this.trace = const [],
  });

  /// Parses `--size=COLSxROWS` (200x60), `--frames=N` (a scenario's own
  /// count by default), `--top=N` (8 classes a scenario), `--only=A,B` and
  /// `--json=PATH`; `--cpu` adds where the time went, from the VM's CPU
  /// samples; `--trace=A,B` where the objects of classes A and B were
  /// allocated, by stack (the VM's allocation tracing).
  factory AllocOptions.parse(List<String> args) {
    var width = 200;
    var height = 60;
    int? frames;
    var top = 8;
    Set<String>? only;
    String? json;
    var cpu = false;
    var trace = const <String>[];
    for (final a in args) {
      final eq = a.indexOf('=');
      final key = eq < 0 ? a : a.substring(0, eq);
      final value = eq < 0 ? '' : a.substring(eq + 1);
      switch (key) {
        case '--size':
          final m = RegExp(r'^(\d+)x(\d+)$').firstMatch(value);
          if (m == null) {
            throw FormatException('bad --size: $value');
          }
          width = int.parse(m[1]!);
          height = int.parse(m[2]!);
        case '--frames':
          frames = int.parse(value);
        case '--top':
          top = int.parse(value);
        case '--only':
          only = value.split(',').toSet();
        case '--json':
          json = value;
        case '--cpu':
          cpu = true;
        case '--trace':
          trace = value.split(',');
        default:
          throw FormatException('unknown option: $a');
      }
    }
    return AllocOptions(
      width: width,
      height: height,
      frames: frames,
      top: top,
      only: only,
      json: json,
      cpu: cpu,
      trace: trace,
    );
  }

  final int width;
  final int height;
  final int? frames;
  final int top;
  final Set<String>? only;
  final String? json;
  final bool cpu;

  /// The classes whose allocations are traced (`--trace`).
  final List<String> trace;

  bool wants(String name) => only == null || only!.contains(name);
}

/// Prints the scenarios' lines as they are measured and, at the end, writes
/// them all as JSON.
final class AllocReport {
  AllocReport(this.opts) {
    stdout.writeln(
      '${'scenario'.padRight(18)} ${'unit'.padRight(6)}'
      '${'B/unit'.padLeft(10)}${'obj/unit'.padLeft(10)}'
      '${'B out/fr'.padLeft(10)}${'fr/unit'.padLeft(8)}'
      '${'scav/kst'.padLeft(9)}${'old/kst'.padLeft(8)}'
      '${'gc ms/kst'.padLeft(10)}${'max ms'.padLeft(7)}'
      '${'µs/unit'.padLeft(10)}',
    );
  }

  final AllocOptions opts;
  final _json = <Map<String, Object?>>[];

  /// Where [steps] steps (of [perStep] units each) allocated the traced
  /// classes: the [AllocOptions.top] stacks of each, with the objects a
  /// unit.
  void traces(
    List<({String cls, int count, String stack})> found,
    int steps, {
    int perStep = 1,
  }) {
    final units = steps * perStep;
    for (final cls in opts.trace) {
      final of = found.where((t) => t.cls == cls).take(opts.top).toList();
      stdout.writeln('    $cls allocated at (objects a unit, $units units):');
      if (of.isEmpty) {
        stdout.writeln('      nowhere');
      }
      for (final t in of) {
        stdout.writeln(
          '      ${(t.count / units).toStringAsFixed(2).padLeft(7)}  '
          '${t.stack}',
        );
      }
    }
  }

  /// One scenario: [s] over its steps, each [perStep] [unit]s; [frames]
  /// and [bytesOut] what was written over its [Sample.steps] (null where
  /// nothing is).
  void add(
    String name,
    Sample s, {
    String unit = 'frame',
    int perStep = 1,
    int? frames,
    int? bytesOut,
  }) {
    final units = s.frames * perStep;
    final gcUnits = s.gcFrames * perStep;
    final steps = s.steps * perStep;
    // collections per 1000 steps
    final k = 1000 / s.gcFrames;
    final out = bytesOut == null || frames == null || frames == 0
        ? '-'
        : (bytesOut / frames).toStringAsFixed(0);
    String f(num v, int width, [int digits = 0]) =>
        v.toStringAsFixed(digits).padLeft(width);
    stdout
      ..writeln(
        '${name.padRight(18)} ${unit.padRight(6)}'
        '${f(s.bytes / units, 10)}${f(s.objects / units, 10, 1)}'
        '${out.padLeft(10)}'
        '${frames == null ? '-'.padLeft(8) : f(frames / steps, 8, 2)}'
        '${f(s.scavenges * k, 9, 1)}${f(s.markSweeps * k, 8, 1)}'
        '${f(s.gcMicros / 1000 * k, 10, 1)}${f(s.maxPauseMicros / 1000, 7, 2)}'
        '${f(s.micros / gcUnits, 10, 1)}',
      )
      ..writeln(
        [
          for (final c in s.classes.take(opts.top)) _class(c, units),
          if (s.vmBytes > 0) '(vm) ${(s.vmBytes / units).toStringAsFixed(0)}B',
        ].join('  ').replaceAll(RegExp('^'), '    '),
      );
    if (s.cpuSamples > 0) {
      String pc(int n) => '${(100 * n / s.cpuSamples).toStringAsFixed(0)}%';
      final bySelf = List.of(s.cpu)..sort((a, b) => b.self.compareTo(a.self));
      final self = [
        for (final c in bySelf.take(opts.top)) '${c.name} ${pc(c.self)}',
      ];
      // what runs every step (the harness, the loop) says nothing
      final inclusive = [
        for (final c
            in s.cpu
                .where((c) => c.inclusive < s.cpuSamples * 0.97)
                .take(opts.top * 2))
          '${c.name} ${pc(c.inclusive)}',
      ];
      stdout
        ..writeln('    cpu ${s.cpuSamples} samples, self: ${self.join('  ')}')
        ..writeln('    inclusive: ${inclusive.join('  ')}');
    }
    _json.add({
      'scenario': name,
      'unit': unit,
      'perStep': perStep,
      'size': '${opts.width}x${opts.height}',
      'framesWritten': ?frames,
      'bytesWritten': ?bytesOut,
      ...s.toJson(top: opts.top),
    });
  }

  static String _class(ClassAllocs c, int units) {
    final b = (c.bytes / units).toStringAsFixed(0);
    final o = (c.objects / units).toStringAsFixed(1);
    return '${c.name} ${b}B/$o';
  }

  void end() {
    if (opts.json case final path?) {
      File(path).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_json),
      );
    }
  }
}
