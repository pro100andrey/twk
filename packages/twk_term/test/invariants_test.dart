import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_term/twk_term.dart';

void main() {
  group('debugAssertInvariants', () {
    test('holds through random bytes, escapes and resizes', () {
      // feed and resize assert it themselves
      const pieces = [
        '\x1b[?1049h',
        '\x1b[?1049l',
        '\x1b[?47h',
        '\x1b[?7l',
        '\x1b[?7h',
        '\x1b7',
        '\x1b8',
        '\x1b[s',
        '\x1b[u',
        '\x1bc',
        '\x1bD',
        '\x1bM',
        '\x1b[3;7r',
        '\x1b[r',
        '\x1b[5;2r',
        '\x1b[0;0r',
        '\x1b[999;999H',
        '\x1b[2J',
        '\x1b[3J',
        '\x1b[5L',
        '\x1b[4M',
        '\x1b[9S',
        '\x1b[9T',
        '\x1b[20@',
        '\x1b[20P',
        '\x1b[3g',
        '\x1b[0g',
        '\x1bH',
        '\t',
        '\t\t',
        '\r\n',
        '\n',
        '\b',
        '\x1b[99C',
        '\x1b[99D',
        '\x1b[99A',
        '\x1b[99B',
        'hello',
        'wide: 中文',
        'é',
        '\u{1F600}',
        '\x1b[?2027h',
        '\x1b[2;3;4m',
        '\x1b[b',
        '\x1b[?6h',
        '\x1b[?6l',
        '\x1b[?3h',
        '\x1b[2K',
        '\x1b[1K',
        '\x1b[0J',
        '\x1b[1J',
        '\x1b[99X',
      ];
      for (var seed = 0; seed < 40; seed++) {
        final random = Random(seed);
        final t = TerminalEmulator(
          width: 1 + random.nextInt(30),
          height: 1 + random.nextInt(12),
          scrollbackLimit: random.nextInt(20),
        );
        for (var i = 0; i < 300; i++) {
          switch (random.nextInt(10)) {
            case 0:
              t.resize(1 + random.nextInt(40), 1 + random.nextInt(15));
            case 1:
              t.feed(
                Uint8List.fromList([
                  for (var k = 0; k < 20; k++) random.nextInt(256),
                ]),
              );
            default:
              t.feedText(pieces[random.nextInt(pieces.length)]);
          }
          expect(t.debugAssertInvariants(), isTrue, reason: 'seed $seed');
        }
      }
    });

    test('a pending wrap is legitimate at the last column', () {
      final t = TerminalEmulator(width: 4, height: 2)..feedText('abcd');
      expect(t.wrapPending, isTrue);
      expect(t.cursorX, 3);
      expect(t.debugAssertInvariants(), isTrue);
    });

    TerminalEmulator filled() =>
        TerminalEmulator(width: 5, height: 3)
          ..feedText('1\r\n2\r\n3\r\n4\r\n5\r\n');

    final corruptions = <String, void Function(TerminalEmulator)>{
      'a cursor off the screen': (t) => t.debugCorrupt(cursorX: 5),
      'a top margin at the bottom': (t) => t.debugCorrupt(top: 3),
      'tab stops not as wide as the screen': (t) =>
          t.debugCorrupt(shortTabs: true),
      'an alternate screen of another height': (t) =>
          t.debugCorrupt(shortAlternate: true),
      'a scrollback line of another width': (t) =>
          t.debugCorrupt(narrowScrollback: true),
    };
    for (final MapEntry(key: name, value: corrupt) in corruptions.entries) {
      test('fires on $name', () {
        final t = filled();
        expect(t.scrollbackLength, greaterThan(0));
        corrupt(t);
        expect(t.debugAssertInvariants, throwsA(isA<AssertionError>()));
        // a feed that writes nothing still ends in the check, which looks at
        // the lines the scrollback took since the last one, not the old ones
        if (!name.contains('scrollback')) {
          expect(() => t.feed(const []), throwsA(isA<AssertionError>()));
        }
      });
    }

    test('a feed checks the lines the scrollback took, not all of them', () {
      final t = TerminalEmulator(width: 5, height: 3, scrollbackLimit: 5000);
      for (var i = 0; i < 2000; i++) {
        t.feedText('$i\r\n');
      }
      expect(t.scrollbackLength, greaterThan(1900));
      final before = t.debugScrollbackChecked;
      t
        ..feedText('x\r\n')
        ..feed(const [])
        ..feedText('y');
      // one line scrolled off, however much it holds
      expect(t.debugScrollbackChecked - before, lessThanOrEqualTo(1));
      // a direct call checks them all
      final n = t.scrollbackLength;
      t.debugAssertInvariants();
      expect(t.debugScrollbackChecked - before, greaterThanOrEqualTo(n));
    });
  });
}
