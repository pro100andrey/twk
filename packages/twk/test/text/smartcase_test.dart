// Smartcase: a pattern all in lower case ignores the case, any capital
// heeds it; the offsets found are the text's, a letter whose lower case is
// longer (İ on the web) matched as it is; outside ASCII too, surrogate
// pairs included; the same as searching the text lower-cased wherever that
// keeps its length.
import 'dart:math' show Random;

import 'package:test/test.dart';
import 'package:twk/twk.dart';

void main() {
  test('a pattern all in lower case ignores the case', () {
    final s = Smartcase('error');
    expect(s.ignoresCase, isTrue);
    expect(s.indexIn('an ERROR here'), 3);
    expect(s.indexIn('an Error here'), 3);
    expect(s.indexIn('an error here'), 3);
    expect(s.indexIn('an err'), -1);
    expect(s.isIn('ErRoR'), isTrue);
    expect(s.isIn('warning'), isFalse);
  });

  test('a capital in the pattern heeds the case', () {
    final s = Smartcase('Error');
    expect(s.ignoresCase, isFalse);
    expect(s.indexIn('an ERROR, an Error'), 13);
    expect(s.isIn('an error'), isFalse);
  });

  test('names its pattern', () {
    expect('${Smartcase('Error')}', 'Smartcase(Error)');
  });

  test('from start on, as far as the end', () {
    final s = Smartcase('ab');
    expect(s.indexIn('AB ab Ab', 1), 3);
    expect(s.indexIn('AB ab Ab', 4), 6);
    expect(s.indexIn('AB ab Ab', 7), -1);
    expect(s.indexIn('AB ab Ab', 8), -1);
    expect(() => s.indexIn('ab', 3), throwsRangeError);
    expect(Smartcase('').indexIn('abc', 2), 2);
    expect(Smartcase('abc').indexIn('ab'), -1);
  });

  test('outside ASCII: Cyrillic, Greek, a sign that is a letter', () {
    expect(Smartcase('ошибка').indexIn('сеть: ОШИБКА'), 6);
    expect(Smartcase('ΟΔΟΣ').indexIn('η οδος, η ΟΔΟΣ'), 10);
    expect(Smartcase('οδοσ').indexIn('η ΟΔΟΣ'), 2);
    // the Kelvin sign's lower case is k
    expect(Smartcase('5k').indexIn('at 5K'), 3);
  });

  test('a surrogate pair is lower-cased whole', () {
    // Deseret: 𐐀 (U+10400) is the capital of 𐐨 (U+10428)
    expect(Smartcase('𐐨x').indexIn('a 𐐀X'), 2);
    expect(Smartcase('𐐨').indexIn('𐐨𐐀', 1), 2);
    expect(Smartcase('😀').indexIn('a 😀'), 2);
  });

  test('İ: what is found is where it is in the text', () {
    // whatever İ is in lower case (i on the VM, i and a dot on the web),
    // the offsets are the text's, the rest of it still ignoring the case
    expect(Smartcase('error').indexIn('İİ ERROR'), 3);
    expect(Smartcase('stanbul').indexIn('İSTANBUL'), 1);
    // a capital heeds the case
    expect(Smartcase('İ').indexIn('i İ'), 2);
  });

  test('finds what a search of the text lower-cased does, wherever that '
      'keeps its length', () {
    const letters = 'aAbBkKKσ΢ΣсСİi𐐀𐐨 .';
    final runes = letters.runes.toList();
    final rnd = Random(7);
    String word(int n) => String.fromCharCodes([
      for (var i = 0; i < n; i++) runes[rnd.nextInt(runes.length)],
    ]);
    var compared = 0;
    for (var k = 0; k < 4000; k++) {
      final text = word(rnd.nextInt(12));
      final pattern = word(1 + rnd.nextInt(3)).toLowerCase();
      final lower = text.toLowerCase();
      if (lower.length != text.length) {
        continue;
      }
      final from = rnd.nextInt(text.length + 1);
      expect(
        Smartcase(pattern).indexIn(text, from),
        lower.indexOf(pattern, from),
        reason: '"$pattern" in "$text" from $from',
      );
      compared++;
    }
    expect(compared, greaterThan(1000));
  });
}
