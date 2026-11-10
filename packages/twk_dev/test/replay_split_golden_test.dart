// The keys lib/src/replay.dart makes of a recording's input held to
// replay_split.golden.json, the description of them the VS Code extension's
// tests hold its own (editors/vscode/src/core/replay_input.ts) to as well: a
// recording replays the same in `twk record --replay` and in the extension.
// A change to an answer here that is not made in the golden fails this test;
// made in the golden, it fails the extension's until it follows.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_dev/src/replay.dart';
import 'package:twk_dev/twk_dev.dart';

typedef Json = Map<String, Object?>;

/// Where the golden is, from the package's directory.
const goldenPath = 'test/replay_split.golden.json';

void main() {
  final golden = jsonDecode(File(goldenPath).readAsStringSync()) as Json;
  for (final c in (golden['cases']! as List<Object?>).cast<Json>()) {
    test(c['name']! as String, () {
      final cast = Cast(const CastHeader(width: 80, height: 24), [
        for (final e in (c['events']! as List<Object?>).cast<List<Object?>>())
          CastEvent(
            (e[0]! as num).toDouble(),
            e[1]! as String,
            e[2]! as String,
          ),
      ]);
      expect(
        [
          for (final s in replaySteps(cast))
            {'time': s.time, 'keys': s.keys, 'reacts': s.reacts},
        ],
        c['steps'],
      );
    });
  }
}
