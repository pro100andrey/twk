// changedWords: the words two versions of a line differ in, as ranges of
// each; none between lines too different for them to help.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

/// [changedWords] as a list of its two lists, which compare by their items.
List<List<(int, int)>>? words(String before, String after) =>
    switch (changedWords(before, after)) {
      (final a, final b) => [a, b],
      null => null,
    };

void main() {
  test('finds the words a line replaced', () {
    expect(words('final x = 1;', 'final x = 22;'), [
      [(10, 11)],
      [(10, 12)],
    ]);
    expect(words("print('hello');", "print('hi');"), [
      [(7, 12)],
      [(7, 9)],
    ]);
  });

  test('finds the words a line added or removed', () {
    expect(words('run(a, b)', 'run(a, b, verbose)'), [
      <(int, int)>[],
      [(8, 17)],
    ]);
    expect(words('if (a && b) {', 'if (b) {'), [
      [(4, 9)],
      <(int, int)>[],
    ]);
  });

  test('takes a run of blanks as a word', () {
    expect(words('  x = y;', '    x = y;'), [
      [(0, 2)],
      [(0, 4)],
    ]);
  });

  test('takes letters outside ASCII as letters', () {
    expect(words('naïve café', 'naïve cafés'), [
      [(6, 10)],
      [(6, 11)],
    ]);
  });

  test('finds none between lines that are equal', () {
    expect(words('a = b;', 'a = b;'), [<(int, int)>[], <(int, int)>[]]);
  });

  test('is null between lines with too little in common', () {
    expect(words('alpha beta', 'gamma delta'), isNull);
    expect(words('return a + b;', 'yield x;'), isNull);
    expect(words('', 'x'), isNull);
  });
}
