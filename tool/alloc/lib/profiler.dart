/// What frames allocate, read from the VM service of this very process: the
/// objects and bytes per frame, by class, and the collections they cost.
///
/// No package: the service is switched on from inside
/// ([Service.controlWebServer]) and spoken to over a WebSocket of
/// `dart:io` by an isolate of its own group, so of its own heap
/// (`src/service_client.dart`): reading the profile allocates nothing
/// here. It runs under `dart run` (JIT) only — an AOT executable has no
/// service — so the numbers are those of optimised JIT code after a
/// warm-up: what escapes is allocated there as in AOT code.
///
/// The VM's profile counts the objects in the heap, the garbage not yet
/// collected included. So the frames are counted in windows: a full
/// collection, a reading, the frames, a reading; a window during which a
/// collection ran is dropped and the next is half as long. The
/// collections are counted in a second run of as many frames, unprofiled.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'dart:isolate';

import 'src/service_client.dart' show vmClasses;

/// One class's share of a [Sample]: instances and bytes allocated.
typedef ClassAllocs = ({String name, int objects, int bytes});

/// One function's share of a [Sample]'s CPU samples.
typedef CpuShare = ({String name, int self, int inclusive});

/// What [Profiler.measure] measured.
final class Sample {
  Sample({
    required this.frames,
    required this.objects,
    required this.bytes,
    required this.classes,
    required this.gcFrames,
    required this.scavenges,
    required this.markSweeps,
    required this.gcMicros,
    required this.maxPauseMicros,
    required this.micros,
    required this.steps,
    required this.dropped,
    required this.vmBytes,
    this.cpuSamples = 0,
    this.cpu = const [],
    this.next = 1,
  });

  /// The number of the step after the last one run: where a run that goes
  /// on as these steps did starts ([Profiler.trace]'s `from`).
  final int next;

  /// The frames (or events, or steps) whose allocations were counted.
  final int frames;

  /// Objects and bytes they allocated, the VM's own classes (the JIT's
  /// code) left out.
  final int objects;
  final int bytes;

  /// The classes allocated, the most bytes first.
  final List<ClassAllocs> classes;

  /// The frames of the unprofiled run, and the new-space (scavenges) and
  /// old-space (mark-sweeps, compactions) collections during it, their
  /// total time and the longest.
  final int gcFrames;
  final int scavenges;
  final int markSweeps;
  final double gcMicros;
  final double maxPauseMicros;

  /// The wall time of the unprofiled run, JIT.
  final int micros;

  /// Every step run once counting started ([Profiler.measure]'s
  /// `counting`), of both runs and dropped windows.
  final int steps;

  /// Windows dropped because a collection ran during them.
  final int dropped;

  /// Bytes of the VM's own classes over the [frames]: code compiled,
  /// inline caches, type objects — the JIT's, mostly, so not in [bytes].
  final int vmBytes;

  /// The CPU samples taken during the unprofiled run (`cpu` of
  /// [Profiler.measure]), and the functions they were in, the most
  /// inclusive first: `self` counts the samples in the function itself,
  /// `inclusive` those in it or what it called.
  final int cpuSamples;
  final List<CpuShare> cpu;

  double get bytesPerFrame => bytes / frames;
  double get objectsPerFrame => objects / frames;
  double get microsPerFrame => micros / gcFrames;

  Map<String, Object?> toJson({int top = 12}) => {
    'frames': frames,
    'bytesPerFrame': bytesPerFrame,
    'objectsPerFrame': objectsPerFrame,
    'gcFrames': gcFrames,
    'scavenges': scavenges,
    'markSweeps': markSweeps,
    'gcMillis': gcMicros / 1000,
    'maxPauseMillis': maxPauseMicros / 1000,
    'microsPerFrame': microsPerFrame,
    'droppedWindows': dropped,
    'vmBytesPerFrame': vmBytes / frames,
    if (cpuSamples > 0) ...{
      'cpuSamples': cpuSamples,
      'cpu': [
        for (final c in cpu.take(40))
          {'function': c.name, 'self': c.self, 'inclusive': c.inclusive},
      ],
    },
    'classes': [
      for (final c in classes.take(top))
        {'class': c.name, 'objects': c.objects, 'bytes': c.bytes},
    ],
  };
}

/// What measures the code of this isolate, through the VM service.
final class Profiler {
  Profiler._(this._replies, this._commands, this._helper, this._errors);

  /// Switches the service on (it may be on already, as under
  /// `--observe`) and starts the isolate that speaks to it.
  static Future<Profiler> connect() async {
    final info = await Service.controlWebServer(
      enable: true,
      silenceOutput: true,
    );
    final uri = info.serverWebSocketUri;
    if (uri == null) {
      throw StateError(
        'no VM service: run under `dart run` (JIT), not as an executable',
      );
    }
    final script = await Isolate.resolvePackageUri(
      Uri.parse('package:twk_alloc/src/service_client.dart'),
    );
    final port = ReceivePort();
    final replies = _Replies(port);
    // an error of the other side ends this one: it waits for no answer
    final errors = RawReceivePort((Object? e) {
      throw StateError('the profiler isolate failed: $e');
    });
    final helper = await Isolate.spawnUri(
      script!,
      [uri.toString(), Service.getIsolateId(Isolate.current)!],
      port.sendPort,
      onError: errors.sendPort,
    );
    final commands = (await replies.next())! as SendPort;
    final p = Profiler._(replies, commands, helper, errors);
    await p._calibrate();
    return p;
  }

  /// What a window of no steps counts, by class: the service's own work
  /// on this isolate, taken off every window (the least of a few, so
  /// nothing of the program's is).
  final _overhead = <String, (int, int)>{};

  Future<void> _calibrate() async {
    for (var k = 0; k < 6; k++) {
      await _ask<bool>('mark');
      final r = await _ask<List<Object?>>('take');
      final seen = <String, (int, int)>{};
      for (var j = 1; j < r.length; j += 3) {
        seen[r[j]! as String] = (r[j + 1]! as int, r[j + 2]! as int);
      }
      if (k == 0) {
        // the first runs code not compiled yet
        continue;
      }
      if (k == 1) {
        _overhead.addAll(seen);
        continue;
      }
      for (final name in _overhead.keys.toList()) {
        final (o, b) = _overhead[name]!;
        final (so, sb) = seen[name] ?? (0, 0);
        _overhead[name] = (o < so ? o : so, b < sb ? b : sb);
      }
    }
  }

  final _Replies _replies;
  final SendPort _commands;
  final Isolate _helper;
  final RawReceivePort _errors;

  Future<T> _ask<T>(String command) {
    _commands.send(command);
    return _replies.next().then((r) => r as T);
  }

  /// Runs [step] for [warmup] steps (and at least [warmupMicros])
  /// uncounted, then for [frames] steps counted in windows, then [frames]
  /// more for the collections and the time. [step] may be asynchronous:
  /// what runs while it is awaited (timers, microtasks) is counted too.
  /// [counting] is called once the warm-up is over: where a caller zeroes
  /// counters of its own, which then cover [Sample.steps].
  Future<Sample> measure(
    FutureOr<void> Function(int i) step, {
    required int frames,
    int warmup = 200,
    int warmupMicros = 1500000,
    void Function()? counting,
    bool cpu = false,
  }) async {
    var i = 1;
    var steps = 0;
    Future<void> run(int n) async {
      for (var k = 0; k < n; k++) {
        final r = step(i++);
        if (r is Future<void>) {
          await r;
        }
      }
      steps += n;
    }

    final sw = Stopwatch()..start();
    while (i <= warmup || sw.elapsedMicroseconds < warmupMicros) {
      final r = step(i++);
      if (r is Future<void>) {
        await r;
      }
    }
    counting?.call();

    // the allocations, window by window
    final totals = <String, (int, int)>{};
    var counted = 0;
    var dropped = 0;
    var window = frames;
    while (counted < frames) {
      final n = window < frames - counted ? window : frames - counted;
      await _ask<bool>('mark');
      await run(n);
      final r = await _ask<List<Object?>>('take');
      if (r[0]! as bool && n > 1) {
        dropped++;
        window = n ~/ 2;
        continue;
      }
      for (var k = 1; k < r.length; k += 3) {
        final name = r[k]! as String;
        final (o, b) = totals[name] ?? (0, 0);
        final (vo, vb) = _overhead[name] ?? (0, 0);
        totals[name] = (
          o + (r[k + 1]! as int) - vo,
          b + (r[k + 2]! as int) - vb,
        );
      }
      counted += n;
    }
    final vm = totals.remove(vmClasses) ?? (0, 0);
    final classes = [
      for (final MapEntry(key: name, value: (o, b)) in totals.entries)
        if (o > 0) (name: name, objects: o, bytes: b),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));

    // the collections and the time, unprofiled
    final before = await _ask<List<Object?>>('heaps');
    await _ask<List<Object?>>('pauses');
    if (cpu) {
      await _ask<bool>('cpu-clear');
    }
    sw.reset();
    await run(frames);
    final micros = sw.elapsedMicroseconds;
    final profile = cpu ? await _ask<List<Object?>>('cpu-take') : null;
    final after = await _ask<List<Object?>>('heaps');
    final pauses = await _ask<List<Object?>>('pauses');
    int d(int k) => (after[k]! as int) - (before[k]! as int);
    var maxPause = 0.0;
    for (final p in pauses) {
      if ((p! as double) > maxPause) {
        maxPause = p as double;
      }
    }
    return Sample(
      frames: counted,
      objects: classes.fold(0, (s, c) => s + c.objects),
      bytes: classes.fold(0, (s, c) => s + c.bytes),
      classes: classes,
      gcFrames: frames,
      scavenges: d(0),
      markSweeps: d(2),
      gcMicros: (d(1) + d(3)).toDouble(),
      maxPauseMicros: maxPause,
      micros: micros,
      steps: steps,
      dropped: dropped,
      vmBytes: vm.$2,
      next: i,
      cpuSamples: profile == null ? 0 : profile[0]! as int,
      cpu: [
        if (profile != null)
          for (var k = 1; k < profile.length; k += 3)
            (
              name: profile[k]! as String,
              self: profile[k + 1]! as int,
              inclusive: profile[k + 2]! as int,
            ),
      ],
    );
  }

  /// Runs [step] for [steps] steps with the allocations of the classes
  /// [classes] traced, and returns where they were allocated: by class
  /// and stack (`A.f < B.g`, the innermost of the program's frames first,
  /// the `dart:` frame that allocated before them), how many objects, the
  /// most first. The steps are numbered on from [from].
  Future<List<({String cls, int count, String stack})>> trace(
    List<String> classes,
    FutureOr<void> Function(int i) step, {
    required int steps,
    int from = 1,
  }) async {
    await _ask<bool>('trace-on:${classes.join(',')}');
    for (var i = from; i < from + steps; i++) {
      final r = step(i);
      if (r is Future<void>) {
        await r;
      }
    }
    final r = await _ask<List<Object?>>('trace-take');
    return [
      for (var k = 0; k < r.length; k += 3)
        (
          cls: r[k]! as String,
          count: r[k + 1]! as int,
          stack: r[k + 2]! as String,
        ),
    ];
  }

  /// Ends the other isolate and switches the service off: neither keeps
  /// the process alive then.
  Future<void> close() async {
    _commands.send('close');
    _replies.close();
    _errors.close();
    _helper.kill();
    await Service.controlWebServer(silenceOutput: true);
  }
}

/// The messages of a port, one at a time, in order.
final class _Replies {
  _Replies(this._port) {
    _port.listen((m) {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete(m);
      } else {
        _early.add(m);
      }
    });
  }

  final ReceivePort _port;
  final _waiting = Queue<Completer<Object?>>();
  final _early = Queue<Object?>();

  Future<Object?> next() {
    if (_early.isNotEmpty) {
      return Future.value(_early.removeFirst());
    }
    final c = Completer<Object?>();
    _waiting.add(c);
    return c.future;
  }

  void close() => _port.close();
}
