// A test that holds processes it started while fixtures/processes.dart,
// run at once beside it (in another isolate of its runner, or in another
// runner), ends its own: what process_test.dart checks is that none of
// those ends reaches these. It waits for the file TWK_PROCESS_DONE names,
// which processes.dart writes once all of its tests have ended, then
// expects its own processes still running; it writes them to the file
// TWK_HOLDER_LOG names as processes.dart does.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

final _log = File(Platform.environment['TWK_HOLDER_LOG']!);

/// Writes [pid] with the time it started to the log.
void started(int pid) {
  final stat = File('/proc/$pid/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  _log.writeAsStringSync('$pid ${fields[19]}\n', mode: FileMode.append);
}

void main() {
  test(
    'what it started runs while the other suite ends its own',
    () async {
      final alone = await startProcess('sleep', ['300']);
      final shell = await startProcess('sh', [
        '-c',
        r'sleep 300 & echo $!; wait',
      ], group: true);
      final grandchild = int.parse(
        await shell.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
      );
      for (final pid in [alone.pid, shell.pid, grandchild]) {
        started(pid);
      }
      await waitUntil(
        File(Platform.environment['TWK_PROCESS_DONE']!).existsSync,
        'the other suite to end its tests',
        timeout: const Duration(minutes: 2),
      );
      // a kill that reached them would have them gone by now; what they
      // would answer then is waited for, and must not come
      Future<int?> exit(Process p) => p.exitCode
          .then<int?>((code) => code)
          .timeout(const Duration(milliseconds: 500), onTimeout: () => null);
      expect(await exit(alone), isNull, reason: 'sleep ${alone.pid} ended');
      expect(await exit(shell), isNull, reason: 'sh ${shell.pid} ended');
      final stat = File('/proc/$grandchild/stat').readAsStringSync();
      expect(
        stat.substring(stat.lastIndexOf(')') + 2).split(' ').first,
        isNot('Z'),
        reason: 'sleep $grandchild ended',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
