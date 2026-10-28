/// The other side of `Profiler`: an isolate of a group of its own (so of a
/// heap of its own) that speaks to the VM service for the isolate it
/// measures, which allocates nothing for it but the port messages.
///
/// The allocation profile counts the objects in the heap, garbage not yet
/// collected included: between a full collection and a reading with no
/// collection in between, the difference is exactly what was allocated.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// The name the VM's own classes are summed under.
const vmClasses = '(vm)';

/// Started by `Isolate.spawnUri` with the service's WebSocket URI and the
/// id of the isolate it measures; [reply] gets this side's port, then an
/// answer to each command.
Future<void> main(List<String> args, SendPort reply) async {
  final client = _Client(await WebSocket.connect(args[0]), args[1]);
  await client.call('streamListen', {'streamId': 'GC'});
  final commands = ReceivePort();
  reply.send(commands.sendPort);
  await for (final Object? c in commands) {
    switch (c) {
      case 'mark':
        await client.mark();
        reply.send(true);
      case 'take':
        reply.send(await client.take());
      case 'heaps':
        reply.send(await client.heaps());
      case 'pauses':
        reply.send(client.takePauses());
      case 'cpu-clear':
        // off by default: on, a sample every 250 µs
        await client.call('setFlag', {
          'name': 'profile_period',
          'value': '250',
        });
        await client.call('setFlag', {'name': 'profiler', 'value': 'true'});
        await client.call('clearCpuSamples', {'isolateId': args[1]});
        reply.send(true);
      case 'cpu-take':
        reply.send(await client.cpu());
      case final String c when c.startsWith('trace-on:'):
        await client.traceOn(c.substring('trace-on:'.length).split(','));
        reply.send(true);
      case 'trace-take':
        reply.send(await client.traces());
      case 'close':
        commands.close();
        await client.close();
    }
  }
}

final class _Client {
  _Client(this._ws, this._isolate) {
    _ws.listen(_receive);
  }

  final WebSocket _ws;
  final String _isolate;
  var _id = 0;
  final _pending = <String, Completer<Map<String, Object?>>>{};
  Map<String, (int, int)> _marked = const {};
  List<int> _markedHeaps = const [];

  // the cumulative GC time of each space at the last event of it, and the
  // pauses since [takePauses]
  final _last = <String, double>{};
  final _pauses = <double>[];

  void _receive(Object? message) {
    final j = jsonDecode(message! as String) as Map<String, Object?>;
    if (j['method'] == 'streamNotify') {
      final e =
          (j['params']! as Map<String, Object?>)['event']!
              as Map<String, Object?>;
      final iso = e['isolate'] as Map<String, Object?>?;
      if (e['kind'] == 'GC' && (iso == null || iso['id'] == _isolate)) {
        for (final space in const ['new', 'old']) {
          final heap = e[space] as Map<String, Object?>?;
          if (heap == null) {
            continue;
          }
          final t = (heap['time']! as num).toDouble();
          final before = _last[space];
          if (before != null && t > before) {
            _pauses.add((t - before) * 1e6);
          }
          _last[space] = t;
        }
      }
      return;
    }
    final c = _pending.remove('${j['id']}');
    if (c == null) {
      return;
    }
    if (j['error'] case final Map<String, Object?> error) {
      c.completeError(
        StateError('VM service: ${error['message']} ${error['data']}'),
      );
    } else {
      c.complete(j['result']! as Map<String, Object?>);
    }
  }

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    final id = '${++_id}';
    final c = _pending[id] = Completer<Map<String, Object?>>();
    _ws.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return c.future;
  }

  /// The objects and bytes in the heap by class, after a full collection
  /// when [gc]. The VM's own classes (code, inline caches, type objects:
  /// the JIT's work more than the program's) are summed as [vmClasses]; a
  /// closure's `Context` is the program's.
  Future<Map<String, (int, int)>> _profile({bool gc = false}) async {
    final p = await call('getAllocationProfile', {
      'isolateId': _isolate,
      'gc': ?(gc ? true : null),
    });
    final out = <String, (int, int)>{};
    for (final m
        in (p['members']! as List<Object?>).cast<Map<String, Object?>>()) {
      final cls = m['class']! as Map<String, Object?>;
      final name = '${cls['name']}';
      final key = _isVm(cls, name) ? vmClasses : name;
      final (o, b) = out[key] ?? (0, 0);
      out[key] = (
        o + (m['instancesAccumulated']! as int),
        b + (m['accumulatedSize']! as int),
      );
    }
    return out;
  }

  static bool _isVm(Map<String, Object?> cls, String name) =>
      name != 'Context' && (cls['library'] == null || _vm.contains(name));

  static const _vm = {
    'Instructions',
    'ICData',
    'ObjectPool',
    'PcDescriptors',
    'CodeSourceMap',
    'CompressedStackMaps',
    'Code',
    'Function',
    'Field',
    'ExceptionHandlers',
    'LocalVarDescriptors',
    'MegamorphicCache',
    'SubtypeTestCache',
    'ContextScope',
    'ClosureData',
    'TypeParameters',
    'TypeArguments',
    '_Type',
    '_TypeParameter',
    '_FunctionType',
    '_RecordType',
    'UnlinkedCall',
    'MonomorphicSmiableCall',
    'SingleTargetCache',
    'WeakArray',
  };

  /// The collections of the new and the old space, and their total time
  /// in µs: `[scavenges, µs, mark-sweeps, µs]`.
  Future<List<int>> heaps() async {
    final iso = await call('getIsolate', {'isolateId': _isolate});
    final heaps = iso['_heaps']! as Map<String, Object?>;
    return [
      for (final space in const ['new', 'old']) ...[
        (heaps[space]! as Map<String, Object?>)['collections']! as int,
        (((heaps[space]! as Map<String, Object?>)['time']! as num) * 1e6)
            .round(),
      ],
    ];
  }

  Future<void> mark() async {
    _marked = await _profile(gc: true);
    _markedHeaps = await heaps();
  }

  /// What was allocated since [mark], as `[collected, name, objects, bytes,
  /// name, …]`: `collected` is whether a collection ran since, which makes
  /// the counts short of the truth.
  Future<List<Object>> take() async {
    final h = await heaps();
    final now = await _profile();
    final out = <Object>[h[0] != _markedHeaps[0] || h[2] != _markedHeaps[2]];
    for (final MapEntry(key: name, value: (o, b)) in now.entries) {
      final (mo, mb) = _marked[name] ?? (0, 0);
      if (o > mo) {
        out.addAll([name, o - mo, b - mb]);
      }
    }
    return out;
  }

  /// Where the samples since `cpu-clear` were: `[samples, name, self,
  /// inclusive, …]`, the most inclusive first, the functions of the
  /// program's libraries only (and the core's `dart:` ones they call).
  Future<List<Object>> cpu() async {
    final r = await call('getCpuSamples', {
      'isolateId': _isolate,
      'timeOriginMicros': 0,
      'timeExtentMicros': 1 << 52,
    });
    final functions = (r['functions']! as List<Object?>)
        .cast<Map<String, Object?>>();
    String nameOf(int i) {
      final f = functions[i]['function']! as Map<String, Object?>;
      final name = '${f['name']}';
      final owner = f['owner'];
      if (owner is Map<String, Object?> && owner['type'] == '@Class') {
        return '${owner['name']}.$name';
      }
      return name;
    }

    final self = <int, int>{};
    final incl = <int, int>{};
    final samples = (r['samples']! as List<Object?>)
        .cast<Map<String, Object?>>();
    for (final sample in samples) {
      final stack = (sample['stack']! as List<Object?>).cast<int>();
      if (stack.isEmpty) {
        continue;
      }
      self[stack.first] = (self[stack.first] ?? 0) + 1;
      for (final f in stack.toSet()) {
        incl[f] = (incl[f] ?? 0) + 1;
      }
    }
    final order = incl.keys.toList()
      ..sort((a, b) => incl[b]!.compareTo(incl[a]!));
    return [
      samples.length,
      for (final f in order.take(400)) ...[nameOf(f), self[f] ?? 0, incl[f]!],
    ];
  }

  /// The classes [traceOn] traces, by id, and their names.
  final _traced = <String, String>{};

  /// Starts recording a stack for each object of the classes [names]
  /// allocated (the VM's allocation tracing); a name of no class loaded
  /// is left out.
  Future<void> traceOn(List<String> names) async {
    // the stacks are the CPU profiler's samples: without it on, the VM
    // has nowhere to put them (and crashes)
    await call('setFlag', {'name': 'profiler', 'value': 'true'});
    final p = await call('getAllocationProfile', {'isolateId': _isolate});
    for (final m
        in (p['members']! as List<Object?>).cast<Map<String, Object?>>()) {
      final c = m['class']! as Map<String, Object?>;
      final name = '${c['name']}';
      if (names.contains(name)) {
        _traced['${c['id']}'] = name;
      }
    }
    for (final id in _traced.keys) {
      await call('setTraceClassAllocation', {
        'isolateId': _isolate,
        'classId': id,
        'enable': true,
      });
    }
  }

  /// The stacks the traced classes were allocated at since [traceOn], and
  /// tracing off: `[class, count, stack, …]`, the most first, a stack the
  /// [_frames] innermost frames of the program's libraries (a frame of
  /// `dart:` before them named once, as what allocated).
  Future<List<Object>> traces() async {
    final counts = <(String, String), int>{};
    for (final MapEntry(key: id, value: name) in _traced.entries) {
      final r = await call('getAllocationTraces', {
        'isolateId': _isolate,
        'classId': id,
      });
      await call('setTraceClassAllocation', {
        'isolateId': _isolate,
        'classId': id,
        'enable': false,
      });
      final functions = (r['functions']! as List<Object?>)
          .cast<Map<String, Object?>>();
      String nameOf(int i) {
        final f = functions[i]['function']! as Map<String, Object?>;
        final owner = f['owner'];
        final n = '${f['name']}';
        return owner is Map<String, Object?> && owner['type'] == '@Class'
            ? '${owner['name']}.$n'
            : n;
      }

      bool sdk(int i) => '${functions[i]['resolvedUrl']}'.startsWith('dart:');
      for (final sample
          in (r['samples']! as List<Object?>).cast<Map<String, Object?>>()) {
        final stack = (sample['stack']! as List<Object?>).cast<int>();
        final at = stack.indexWhere((f) => !sdk(f));
        if (at < 0) {
          continue;
        }
        final key = [
          if (at > 0) nameOf(stack[at - 1]),
          for (final f in stack.skip(at).where((f) => !sdk(f)).take(_frames))
            nameOf(f),
        ].join(' < ');
        counts[(name, key)] = (counts[(name, key)] ?? 0) + 1;
      }
    }
    _traced.clear();
    final order = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return [
      for (final k in order.take(200)) ...[k.$1, counts[k]!, k.$2],
    ];
  }

  /// How many frames of the program a traced stack shows.
  static const _frames = 5;

  List<double> takePauses() {
    final p = List.of(_pauses);
    _pauses.clear();
    return p;
  }

  Future<void> close() => _ws.close();
}
