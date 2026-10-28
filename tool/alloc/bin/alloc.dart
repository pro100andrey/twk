// What a frame allocates: objects and bytes per frame (or per event), the
// classes they are, and the collections they cost, for the scenarios of
// tool/bench.dart and for apps of twk and twk_rich.
//
//   dart pub get                         # once, at the root: the workspace
//   dart run tool/alloc/bin/alloc.dart [--size=200x60] [--frames=N]
//       [--top=8] [--only=NAME,...] [--json=PATH] [--cpu]
//       [--trace=CLASS,...]
//
// The gallery's own scenario is bin/alloc_gallery.dart: the gallery is a
// big program of its own, and a page being edited stops only that one.
//
// Each scenario is warmed up (at least 200 steps and 1.5 s, so the hot code
// is optimised). Then its steps are counted in windows: a full collection,
// a reading of the VM's allocation profile, the steps, a reading — the
// difference is what they allocated, since the profile counts garbage not
// yet collected; a window a collection ran in is dropped and the next is
// half as long (lib/profiler.dart). Then as many steps run unprofiled, for
// the collections and the time. JIT, not AOT (an executable has no VM
// service): what escapes is allocated in both. Counts don't depend on the
// machine's load; the µs column does, and is JIT time — tool/bench.dart is
// the clock. The VM's own classes (code, inline caches, type objects) are
// summed apart as (vm): the JIT's work more than the program's.
//
// Columns: B/unit and obj/unit allocated per frame (per event for `keys`
// and `mouse-flood`), B out/fr the bytes written per frame written,
// fr/unit frames written per unit; then, of the unprofiled run: scav/kst
// and old/kst the new- and old-space collections per 1000 steps (a step
// is a frame, a burst of 2000 events for `keys`, of 100 for
// `mouse-flood`), gc ms/kst their time, max ms the longest one, µs/unit
// the wall time. With --trace=CLASS,... the scenario then runs 200 steps
// more (as it went on) with the VM's allocation tracing of those classes,
// and lists where their objects were allocated: a stack a line, the
// innermost of the program's frames first and the dart: frame that
// allocated before them, with the objects a unit (`_List`, `_Int32List`,
// `_ArrayIterator`: the class names the profile prints). An app runs on
// a synchronous clock of the tool's own (lib/sync_clock.dart): its steps
// cost what the app does, not a test clock's turns of the event loop;
// `app-idle`, where nothing changes, shows what is left of the tool's,
// some 20 B a frame. Below each line, the classes allocated the most
// bytes per unit, with bytes/objects.
import 'dart:io';

import 'package:twk_alloc/app_scenarios.dart';
import 'package:twk_alloc/profiler.dart';
import 'package:twk_alloc/report.dart';
import 'package:twk_frame_scenarios/frame_scenarios.dart';

var _sink = 0;

Future<void> main(List<String> args) async {
  final AllocOptions opts;
  try {
    opts = AllocOptions.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 64;
    return;
  }
  final p = await Profiler.connect();
  final report = AllocReport(opts);
  for (final s in frameScenarios) {
    if (!opts.wants(s.name)) {
      continue;
    }
    final frame = s.start(FrameRig(opts.width, opts.height));
    var bytes = 0;
    final sample = await p.measure(
      (i) => bytes += frame(i),
      frames: opts.frames ?? 2000,
      cpu: opts.cpu,
      warmup: 500,
      counting: () => bytes = 0,
    );
    final events = s.name == 'keys';
    report.add(
      s.name,
      sample,
      unit: events ? 'event' : 'frame',
      perStep: events ? 2000 : 1,
      frames: s.write ? sample.steps : null,
      bytesOut: s.write ? bytes : null,
    );
    if (opts.trace.isNotEmpty) {
      const steps = 200;
      report.traces(
        await p.trace(
          opts.trace,
          (i) => bytes += frame(i),
          steps: steps,
          from: sample.next,
        ),
        steps,
        perStep: events ? 2000 : 1,
      );
    }
    _sink += bytes;
  }
  for (final s in appScenarios) {
    if (!opts.wants(s.name)) {
      continue;
    }
    final (run, step) = await s.start(opts.width, opts.height);
    var frames = 0;
    var bytes = 0;
    final sample = await p.measure(
      step,
      frames: opts.frames ?? s.steps,
      cpu: opts.cpu,
      warmup: 100,
      counting: () {
        frames = run.frames;
        bytes = run.bytes;
      },
    );
    report.add(
      s.name,
      sample,
      unit: s.unit,
      perStep: s.perStep,
      frames: run.frames - frames,
      bytesOut: run.bytes - bytes,
    );
    if (opts.trace.isNotEmpty) {
      final steps = s.steps < 200 ? s.steps : 200;
      report.traces(
        await p.trace(opts.trace, step, steps: steps, from: sample.next),
        steps,
        perStep: s.perStep,
      );
    }
    await run.stop();
  }
  report.end();
  if (_sink == 42) {
    stdout.writeln();
  }
  await p.close();
  // the apps' bindings may hold a timer still
  exit(exitCode);
}
