// The emulator's Konsole images (Vt.konsoleImages): a scroll up moves every
// image up, wherever the scrolled rows are, a scroll down none, and a
// deletion keeps the image data, as Konsole 26.08's Screen.cpp does.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_test/vt.dart';

/// kitty image [id] (12 bytes) placed at row [y], column 0, 2 x 2 cells,
/// as placement 1.
String _place(int id, int y) =>
    '\x1b[${y + 1};1H\x1b_Ga=T,f=100,t=d,i=$id,p=1,c=2,r=2,C=1,q=2;'
    '${base64.encode(List.filled(12, id))}\x1b\\';

/// Each image the emulator shows: its id and where.
List<String> _shown(Vt vt) => [
  for (final i in vt.images) '${i.id} ${i.cols}x${i.rows} at (${i.x}, ${i.y})',
];

void main() {
  for (final (name, scroll) in [
    ('SU in a scroll region', '\x1b[5;8r\x1b[S\x1b[r'),
    ('a line feed at its bottom margin', '\x1b[5;8r\x1b[8;1H\n\x1b[r'),
    ('DL', '\x1b[6;1H\x1b[M'),
  ]) {
    test('$name moves the images outside the scrolled rows up too', () {
      final vt = Vt(10, 8, konsoleImages: true, allowLineFeed: true)
        ..feed(utf8.encode('${_place(1, 0)}${_place(2, 5)}$scroll'));
      expect(vt.errors, isEmpty);
      expect(_shown(vt), ['1 2x1 at (0, 0)', '2 2x2 at (0, 4)']);
      // kitty's: those in the rows move with them, the others stay
      final kitty = Vt(10, 8, allowLineFeed: true)
        ..feed(utf8.encode('${_place(1, 0)}${_place(2, 5)}$scroll'));
      expect(_shown(kitty), [
        '1 2x2 at (0, 0)',
        if (name == 'DL') '2 2x1 at (0, 5)' else '2 2x2 at (0, 4)',
      ]);
    });
  }

  for (final (name, scroll) in [
    ('SD', '\x1b[5;8r\x1b[T\x1b[r'),
    ('IL', '\x1b[5;1H\x1b[L'),
  ]) {
    test('$name moves no image', () {
      final vt = Vt(10, 8, konsoleImages: true)
        ..feed(utf8.encode('${_place(1, 0)}${_place(2, 5)}$scroll'));
      expect(vt.errors, isEmpty);
      expect(_shown(vt), ['1 2x2 at (0, 0)', '2 2x2 at (0, 5)']);
    });
  }

  test('a deletion keeps the image data, which an image of the same id '
      'replaces', () {
    final vt = Vt(10, 8, konsoleImages: true)
      ..feed(utf8.encode('${_place(1, 0)}\x1b_Ga=d,d=I,i=1,q=2\x1b\\'));
    expect(vt.images, isEmpty);
    expect(vt.kittyImages, {1: 12});
    vt.feed(utf8.encode('${_place(2, 0)}\x1b[2J'));
    expect(vt.images, isEmpty);
    expect(vt.kittyImages, {1: 12, 2: 12});
    final kitty = Vt(10, 8)
      ..feed(utf8.encode('${_place(1, 0)}\x1b_Ga=d,d=I,i=1,q=2\x1b\\'));
    expect(kitty.kittyImages, isEmpty);
  });
}
