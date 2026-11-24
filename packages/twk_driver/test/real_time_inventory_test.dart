// What stays on real time (part 4.4 of DESIGN.md): every timer, timeout and
// stopwatch in the code of twk_core, twk_term and twk is held to a table,
// so that a new one cannot slip in unclassified.
//
// A driven app runs in a zone whose timers go to the clock the driver
// moves. A timer of an I/O adapter made there would wait for a clock that
// stands still, so each adapter makes its timers where it was made, or in
// the root zone; the app's own (frames, animations, a view's timeout) are
// driven on purpose. A new `Timer(`, `.timeout(`, `Future.delayed(`,
// `Stopwatch(`, `createTimer(` or `createPeriodicTimer(` in those
// libraries fails here until it is classified, and a classified one that is
// gone fails too, so the table does not go stale.
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Where a timer is made, and so whose time it keeps.
enum Kind {
  /// A root-zone (or captured-zone) timer made by an I/O adapter: real
  /// time, whichever zone calls it.
  real,

  /// Made in the zone the adapter opened in, before an app's zone exists:
  /// real time, as the terminal opens on it.
  openZone,

  /// The app's own, driven on purpose: its time is app time, and the app
  /// is not quiet while it runs.
  driven,

  /// A stopwatch that measures what a step cost, never app time.
  measure,

  /// The port itself: the system clock's timers, or the driven clock's
  /// wake-up in the root zone.
  port,
}

/// A line of code that makes a timer, as the table knows it: [code] is a
/// part of it, [kind] and [why] say what it is.
final class Entry {
  const Entry(this.code, this.kind, this.why);
  final String code;
  final Kind kind;
  final String why;
}

/// The table: by file, below `packages/`.
const _table = <String, List<Entry>>{
  'twk_core/lib/src/clock.dart': [
    Entry('Stopwatch()..start()', Kind.port, 'the system clock'),
    Entry('Timer(after, callback)', Kind.port, 'the system clock'),
    Entry('Timer.periodic(every, callback)', Kind.port, 'the system clock'),
  ],
  'twk_core/lib/src/app.dart': [
    Entry(
      '_settleTimer = Zone.root.createTimer',
      Kind.real,
      'a turn of the event loop, not a time of the app',
    ),
    Entry(
      'Zone.root.createTimer(Duration.zero, settled.complete)',
      Kind.real,
      'a turn of the event loop, not a time of the app',
    ),
    Entry('_statsClock = Stopwatch()', Kind.measure, 'frame cost'),
  ],
  'twk_core/lib/src/platform/io.dart': [
    Entry(
      'tmux.exitCode.timeout(within)',
      Kind.openZone,
      'the probe asks tmux whether its pane allows passthrough',
    ),
  ],
  'twk_core/lib/src/platform/log_server.dart': [
    Entry('Zone.root.createTimer(_tokenTimeout', Kind.real, 'a client waits'),
  ],
  'twk_core/lib/src/terminal/trace.dart': [
    Entry('clock ?? (Stopwatch()', Kind.measure, 'the trace line'),
    Entry('Zone.root.createTimer(Duration.zero, _drainLater)', Kind.real, ''),
  ],
  'twk_core/lib/src/terminal/posix_output.dart': [
    Entry('waited ??= Stopwatch()', Kind.measure, 'a write waits for a tty'),
    Entry('_zone.createTimer(', Kind.real, 'the zone the output was opened in'),
  ],
  'twk_core/lib/src/terminal/socket.dart': [
    Entry('link._welcome.future.timeout(', Kind.openZone, 'open'),
    Entry(
      '_socket.close().timeout(',
      Kind.real,
      "close's guard: the link's zone",
    ),
    Entry(
      'refused.future.timeout(',
      Kind.openZone,
      'a refusal, before the app',
    ),
    Entry('Timer(helloTimeout', Kind.openZone, 'hello, before the app'),
  ],
  'twk_core/lib/src/terminal/terminal.dart': [
    Entry('final clock = Stopwatch()', Kind.measure, 'the probe'),
    Entry('round.future.timeout(', Kind.openZone, 'the probe'),
    Entry(
      'Timer.periodic(refresh',
      Kind.driven,
      "the app's own refresh of a terminal state",
    ),
    Entry('_lateProbeTimer = Timer(', Kind.openZone, 'the late probe'),
    Entry('_pasteTimer = Timer(', Kind.openZone, 'the paste timeout'),
    Entry('_escTimer = Timer(', Kind.openZone, 'the escape timeout'),
    Entry('asked!.future.timeout(', Kind.real, "resume's cursor wait"),
    Entry('_realZone.createTimer(', Kind.real, "resume's late cursor"),
    Entry('flush().timeout(_closeBlindLimit', Kind.real, "close's guard"),
    Entry('flushed.timeout(_closeFlushLimit', Kind.real, "close's guard"),
  ],
  'twk_term/lib/src/pty/pty.dart': [
    Entry('Zone.root.createTimer(_hangUpGrace', Kind.real, 'hang-up grace'),
    // two sites: the end of a hosted program and `_reapKilled`
    Entry('Zone.root.createPeriodicTimer(', Kind.real, 'the reapers'),
    Entry('taken = Stopwatch()', Kind.measure, "the I/O isolate's poll"),
  ],
  'twk_term/lib/src/view/render_terminal.dart': [
    Entry(
      '_syncTimer = Timer(',
      Kind.driven,
      "a view's synchronized-update timeout is app time",
    ),
  ],
  'twk/lib/src/debug/frame_overlay.dart': [
    Entry('_aloneWatch = Stopwatch()', Kind.measure, 'overlay cost'),
    Entry('_layoutWatch = Stopwatch()', Kind.measure, 'overlay cost'),
    Entry('_paintWatch = Stopwatch()', Kind.measure, 'overlay cost'),
  ],
  'twk/lib/src/binding/driven_clock.dart': [
    Entry(
      '_wake = Zone.root.createTimer',
      Kind.port,
      'what is due now runs by itself',
    ),
  ],
  'twk/lib/src/binding/app_binding.dart': [
    Entry(
      'Zone.root.createTimer(Duration.zero, done.complete)',
      Kind.real,
      'ext.twk.clock waits for the event loop to turn',
    ),
    Entry(
      '_scheduledTimer = Zone.root.createTimer',
      Kind.real,
      'twk.scheduled: once per turn of the event loop, not a time of the app',
    ),
    Entry(
      '_logTimer ??= Zone.root.createTimer',
      Kind.real,
      'twk.log: once per turn of the event loop, not a time of the app',
    ),
  ],
};

final _timers = RegExp(
  r'(?<![A-Za-z])(Timer(\.periodic|\.run)?|Future\.delayed|Stopwatch)\('
  r'|\.timeout\(|createTimer\(|createPeriodicTimer\(',
);

Future<Directory> _lib(String package) async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:$package/$package.dart'),
  );
  return File.fromUri(uri!).parent;
}

/// Each line of the code of the three packages that makes a timer, as
/// `package/lib/...: line`.
Future<List<(String, String)>> _hits() async {
  final hits = <(String, String)>[];
  for (final package in ['twk_core', 'twk_term', 'twk']) {
    final lib = await _lib(package);
    for (final file in lib.listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final relative =
          '$package/lib/${file.path.substring(lib.path.length + 1)}';
      for (final line in file.readAsLinesSync()) {
        final text = line.trim();
        if (!text.startsWith('//') && _timers.hasMatch(text)) {
          hits.add((relative, text));
        }
      }
    }
  }
  return hits;
}

void main() {
  test('every timer in the code is in the table, and every entry of the '
      'table is in the code', () async {
    final hits = await _hits();
    final unclassified = <String>[];
    final used = <Entry, int>{};
    for (final (file, text) in hits) {
      final entry = (_table[file] ?? const <Entry>[])
          .where((e) => text.contains(e.code))
          .firstOrNull;
      if (entry == null) {
        unclassified.add('$file: $text');
      } else {
        used[entry] = (used[entry] ?? 0) + 1;
      }
    }
    expect(
      unclassified,
      isEmpty,
      reason:
          'a timer that is not in the table of part 4.4 of DESIGN.md: an '
          'adapter makes its timers in a zone it captured, or in Zone.root '
          "(`Kind.real`); an app's own are driven (`Kind.driven`). Put it "
          'in _table with its kind, and say why.',
    );
    final stale = [
      for (final MapEntry(:key, :value) in _table.entries)
        for (final e in value)
          if (!used.containsKey(e)) '$key: ${e.code}',
    ];
    expect(stale, isEmpty, reason: 'entries the code no longer has');
  });

  test('the pty makes its timers in the root zone: the '
      'reapers twice, the grace once', () async {
    final lib = await _lib('twk_term');
    final text = File('${lib.path}/src/pty/pty.dart').readAsStringSync();
    expect(
      RegExp(r'Zone\.root\.createPeriodicTimer\(').allMatches(text),
      hasLength(2),
    );
    expect(RegExp(r'Zone\.root\.createTimer\(').allMatches(text), hasLength(1));
  });
}
