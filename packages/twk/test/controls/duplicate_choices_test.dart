// Choices, segments and item keys that are equal assert, with a hint, when
// the widget is built or given a new list; a value chosen that no choice
// has stays legal.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const List<Choice<String>> dup = [
  Choice('a', 'One'),
  Choice('b', 'Two'),
  Choice('a', 'Three'),
];
const List<Choice<String>> fine = [Choice('a', 'One'), Choice('b', 'Two')];

/// The messages of the errors the app logged since they were last taken,
/// each told apart from an assertion's.
List<String> errors(TwkTester t) => [
  for (final r in t.takeErrors())
    if (r.error is AssertionError) '${r.error}' else 'other: ${r.error}',
];

void main() {
  group('Select and MultiSelect', () {
    testTwk('two choices with one value assert', (t) async {
      await t.pumpWidget(
        Overlay(
          child: Select<String>(choices: dup, value: 'b', onChanged: (_) {}),
        ),
      );
      expect(errors(t), [contains('Select has two choices with the value a')]);
    });

    testTwk('a new list with a duplicate asserts, the same list does not '
        'check again', (t) async {
      Widget select(List<Choice<String>> c) => Overlay(
        child: MultiSelect<String>(
          choices: c,
          values: const {'b'},
          onChanged: (_) {},
        ),
      );
      await t.pumpWidget(select(fine));
      expect(errors(t), isEmpty);
      await t.pumpWidget(select(dup));
      expect(errors(t), [
        contains('MultiSelect has two choices with the value a'),
      ]);
    });

    testTwk('a value no choice has is legal', (t) async {
      await t.pumpWidget(
        Overlay(
          child: Select<String>(
            choices: fine,
            value: 'zzz',
            onChanged: (_) {},
            hint: 'pick',
          ),
        ),
      );
      expect(errors(t), isEmpty);
      expect(t.lines.join('\n'), contains('pick'));
    });
  });

  group('SegmentedButton', () {
    testTwk('two segments with one value assert', (t) async {
      await t.pumpWidget(
        SegmentedButton<String>(
          segments: dup,
          selected: const {'a'},
          onSelectionChanged: (_) {},
        ),
      );
      expect(errors(t), [
        contains('SegmentedButton has two segments with the value a'),
      ]);
    });

    testTwk('a selected value no segment has is legal', (t) async {
      await t.pumpWidget(
        SegmentedButton<String>(
          segments: fine,
          selected: const {'zzz'},
          onSelectionChanged: (_) {},
        ),
      );
      expect(errors(t), isEmpty);
    });
  });

  group('SelectionList', () {
    testTwk('two items with one key assert', (t) async {
      await t.pumpWidget(
        SizedBox(
          height: 4,
          child: SelectionList<int>(
            itemCount: 3,
            keyOf: (i) => i % 2,
            itemBuilder: (context, i) => Text('$i'),
          ),
        ),
      );
      expect(errors(t), [
        contains('SelectionList has two items with the key 0 (at 2)'),
      ]);
    });

    testTwk('an update with the same count and keyOf does not read the keys '
        'again; a new count does', (t) async {
      var reads = 0;
      int keyOf(int i) {
        reads++;
        return i;
      }

      Widget list(int count) => SizedBox(
        height: 4,
        child: SelectionList<int>(
          itemCount: count,
          keyOf: keyOf,
          itemBuilder: (context, i) => Text('$i'),
        ),
      );
      await t.pumpWidget(list(1000));
      reads = 0;
      await t.pumpWidget(list(1000));
      // the items in view, not the thousand
      expect(reads, lessThan(100));
      await t.pumpWidget(list(1001));
      expect(reads, greaterThanOrEqualTo(1001));
      expect(errors(t), isEmpty);
    });

    testTwk('a list refused for its keys leaves no controller undisposed', (
      t,
    ) async {
      await t.pumpWidget(
        SizedBox(
          height: 4,
          child: SelectionList<int>(
            itemCount: 3,
            keyOf: (i) => i % 2,
            itemBuilder: (context, i) => Text('$i'),
          ),
        ),
      );
      expect(errors(t), isNotEmpty);
    }, trackDisposables: true);
  });
}
