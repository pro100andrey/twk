// The decimal separator of TwkStrings: the sizes and times the widgets and
// the exported functions write, with a comma where the language has one.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const _comma = TwkStrings(decimalSeparator: ',');

void main() {
  group('exported functions', () {
    test('write a point by default and the separator given', () {
      expect(formatBytes(4096), '4.1 kB');
      expect(formatBytes(4096, decimalSeparator: ','), '4,1 kB');
      expect(formatBytes(620000, decimalSeparator: ','), '620 kB');
      expect(
        formatBytes(1536, byteUnits: ByteUnits.binary, decimalSeparator: ','),
        '1,5 KiB',
      );
      expect(formatTook(const Duration(milliseconds: 3190)), '3.1 s');
      expect(
        formatTook(const Duration(milliseconds: 3190), decimalSeparator: ','),
        '3,1 s',
      );
      expect(
        formatTook(
          const Duration(minutes: 1, seconds: 5),
          decimalSeparator: ',',
        ),
        '01:05',
      );
    });
  });

  group('TwkStrings', () {
    test('have a point, and differ and hash by the separator', () {
      expect(const TwkStrings().decimalSeparator, '.');
      expect(_comma, isNot(const TwkStrings()));
      expect(_comma, const TwkStrings(decimalSeparator: ','));
      expect(_comma.hashCode, const TwkStrings(decimalSeparator: ',').hashCode);
    });
  });

  group('TaskList', () {
    testTwk('writes the time a task took with the separator', (t) async {
      Widget list(TwkStrings strings) => Localizations(
        strings: strings,
        child: TaskList(
          tasks: [
            TaskItem(
              'Build',
              status: TaskStatus.done,
              elapsed: const Duration(milliseconds: 3190),
            ),
          ],
        ),
      );
      await t.pumpWidget(list(const TwkStrings()), size: (20, 1));
      expect(t.lines.single, contains('3.1 s'));
      await t.pumpWidget(list(_comma), size: (20, 1));
      expect(t.lines.single, contains('3,1 s'));
    });
  });

  group('ProgressList', () {
    testTwk('writes counts with the separator', (t) async {
      final tracker = ProgressTracker(clock: t.clock.stopwatch);
      addTearDown(tracker.dispose);
      tracker.add('a', total: 3200000, unit: ProgressUnit.bytes)
        ..start()
        ..advance(1200000);
      Widget list(TwkStrings strings) => Localizations(
        strings: strings,
        child: ProgressList(
          tracker: tracker,
          columns: const [ProgressColumn.label, ProgressColumn.count],
        ),
      );
      await t.pumpWidget(list(const TwkStrings()), size: (30, 1));
      expect(t.lines.single, contains('1.2/3.2 MB'));
      await t.pumpWidget(list(_comma), size: (30, 1));
      expect(t.lines.single, contains('1,2/3,2 MB'));
    });

    test('ProgressTask.summary takes the separator', () {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      final task = tracker.add('a', total: 3200000, unit: ProgressUnit.bytes)
        ..start()
        ..advance(1200000);
      expect(task.summary(), contains('1.2/3.2 MB'));
      expect(task.summary(decimalSeparator: ','), contains('1,2/3,2 MB'));
    });
  });
}
