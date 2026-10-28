import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_term/src/pty/pty.dart';

void main() {
  group('signalProcess', () {
    final byPid = <int>[];
    final byPidfd = <(int, int)>[];

    bool toPid(int pid, ProcessSignal signal) {
      byPid.add(pid);
      return true;
    }

    int toPidfd(int pidfd, int signal) {
      byPidfd.add((pidfd, signal));
      return 0;
    }

    setUp(() {
      byPid.clear();
      byPidfd.clear();
    });

    test('never signals by a pid that is not positive', () {
      for (final pid in [-1, 0, -42]) {
        for (final throughPidfd in [false, true]) {
          expect(
            signalProcess(
              pid,
              -1,
              ProcessSignal.sigkill,
              throughPidfd: throughPidfd,
              toPidfd: toPidfd,
              toPid: toPid,
            ),
            isFalse,
            reason: 'pid $pid',
          );
        }
      }
      expect(byPid, isEmpty);
      expect(byPidfd, isEmpty);
    });

    test('goes through the pidfd where there is one, whatever the pid', () {
      for (final pid in [-1, 0, 1234]) {
        expect(
          signalProcess(
            pid,
            7,
            ProcessSignal.sigkill,
            throughPidfd: true,
            toPidfd: toPidfd,
            toPid: toPid,
          ),
          isTrue,
        );
      }
      expect(byPidfd, [(7, 9), (7, 9), (7, 9)]);
      expect(byPid, isEmpty);
    });

    test('signals a positive pid when the pidfd cannot be used', () {
      expect(
        signalProcess(
          1234,
          7,
          ProcessSignal.sigterm,
          throughPidfd: false,
          toPidfd: toPidfd,
          toPid: toPid,
        ),
        isTrue,
      );
      expect(
        signalProcess(
          1234,
          -1,
          ProcessSignal.sigterm,
          throughPidfd: true,
          toPidfd: toPidfd,
          toPid: toPid,
        ),
        isTrue,
      );
      expect(
        signalProcess(
          -1,
          7,
          ProcessSignal.sigterm,
          throughPidfd: false,
          toPidfd: toPidfd,
          toPid: toPid,
        ),
        isFalse,
      );
      expect(byPid, [1234, 1234]);
      expect(byPidfd, isEmpty);
    });

    test('says false when the pidfd refuses the signal', () {
      expect(
        signalProcess(
          1234,
          7,
          ProcessSignal.sigterm,
          throughPidfd: true,
          toPidfd: (_, _) => -1,
          toPid: toPid,
        ),
        isFalse,
      );
      expect(byPid, isEmpty);
    });
  });
}
