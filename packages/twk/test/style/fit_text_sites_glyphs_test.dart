// The controls that cut a label with fitText cut it with the theme's
// Glyphs.ellipsis: `…` in Glyphs.unicode, `...` (three columns, taken from
// the room) in Glyphs.ascii. Sites: Chip, ValueStepper, SegmentedButton,
// the console's stack places, the ProgressList's labels and "+n more", the
// last Breadcrumbs item.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../debug/console_test.dart' show record;

Widget themed(Glyphs glyphs, Widget child) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: child,
);

Widget corner(int? width, Widget child) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox(width: width, child: child),
);

void main() {
  final marks = {Glyphs.unicode: '…', Glyphs.ascii: '...'};

  for (final MapEntry(key: glyphs, value: mark) in marks.entries) {
    final name = mark == '…' ? 'unicode' : 'ascii';

    testTwk('ChipList cuts a label with the $name mark', (t) async {
      await t.pumpWidget(
        themed(
          glyphs,
          ChipList<String>(
            chips: const [Choice('x', 'a very long label')],
            selected: const {},
            onSelectionChanged: (_) {},
          ),
        ),
        size: (10, 2),
      );
      expect(t.lines.first.trimRight(), contains(mark));
      expect(t.lines.first.trimRight().length, lessThanOrEqualTo(10));
      expect(
        t.lines.first,
        mark == '…' ? isNot(contains('...')) : isNot(contains('…')),
      );
    });

    testTwk('ValueStepper cuts a label with the $name mark', (t) async {
      await t.pumpWidget(
        themed(
          glyphs,
          corner(
            null,
            ValueStepper<String>(
              values: const [Choice('a', 'auto-switching')],
              value: 'a',
              onChanged: (_) {},
            ),
          ),
        ),
        size: (12, 2),
      );
      expect(
        t.lines.first,
        mark == '…' ? contains(' auto-sw… ') : contains(' auto-... '),
      );
    });

    testTwk('SegmentedButton cuts its labels with the $name mark', (t) async {
      await t.pumpWidget(
        themed(
          glyphs,
          corner(
            24,
            SegmentedButton<String>(
              segments: const [
                Choice('a', 'Everything'),
                Choice('b', 'Elsewhere'),
              ],
              selected: const {'a'},
              onSelectionChanged: (_) {},
            ),
          ),
        ),
        size: (30, 2),
      );
      final first = t.lines.first.trimRight();
      expect(first.length, lessThanOrEqualTo(24));
      expect(first.split(mark), hasLength(2), reason: first);
      expect(
        first,
        mark == '…' ? isNot(contains('...')) : isNot(contains('…')),
      );
    });

    testTwk('ProgressList cuts labels and "+n more" with the $name mark', (
      t,
    ) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      tracker
        ..add('Downloading assets').start()
        ..add('b')
        ..add('c');
      await t.pumpWidget(
        themed(
          glyphs,
          ProgressList(
            tracker: tracker,
            maxVisible: 1,
            columns: const [ProgressColumn.label],
          ),
        ),
        size: (8, 2),
      );
      final lines = t.lines;
      expect(lines.first.trimRight(), contains(mark));
      expect(lines.first.trimRight().length, lessThanOrEqualTo(8));
      // "+2 more" in 4 columns
      await t.resize(5, 2);
      await t.pump();
      expect(t.lines[1].trimRight(), mark == '…' ? '+2 m…' : '+2...');
    });

    testTwk('Breadcrumbs cuts the last item with the $name mark', (t) async {
      // the width where only the last item is left, cut after a mark
      final width = mark == '…' ? 8 : 12;
      await t.pumpWidget(
        themed(
          glyphs,
          corner(
            width,
            Breadcrumbs(
              items: const ['Root', 'Projects', 'widgets'],
              onSelected: (_) {},
            ),
          ),
        ),
        size: (14, 2),
      );
      expect(
        t.lines.first.trimRight(),
        mark == '…' ? '… › wid…' : '... > wid...',
      );
    });
  }

  group('the console cuts the place of a frame from the left', () {
    for (final MapEntry(key: glyphs, value: mark) in marks.entries) {
      test('with the ${mark == '…' ? 'unicode' : 'ascii'} mark', () {
        final app = Uri.file('${Directory.current.path}/lib/main.dart');
        final stack = StackTrace.fromString(
          '#0      main.<anonymous closure> ($app:12:5)\n',
        );
        final sink = LogSink()
          ..add(
            record(
              'failed',
              level: LogLevel.error,
              error: 'boom',
              stack: stack,
            ),
          );
        final controller = ConsoleController(sink)
          ..open()
          ..selectPrevious()
          ..showSelected();
        final shot = Shot(
          themed(
            glyphs,
            Console(controller: controller, rows: 4, child: const SizedBox()),
          ),
          30,
          12,
        )..frame();
        final place = shot.rows.firstWhere((r) => r.contains(':12:5'));
        expect(place, contains(mark));
        expect(
          place,
          mark == '…' ? isNot(contains('...')) : isNot(contains('…')),
        );
      });
    }
  });
}
