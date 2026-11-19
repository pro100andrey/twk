import 'package:test/test.dart';
import 'package:twk_rich/src/image/byte_cache.dart';

final class Item implements Costed {
  Item(this.cost, {this.pinned = false});

  @override
  final int cost;
  @override
  final bool pinned;
}

void main() {
  test('the least recently used go first, past the limit', () {
    final c = ByteCache<Item>(100);
    for (var i = 0; i < 5; i++) {
      c[i] = Item(40);
    }
    expect(c.length, 2);
    expect(c[3], isNotNull);
    expect(c[4], isNotNull);
    expect(c[0], isNull);
    expect(c[3], isNotNull); // 3 is the most recent now
    c[5] = Item(40);
    expect(c[4], isNull, reason: 'the least recent was 4');
    expect(c[3], isNotNull);
    expect(c.bytes, 80);
  });

  test('the one just put stays whatever it costs, a pinned one too', () {
    final c = ByteCache<Item>(100);
    c[0] = Item(60, pinned: true);
    c[1] = Item(60);
    c[2] = Item(500);
    expect(c[0], isNotNull, reason: 'pinned');
    expect(c[1], isNull);
    expect(c[2], isNotNull, reason: 'just put');
    c[3] = Item(10);
    expect(c[2], isNull);
    expect(c.bytes, 70);
  });

  test('a value put again at an index replaces the one there', () {
    final c = ByteCache<Item>(100);
    c[0] = Item(70);
    c[0] = Item(30);
    expect(c.bytes, 30);
    expect(c.length, 1);
  });
}
