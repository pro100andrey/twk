// THROWAWAY (task web-check-windows-cause): runs web_check's twk case
// many times, [_lanes] at once, and says for each run its lane, outcome and
// time, and the stage a failed one stopped at. Not for main.
import 'dart:convert';
import 'dart:io';

const _lanes = 3;
const _perLane = 10;

Future<void> main() async {
  final failed = <String>[];
  await Future.wait([
    for (var lane = 1; lane <= _lanes; lane++) _lane(lane, failed),
  ]);
  stdout.writeln('failed: ${failed.length} of ${_lanes * _perLane}');
  if (failed.isNotEmpty) {
    stdout.writeln(failed.join('\n'));
    exitCode = 1;
  }
}

Future<void> _lane(int lane, List<String> failed) async {
  for (var i = 1; i <= _perLane; i++) {
    final watch = Stopwatch()..start();
    final r = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        'tool/web_check.dart',
        'twk',
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final out = '${r.stdout}${r.stderr}';
    final stage = RegExp(r'at the stage (\S+)').firstMatch(out)?[1];
    final took = (watch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    final run = RegExp(
      r'^twk +run +(\S+) +([\d.]+) s',
      multiLine: true,
    ).firstMatch(out);
    final line =
        'lane $lane run $i: exit ${r.exitCode}, run step '
        '${run?[1]} ${run?[2]} s, whole $took s'
        '${stage == null ? '' : ', stopped at stage $stage'}';
    stdout.writeln(line);
    if (r.exitCode != 0) {
      failed.add(line);
      stdout.writeln(out);
    }
  }
}
