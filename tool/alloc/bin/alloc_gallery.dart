// What switching pages of the gallery allocates: Down pressed in its list
// of pages, then half a second of frames (the page's motion and the
// shell's dissolve), a step; at the last page, Home. Options and columns
// as bin/alloc.dart's; the unit is a page switch.
//
//   dart run tool/alloc/bin/alloc_gallery.dart [--size=120x36] [--frames=N]
import 'dart:io';

import 'package:gallery/gallery.dart';
import 'package:twk_alloc/app_run.dart';
import 'package:twk_alloc/profiler.dart';
import 'package:twk_alloc/report.dart';

Future<void> main(List<String> args) async {
  final AllocOptions opts;
  try {
    opts = AllocOptions.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 64;
    return;
  }
  final pages = [for (final g in catalog) ...g.pages].length;
  final p = await Profiler.connect();
  final report = AllocReport(opts);
  final run = await AppRun.start(
    galleryApp(route: GalleryRoute.parse('#/text/text')),
    width: opts.width,
    height: opts.height,
  );
  var frames = 0;
  var bytes = 0;
  final sample = await p.measure(
    (i) {
      run.input(i % pages == 0 ? const [0x1B, 0x5B, 0x48] : keyDown);
      return run.pump(const Duration(milliseconds: 500));
    },
    // every page once
    frames: opts.frames ?? pages,
    cpu: opts.cpu,
    warmup: pages,
    counting: () {
      frames = run.frames;
      bytes = run.bytes;
    },
  );
  report
    ..add(
      'gallery-switch',
      sample,
      unit: 'switch',
      frames: run.frames - frames,
      bytesOut: run.bytes - bytes,
    )
    ..end();
  await run.stop();
  await p.close();
  // the apps' bindings may hold a timer still
  exit(exitCode);
}
