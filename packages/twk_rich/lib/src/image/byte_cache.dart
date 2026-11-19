/// What a [ByteCache] holds.
abstract interface class Costed {
  /// What it takes, in bytes.
  int get cost;

  /// Whether it stays however little room there is.
  bool get pinned;
}

/// A map from frame index to a [Costed] value, holding at most [limit]
/// bytes of them: past it the least recently used go first, but for the one
/// just put and those that are pinned.
final class ByteCache<V extends Costed> {
  /// A cache of at most [limit] bytes.
  ByteCache(this.limit);

  /// The most bytes held, but for the value just put and the pinned.
  final int limit;

  final _entries = <int, V>{};
  var _bytes = 0;

  /// The value at [index], now the most recently used; null where none.
  V? operator [](int index) {
    final v = _entries.remove(index);
    if (v != null) {
      _entries[index] = v;
    }
    return v;
  }

  /// Puts [value] at [index], the most recently used, and drops the least
  /// recently used until the rest fit.
  void operator []=(int index, V value) {
    if (_entries.remove(index) case final old?) {
      _bytes -= old.cost;
    }
    _entries[index] = value;
    _bytes += value.cost;
    if (_bytes <= limit) {
      return;
    }
    for (final e in _entries.entries.toList()) {
      if (_bytes <= limit || e.key == index) {
        break;
      }
      if (!e.value.pinned) {
        _entries.remove(e.key);
        _bytes -= e.value.cost;
      }
    }
  }

  /// How many values are held.
  int get length => _entries.length;

  /// The bytes they cost.
  int get bytes => _bytes;
}
