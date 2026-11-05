// When a row is told to be shifted (ICH/DCH): searched in full until four rows
// of a frame found no shift, by a few of its cells after that. What this holds
// is which rows get which search; that the bytes are right, the fuzz does.
import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';

import 'support/harness.dart';

const _width = 200;

/// The rows a frame rewrites for no shift to explain them.
const _busyRows = 4;

/// [_width] letters, no two next to each other alike.
String _letters(Random rnd) {
  final s = StringBuffer();
  var last = -1;
  for (var x = 0; x < _width; x++) {
    var c = rnd.nextInt(26);
    if (c == last) {
      c = (c + 1) % 26;
    }
    s.writeCharCode(0x61 + c);
    last = c;
  }
  return s.toString();
}

/// [text] with a cell inserted at its start.
String _inserted(String text) => 'X${text.substring(0, _width - 1)}';

/// [_inserted], the cells a search by samples looks at for that insertion
/// changed too: a shift that pays, which only a search in full finds.
String _insertedPastSamples(String text) {
  final cells = _inserted(text).split('');
  const step = _width ~/ 16;
  for (var x = 1; x < _width - 1; x += step) {
    cells[x] = '#';
  }
  return cells.join();
}

void main() {
  late Harness hs;
  late Random rnd;

  void write(int y, String text) => hs.canvas.text(0, y, text, hs.pens[0]);

  void busyRows() {
    for (var y = 0; y < _busyRows; y++) {
      write(y, _letters(rnd));
    }
  }

  void expectShifted(int rows) {
    final out = latin1.decode(hs.presenter.out.view);
    expect(hs.mismatches(), isEmpty, reason: out);
    expect(hs.presenter.stats.shiftedRows, rows, reason: out);
  }

  setUp(() {
    rnd = Random(1);
    hs = Harness(_width, _busyRows + 1);
  });

  test('a row below rows no shift explained is shifted all the same', () {
    final text = _letters(rnd);
    busyRows();
    write(_busyRows, text);
    hs.frame();

    busyRows();
    write(_busyRows, _inserted(text));
    hs.frame();
    expectShifted(1);
  });

  test('a frame after a busy one searches its rows in full again', () {
    final text = _letters(rnd);
    busyRows();
    write(_busyRows, text);
    hs.frame();

    busyRows();
    hs.frame();
    expectShifted(0);

    write(_busyRows, _insertedPastSamples(text));
    hs.frame();
    expectShifted(1);
  });
}
