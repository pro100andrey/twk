// Frame benchmark of the core: the time and the bytes of one frame for the
// updates of an agent-chat screen and of a word-wrapped paragraph, plus
// decoding a burst of input.
//
//   dart run tool/bench.dart --baseline=HEAD   # the working tree against HEAD
//   dart run tool/bench.dart                   # the working tree alone
//
// Options: --size=COLSxROWS (200x60), --rounds=N (5), --only=NAME[,NAME]
// (scenario names as in the report). --measure times in this process only
// and prints tab-separated lines (what the compiled executables do).
//
// Before a scenario is timed it runs for 64 frames into the test emulator
// (package:twk_test/vt.dart): a screen that differs from what was painted, or
// output the emulator rejects, stops the benchmark, so a broken scenario
// can't report a fast number. Bytes per frame are the mean over those
// frames: exact, the same on every machine. Times are the median of batches
// of frames, AOT-compiled.
//
// The benchmark compiles itself (`dart compile exe`) and runs the executable
// once per round. With --baseline it also compiles itself against REF,
// checked out in a temporary git worktree, and runs the two executables
// alternately, so load that drifts during the run affects both alike. REF
// is a commit of this repository, whose history starts with the core at
// packages/twk_core in a pub workspace with the scenarios' package; a
// scenario that uses what REF's core lacks makes the build against REF
// fail, said as such.
//
// On a busy machine timings are noise: pin the run to one core
// (`taskset -c 23 dart run tool/bench.dart ...`; the executables inherit
// it) and keep that core's SMT sibling idle. The report gives the load
// average and how busy the sibling was.
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart';

import 'package:twk_frame_scenarios/frame_scenarios.dart';
import 'package:twk_test/vt.dart';

const _usage =
    'usage: dart run tool/bench.dart [--baseline=REF] [--size=COLSxROWS] '
    '[--rounds=N] [--only=NAME,...] [--measure]';

/// Frames run into the emulator before a scenario is timed.
const _verifyFrames = 64;

// timing: the median of [_samples] batches of about [_batchMicros] each,
// after [_warmupMicros] of frames that aren't counted
const _warmupMicros = 100000;
const _batchMicros = 20000;
const _samples = 15;

/// A ratio of times above this is reported as slower.
const _slower = 1.05;

/// A busy SMT sibling above this share of a round is reported.
const _siblingBusyLimit = 0.05;

// what the frames return, kept so the work can't be optimised away
var _sink = 0;

Future<void> main(List<String> args) async {
  final _Options opts;
  try {
    opts = _Options.parse(args);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln(_usage);
    exitCode = 64;
    return;
  }
  // a compiled executable measures; `dart run` (the script is the source)
  // compiles and orchestrates
  if (opts.measure || !Platform.script.path.endsWith('.dart')) {
    exitCode = _measure(opts);
  } else {
    exitCode = await _run(opts);
  }
}

// --------------------------------------------------------------- measure --

/// Times the scenarios in this process and prints one line per scenario:
/// name, µs per frame, bytes written by the [_verifyFrames] checked frames
/// (-1 when it doesn't write).
int _measure(_Options opts) {
  for (final s in frameScenarios) {
    if (opts.only != null && !opts.only!.contains(s.name)) {
      continue;
    }
    final int bytes;
    try {
      bytes = _verify(s, opts.width, opts.height);
    } on ScenarioBroken catch (e) {
      stderr.writeln('${s.name}: ${e.message}');
      return 1;
    }
    final us = _time(s.start(FrameRig(opts.width, opts.height)));
    stdout.writeln('${s.name}\t$us\t$bytes');
  }
  if (_sink + scenarioSink == 42) {
    stdout.writeln();
  }
  return 0;
}

/// Runs [s] for [_verifyFrames] frames into the emulator and returns the
/// bytes they wrote; throws [ScenarioBroken] when the screen isn't what was
/// painted or the emulator rejected the output.
int _verify(FrameScenario s, int w, int h) {
  final rig = FrameRig(w, h);
  final frame = s.start(rig);
  if (!s.write) {
    for (var i = 1; i <= _verifyFrames; i++) {
      frame(i);
    }
    return -1;
  }
  // not strict: every complaint is collected and reported, not just the
  // first
  final vt = Vt(w, h, strict: false)..feed(rig.presenter.out.view);
  var bytes = 0;
  for (var i = 1; i <= _verifyFrames; i++) {
    bytes += frame(i);
    vt.feed(rig.presenter.out.view);
  }
  final problems = [
    ...vt.errors.take(5),
    ..._mismatches(rig, vt),
    if (vt.printWraps > 0) '${vt.printWraps} wraps caused by printing',
    if (vt.syncDepth != 0) 'DEC 2026 left open (depth ${vt.syncDepth})',
  ];
  if (problems.isNotEmpty) {
    throw ScenarioBroken(
      'the emulator disagrees with the frames:\n  ${problems.join('\n  ')}',
    );
  }
  return bytes;
}

/// Where the emulator's screen differs from what [rig]'s surface holds,
/// the first [limit]: a cell's glyph or its half of a wide one, its
/// colors (a blank's foreground only where a line on it shows it), its
/// attributes, its underline's color and its link.
List<String> _mismatches(FrameRig rig, Vt vt, {int limit = 5}) {
  final out = <String>[];
  final surface = rig.surface;
  for (var y = 0; y < surface.height; y++) {
    for (var x = 0; x < surface.width; x++) {
      final i = y * surface.width + x;
      final c = surface.cells[i];
      if ((c & kSkip) != 0) {
        continue;
      }
      final why = _differs(rig, c, surface.styles[i], vt.cell(x, y));
      if (why != null) {
        out.add('($x,$y) $why');
        if (out.length >= limit) {
          return out;
        }
      }
    }
  }
  return out;
}

/// How [v] differs from the cell [c] of style [s]; null where it does not.
String? _differs(FrameRig rig, int c, int s, VtCell v) {
  if ((c & kCont) != 0) {
    return v.role == -1
        ? null
        : 'want trailing half, got "${v.text}" role ${v.role}';
  }
  final wantRole = (c & kWide) != 0 ? 2 : 0;
  final text = rig.glyphs.stringOf(c);
  if (v.role != wantRole || v.text != text) {
    return 'want "$text"/$wantRole got "${v.text}"/${v.role}';
  }
  final styles = rig.styles;
  final fg = styles.fgOf(s).value;
  final bg = styles.bgOf(s).value;
  final attrs = styles.attrsOf(s);
  final ul = styles.underlineColorOf(s).value;
  if (bg != v.bg) {
    return 'bg want ${bg.toRadixString(16)} got ${v.bg.toRadixString(16)}';
  }
  const visible =
      Attr.underlineMask | Attr.strike | Attr.overline | Attr.reverse;
  if (text == ' ' && (attrs & Attr.reverse) == 0) {
    if ((attrs & visible) != (v.attrs & visible)) {
      return 'attrs(blank) want $attrs got ${v.attrs}';
    }
    // lines on a space are drawn in the foreground color (an underline
    // unless it has its own color)
    final linesUseFg =
        (attrs & (Attr.strike | Attr.overline)) != 0 ||
        ((attrs & Attr.underlineMask) != 0 && ul == 0);
    if (linesUseFg && fg != v.fg) {
      return 'fg(blank) want ${fg.toRadixString(16)} '
          'got ${v.fg.toRadixString(16)}';
    }
  } else {
    if (fg != v.fg) {
      return 'fg want ${fg.toRadixString(16)} got ${v.fg.toRadixString(16)}';
    }
    if (attrs != v.attrs) {
      return 'attrs want $attrs got ${v.attrs}';
    }
  }
  if ((attrs & Attr.underlineMask) != 0 && ul != v.ul) {
    return 'ul color';
  }
  final link = styles.linkOf(s);
  return link != v.link ? 'link want $link got ${v.link}' : null;
}

/// Median µs per frame of [frame].
double _time(int Function(int i) frame) {
  final sw = Stopwatch()..start();
  var i = 1;
  while (sw.elapsedMicroseconds < _warmupMicros) {
    _sink += frame(i++);
  }
  final perBatch = (i * _batchMicros ~/ sw.elapsedMicroseconds).clamp(
    1,
    1 << 30,
  );
  final samples = Float64List(_samples);
  for (var k = 0; k < _samples; k++) {
    sw.reset();
    for (var n = 0; n < perBatch; n++) {
      _sink += frame(i++);
    }
    samples[k] = sw.elapsedMicroseconds / perBatch;
  }
  samples.sort();
  return samples[_samples ~/ 2];
}

// ------------------------------------------------------------------- run --

/// One compiled build of the benchmark and what its rounds measured.
final class _Build {
  _Build(this.label, this.exe);
  final String label;
  final String exe;
  final us = <String, List<double>>{};
  final bytes = <String, int>{};
}

/// Compiles the benchmark (and the baseline), runs the rounds and prints
/// the report.
Future<int> _run(_Options opts) async {
  final top = await Process.run('git', ['rev-parse', '--show-toplevel']);
  if (top.exitCode != 0) {
    stderr.writeln('bench: run it inside the twk repository');
    return 1;
  }
  final root = (top.stdout as String).trim();
  final tmp = await Directory.systemTemp.createTemp('twk_bench_');
  final base = '${tmp.path}/base';
  var worktree = false;
  try {
    final builds = <_Build>[];
    final baseline = opts.baseline;
    if (baseline != null) {
      final sha = await Process.run('git', [
        'rev-parse',
        '--verify',
        '--quiet',
        '--short',
        '$baseline^{commit}',
      ], workingDirectory: root);
      if (sha.exitCode != 0) {
        stderr.writeln('bench: no commit $baseline');
        return 1;
      }
      final add = await Process.run('git', [
        'worktree',
        'add',
        '--detach',
        base,
        baseline,
      ], workingDirectory: root);
      if (add.exitCode != 0) {
        stderr.write(add.stderr);
        return 1;
      }
      worktree = true;
      // the same scenarios on both sides: this file and the scenarios'
      // package, against REF's core
      for (final file in [
        'tool/bench.dart',
        'tool/frame_scenarios/pubspec.yaml',
        'tool/frame_scenarios/lib/frame_scenarios.dart',
      ]) {
        await File('$base/$file').parent.create(recursive: true);
        await File('$root/$file').copy('$base/$file');
      }
      final get = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
        '--offline',
      ], workingDirectory: base);
      if (get.exitCode != 0) {
        stderr.write(get.stdout);
        return 1;
      }
      final exe = await _compile(base, '${tmp.path}/before');
      if (exe == null) {
        stderr.writeln(
          'bench: this tool/bench.dart does not compile against '
          '$baseline: the core API it uses changed since',
        );
        return 1;
      }
      builds.add(_Build('$baseline (${(sha.stdout as String).trim()})', exe));
    }
    final exe = await _compile(root, '${tmp.path}/after');
    if (exe == null) {
      return 1;
    }
    builds.add(_Build('working tree', exe));

    final noise = _Noise();
    // a progress line, overwritten, where stderr is a terminal
    final progress = stderr.hasTerminal;
    for (var r = 0; r < opts.rounds; r++) {
      // alternate the order, so neither build always runs second
      final order = r.isEven ? builds : builds.reversed;
      for (final b in order) {
        if (progress) {
          stderr.write('\x1b[2K\rround ${r + 1}/${opts.rounds} · ${b.label}');
        }
        final before = noise.sample();
        final res = await Process.run(b.exe, opts.childArgs);
        noise.account(before, noise.sample());
        if (res.exitCode != 0) {
          if (progress) {
            stderr.writeln();
          }
          stderr
            ..writeln('bench: ${b.label} failed')
            ..write(res.stderr);
          return 1;
        }
        for (final line in (res.stdout as String).trim().split('\n')) {
          final [name, us, bytes] = line.split('\t');
          (b.us[name] ??= []).add(double.parse(us));
          b.bytes[name] = int.parse(bytes);
        }
      }
    }
    if (progress) {
      stderr.write('\x1b[2K\r');
    }
    _report(opts, builds, noise);
    return 0;
  } finally {
    if (worktree) {
      await Process.run('git', [
        'worktree',
        'remove',
        '--force',
        base,
      ], workingDirectory: root);
    }
    await tmp.delete(recursive: true);
  }
}

/// Compiles `tool/bench.dart` of the checkout at [dir] to [out]; returns
/// [out], or null (after printing why) when it doesn't compile.
Future<String?> _compile(String dir, String out) async {
  final res = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'tool/bench.dart',
    '-o',
    out,
  ], workingDirectory: dir);
  if (res.exitCode != 0) {
    stderr
      ..write(res.stdout)
      ..write(res.stderr);
    return null;
  }
  return out;
}

double _median(List<double> xs) => (List.of(xs)..sort())[xs.length ~/ 2];

/// The spread of [xs] around its median, as a percentage.
String _spread(List<double> xs) {
  final s = List.of(xs)..sort();
  final m = s[s.length ~/ 2];
  return m == 0 ? '' : '±${((s.last - s.first) / m * 50).round()}%';
}

String _num(double us) => us < 10
    ? us.toStringAsFixed(2)
    : (us < 100 ? us.toStringAsFixed(1) : us.toStringAsFixed(0));

String _bytes(int total) =>
    total < 0 ? '-' : (total / _verifyFrames).toStringAsFixed(1);

void _report(_Options opts, List<_Build> builds, _Noise noise) {
  final dart = Platform.version.split(' ').first;
  stdout
    ..writeln(
      'twk_core frame benchmark · ${opts.width}x${opts.height} · AOT · '
      '${opts.rounds} rounds · Dart $dart',
    )
    ..writeln(noise.describe());
  if (builds.length == 2) {
    stdout.writeln('before: ${builds[0].label} · after: ${builds[1].label}');
  }
  stdout.writeln();
  final names = [
    for (final s in frameScenarios)
      if (builds.last.us.containsKey(s.name)) s.name,
  ];
  final slower = <String>[];
  final moreBytes = <String>[];
  if (builds.length == 1) {
    final b = builds.single;
    stdout.writeln(
      '${'scenario'.padRight(13)}${'µs/frame'.padLeft(10)}'
      '${''.padLeft(6)}${'B/frame'.padLeft(10)}',
    );
    for (final n in names) {
      stdout.writeln(
        '${n.padRight(13)}${_num(_median(b.us[n]!)).padLeft(10)}'
        '${_spread(b.us[n]!).padLeft(6)}${_bytes(b.bytes[n]!).padLeft(10)}',
      );
    }
  } else {
    final [before, after] = builds;
    stdout.writeln(
      '${'scenario'.padRight(13)}${'before µs'.padLeft(10)}${''.padLeft(6)}'
      '${'after µs'.padLeft(10)}${''.padLeft(6)}${'ratio'.padLeft(8)}'
      '${'before B'.padLeft(10)}${'after B'.padLeft(10)}',
    );
    for (final n in names) {
      final a = _median(after.us[n]!);
      if (!before.us.containsKey(n)) {
        // a scenario the baseline's core can't run
        stdout.writeln(
          '${n.padRight(13)}${'-'.padLeft(10)}${''.padLeft(6)}'
          '${_num(a).padLeft(10)}${_spread(after.us[n]!).padLeft(6)}'
          '${'-'.padLeft(8)}${'-'.padLeft(10)}'
          '${_bytes(after.bytes[n]!).padLeft(10)}',
        );
        continue;
      }
      final b = _median(before.us[n]!);
      final ratio = a / b;
      if (ratio > _slower) {
        slower.add('$n ×${ratio.toStringAsFixed(2)}');
      }
      if (after.bytes[n]! > before.bytes[n]!) {
        moreBytes.add(n);
      }
      stdout.writeln(
        '${n.padRight(13)}${_num(b).padLeft(10)}'
        '${_spread(before.us[n]!).padLeft(6)}${_num(a).padLeft(10)}'
        '${_spread(after.us[n]!).padLeft(6)}'
        '${'×${ratio.toStringAsFixed(2)}'.padLeft(8)}'
        '${_bytes(before.bytes[n]!).padLeft(10)}'
        '${_bytes(after.bytes[n]!).padLeft(10)}',
      );
    }
    stdout
      ..writeln()
      ..writeln(
        'slower by more than ${((_slower - 1) * 100).round()}%: '
        '${slower.isEmpty ? 'none' : slower.join(', ')}',
      )
      ..writeln(
        'more bytes per frame: '
        '${moreBytes.isEmpty ? 'none' : moreBytes.join(', ')}',
      );
  }
  stdout
    ..writeln()
    ..writeln('scenarios:');
  for (final s in frameScenarios) {
    if (names.contains(s.name)) {
      stdout.writeln('  ${s.name.padRight(12)} ${s.about}');
    }
  }
}

// ----------------------------------------------------------------- noise --

/// What else ran during the rounds (Linux only): the load average, and how
/// busy the SMT siblings of the CPUs this process is pinned to were.
final class _Noise {
  _Noise() {
    final online = sample().keys.toSet();
    final allowed = _allowedCpus();
    if (allowed != null &&
        online.isNotEmpty &&
        allowed.length < online.length) {
      pinned = allowed;
      siblings = {
        for (final c in allowed) ..._siblingsOf(c),
      }.difference(allowed);
    }
  }

  final String? _loadStart = _loadAverage();

  /// The CPUs this process may run on, when fewer than all of them.
  Set<int>? pinned;
  var siblings = <int>{};

  /// The highest share of a round a sibling was busy.
  var siblingBusy = 0.0;

  /// Busy and total jiffies per CPU (empty where /proc/stat isn't there).
  Map<int, (int, int)> sample() {
    final out = <int, (int, int)>{};
    try {
      for (final line in File('/proc/stat').readAsLinesSync()) {
        final m = RegExp(r'^cpu(\d+) (.*)$').firstMatch(line);
        if (m == null) {
          continue;
        }
        final t = m[2]!.trim().split(' ').map(int.parse).toList();
        final total = t.fold(0, (a, b) => a + b);
        // idle and iowait are not busy
        out[int.parse(m[1]!)] = (total - t[3] - t[4], total);
      }
    } on FileSystemException {
      // not Linux
    }
    return out;
  }

  void account(Map<int, (int, int)> before, Map<int, (int, int)> after) {
    for (final c in siblings) {
      final b = before[c];
      final a = after[c];
      if (a == null || b == null || a.$2 == b.$2) {
        continue;
      }
      final busy = (a.$1 - b.$1) / (a.$2 - b.$2);
      if (busy > siblingBusy) {
        siblingBusy = busy;
      }
    }
  }

  String describe() {
    final load = _loadStart == null
        ? ''
        : ' · load $_loadStart → ${_loadAverage()}';
    final p = pinned;
    if (p == null) {
      return 'not pinned to a core: expect noise (taskset -c N)$load';
    }
    final cpus = p.join(',');
    if (siblings.isEmpty) {
      return 'pinned to CPU $cpus$load';
    }
    final pct = (siblingBusy * 100).toStringAsFixed(1);
    final warn = siblingBusy > _siblingBusyLimit
        ? ' — busy: the times are not reliable'
        : '';
    return 'pinned to CPU $cpus · sibling CPU ${siblings.join(',')} '
        'busy up to $pct%$warn$load';
  }

  static String? _loadAverage() {
    try {
      return File('/proc/loadavg').readAsStringSync().split(' ').first;
    } on FileSystemException {
      return null;
    }
  }

  static Set<int>? _allowedCpus() {
    try {
      final line = File('/proc/self/status')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('Cpus_allowed_list:'));
      return _cpuList(line.substring(line.indexOf(':') + 1));
    } on Object {
      return null;
    }
  }

  static Set<int> _siblingsOf(int cpu) {
    try {
      return _cpuList(
        File(
          '/sys/devices/system/cpu/cpu$cpu/topology/thread_siblings_list',
        ).readAsStringSync(),
      );
    } on FileSystemException {
      return {};
    }
  }

  /// "0-3,8,10-11" → {0, 1, 2, 3, 8, 10, 11}
  static Set<int> _cpuList(String s) => {
    for (final part in s.trim().split(','))
      if (part.contains('-'))
        for (
          var c = int.parse(part.split('-')[0]);
          c <= int.parse(part.split('-')[1]);
          c++
        )
          c
      else
        int.parse(part),
  };
}

// --------------------------------------------------------------- options --

final class _Options {
  _Options._(
    this.width,
    this.height,
    this.rounds,
    this.only,
    this.baseline, {
    required this.measure,
  });

  factory _Options.parse(List<String> args) {
    var w = 200;
    var h = 60;
    var rounds = 5;
    Set<String>? only;
    String? baseline;
    var measure = false;
    for (final a in args) {
      final eq = a.indexOf('=');
      final name = eq < 0 ? a : a.substring(0, eq);
      final value = eq < 0 ? null : a.substring(eq + 1);
      switch (name) {
        case '--measure' when value == null:
          measure = true;
        case '--baseline' when value != null && value.isNotEmpty:
          baseline = value;
        case '--rounds' when value != null:
          rounds = int.tryParse(value) ?? 0;
          if (rounds < 1) {
            throw FormatException('bad --rounds: $value');
          }
        case '--size' when value != null:
          final m = RegExp(r'^(\d+)x(\d+)$').firstMatch(value);
          w = m == null ? 0 : int.parse(m[1]!);
          h = m == null ? 0 : int.parse(m[2]!);
          if (w < 40 || h < 10) {
            throw FormatException('bad --size: $value (at least 40x10)');
          }
        case '--only' when value != null:
          only = value.split(',').toSet();
        default:
          throw FormatException('unknown option $a');
      }
    }
    // a baseline's build lacks the scenarios its core can't run
    final known = {for (final s in frameScenarios) s.name};
    final unknown = only?.difference(known) ?? const <String>{};
    if (unknown.isNotEmpty && !measure) {
      throw FormatException(
        'no scenario ${unknown.join(', ')} (there are ${known.join(', ')})',
      );
    }
    return _Options._(w, h, rounds, only, baseline, measure: measure);
  }

  final int width;
  final int height;
  final int rounds;
  final Set<String>? only;
  final String? baseline;
  final bool measure;

  /// What the compiled executables are run with.
  List<String> get childArgs => [
    '--measure',
    '--size=${width}x$height',
    if (only != null) '--only=${only!.join(',')}',
  ];
}
