// The words a ProgressList writes, another language's under Localizations,
// and written again when they change.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

String _eta(String time) => 'noch $time';
String _more(int count) => '+$count weitere';

String _left(String time) => 'verbleibend $time';

const _german = TwkStrings(eta: _eta, moreTasks: _more);
const _long = TwkStrings(eta: _left);

void main() {
  group('ProgressList with strings', () {
    testTwk('writes the time left and the tasks not shown in them, and '
        'again when they change', (t) async {
      final tracker = ProgressTracker(clock: t.clock.stopwatch);
      addTearDown(tracker.dispose);
      tracker
        ..add('a', total: 100).start()
        ..add('b')
        ..add('c');
      Widget list(TwkStrings strings) => Localizations(
        strings: strings,
        child: ProgressList(
          tracker: tracker,
          maxVisible: 1,
          columns: const [ProgressColumn.label, ProgressColumn.eta],
        ),
      );
      await t.pumpWidget(list(const TwkStrings()), size: (20, 3));
      expect(t.lines, ['a ETA --:--', '+2 more', '']);

      await t.pumpWidget(list(_german), size: (20, 3));
      expect(t.lines, ['a noch --:--', '+2 weitere', '']);
    });

    testTwk('takes the room the words need where it takes what it needs', (
      t,
    ) async {
      final tracker = ProgressTracker(clock: t.clock.stopwatch);
      addTearDown(tracker.dispose);
      tracker.add('a', total: 100).start();
      Widget list(TwkStrings strings) => Localizations(
        strings: strings,
        child: Row(
          children: [
            IntrinsicWidth(
              child: ProgressList(
                tracker: tracker,
                columns: const [ProgressColumn.label, ProgressColumn.eta],
              ),
            ),
            const Text('|'),
          ],
        ),
      );
      await t.pumpWidget(list(const TwkStrings()), size: (40, 1));
      expect(t.lines.single, 'a ETA --:--   |');

      await t.pumpWidget(list(_long), size: (40, 1));
      expect(t.lines.single, 'a verbleibend --:--   |');
    });

    testTwk('writes English without Localizations', (t) async {
      final tracker = ProgressTracker(clock: t.clock.stopwatch);
      addTearDown(tracker.dispose);
      tracker.add('a', total: 100).start();
      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          columns: const [ProgressColumn.label, ProgressColumn.eta],
        ),
        size: (20, 1),
      );
      expect(t.lines.single, endsWith('ETA --:--'));
    });
  });

  group('Localizations', () {
    testTwk('rebuilds what reads TwkStrings only when they change', (t) async {
      var builds = 0;
      final probe = Builder(
        builder: (context) {
          builds++;
          return Text(TwkStrings.of(context).yesLabel);
        },
      );
      Widget under(TwkStrings strings) =>
          Localizations(strings: strings, child: probe);
      await t.pumpWidget(under(const TwkStrings(yesLabel: 'Ja')));
      expect(t.lines.first, startsWith('Ja'));
      expect(builds, 1);
      await t.pumpWidget(under(const TwkStrings(yesLabel: 'Ja')));
      expect(builds, 1);
      await t.pumpWidget(under(const TwkStrings(yesLabel: 'Oui')));
      expect(t.lines.first, startsWith('Oui'));
      expect(builds, 2);
    });
  });
}
