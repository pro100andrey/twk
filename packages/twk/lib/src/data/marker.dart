/// How a [DotCanvas] shows its dots: [Marker].
library;

import 'dot_canvas.dart';

/// How a [DotCanvas] shows its dots: how many a cell holds across and down,
/// and the glyph each pattern of them is drawn as.
///
/// The dots of a cell are numbered row by row from the top left; bit `k` of
/// a pattern is dot `k`.
final class Marker {
  const Marker._(this._kind, this.dotsAcross, this.dotsDown, [this._char = 0]);

  /// One dot per cell, drawn as [char], a single code point.
  factory Marker.custom(String char) {
    final runes = char.runes;
    assert(runes.length == 1, 'a marker is one code point: "$char"');
    return Marker._(_custom, 1, 1, runes.first);
  }

  /// One dot per cell, drawn as `•`.
  static const dot = Marker._(_dot, 1, 1, 0x2022);

  /// One dot per cell, drawn as a full block `█`.
  static const block = Marker._(_block, 1, 1, 0x2588);

  /// One dot per cell, drawn as a lower half block `▄`.
  static const bar = Marker._(_bar, 1, 1, 0x2584);

  /// 2 × 4 dots per cell, drawn as braille patterns.
  static const braille = Marker._(_braille, 2, 4);

  /// 1 × 2 dots per cell, drawn as half blocks `▀ ▄ █`; each half shows a
  /// color of its own.
  static const halfBlock = Marker._(_halfBlock, 1, 2);

  /// 2 × 2 dots per cell, drawn as quadrants `▘ ▚ ▟`.
  static const quadrant = Marker._(_quadrant, 2, 2);

  /// 2 × 3 dots per cell, drawn as sextants (Unicode 13).
  static const sextant = Marker._(_sextant, 2, 3);

  /// 2 × 4 dots per cell, drawn as octants (Unicode 16).
  static const octant = Marker._(_octant, 2, 4);

  static const _dot = 0;
  static const _block = 1;
  static const _bar = 2;
  static const _braille = 3;
  static const _halfBlock = 4;
  static const _quadrant = 5;
  static const _sextant = 6;
  static const _octant = 7;
  static const _custom = 8;

  final int _kind;
  final int _char;

  /// Dots across a cell.
  final int dotsAcross;

  /// Dots down a cell.
  final int dotsDown;

  /// The code point of a custom marker; 0 for the others.
  int get char => _kind == _custom ? _char : 0;

  /// Whether each half of a cell shows a color of its own ([halfBlock]).
  bool get twoColors => _kind == _halfBlock;

  /// How many patterns of dots a cell can hold.
  int get patterns => 1 << (dotsAcross * dotsDown);

  /// The code point [pattern] is drawn as; a blank for no dots.
  int glyphOf(int pattern) {
    assert(pattern >= 0 && pattern < patterns, 'a pattern of this marker');
    if (pattern == 0) {
      return 0x20;
    }
    return switch (_kind) {
      _braille => 0x2800 | _brailleBits[pattern],
      _halfBlock => const [0x20, 0x2580, 0x2584, 0x2588][pattern],
      _quadrant => _quadrants.codeUnitAt(pattern),
      _sextant => _sextantOf(pattern),
      _octant => _octantOf(pattern),
      _ => _char,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is Marker && other._kind == _kind && other._char == _char;

  @override
  int get hashCode => Object.hash(_kind, _char);

  @override
  String toString() => switch (_kind) {
    _dot => 'Marker.dot',
    _block => 'Marker.block',
    _bar => 'Marker.bar',
    _braille => 'Marker.braille',
    _halfBlock => 'Marker.halfBlock',
    _quadrant => 'Marker.quadrant',
    _sextant => 'Marker.sextant',
    _octant => 'Marker.octant',
    _ => 'Marker.custom(${String.fromCharCode(_char)})',
  };
}

/// Braille bits of each pattern of 2 × 4 dots: dots 0, 2, 4 and 6 (the
/// left column) are braille dots 1, 2, 3 and 7; dots 1, 3, 5 and 7 are
/// braille dots 4, 5, 6 and 8.
final List<int> _brailleBits = List.generate(256, (pattern) {
  const bits = [0x01, 0x08, 0x02, 0x10, 0x04, 0x20, 0x40, 0x80];
  var out = 0;
  for (var k = 0; k < 8; k++) {
    if ((pattern >> k) & 1 != 0) {
      out |= bits[k];
    }
  }
  return out;
});

/// The quadrant glyph of each pattern of 2 × 2 dots.
const _quadrants = ' ▘▝▀▖▌▞▛▗▚▐▜▄▙▟█';

/// Sextants are encoded in the order of their patterns from U+1FB00, but
/// for the two halves and the full block, which are encoded before.
int _sextantOf(int pattern) => switch (pattern) {
  21 => 0x258C,
  42 => 0x2590,
  63 => 0x2588,
  _ => 0x1FB00 + pattern - 1 - (pattern > 21 ? 1 : 0) - (pattern > 42 ? 1 : 0),
};

/// Octants encoded before the octant block (U+1CD00): blocks, quadrants and
/// the quarter blocks.
const _octantsBefore = {
  1: 0x1CEA8, // left half upper one quarter
  2: 0x1CEAB, // right half upper one quarter
  3: 0x1FB82, // upper one quarter
  5: 0x2598, // ▘
  10: 0x259D, // ▝
  15: 0x2580, // ▀
  20: 0x1FBE6, // middle left one quarter
  40: 0x1FBE7, // middle right one quarter
  63: 0x1FB85, // upper three quarters
  64: 0x1CEA3, // left half lower one quarter
  80: 0x2596, // ▖
  85: 0x258C, // ▌
  90: 0x259E, // ▞
  95: 0x259B, // ▛
  128: 0x1CEA0, // right half lower one quarter
  160: 0x2597, // ▗
  165: 0x259A, // ▚
  170: 0x2590, // ▐
  175: 0x259C, // ▜
  192: 0x2582, // ▂
  240: 0x2584, // ▄
  245: 0x2599, // ▙
  250: 0x259F, // ▟
  252: 0x2586, // ▆
  255: 0x2588, // █
};

/// The rest are encoded in the order of their patterns from U+1CD00.
int _octantOf(int pattern) {
  final before = _octantsBefore[pattern];
  if (before != null) {
    return before;
  }
  var skipped = 1; // the blank
  for (final p in _octantsBefore.keys) {
    if (p < pattern) {
      skipped++;
    }
  }
  return 0x1CD00 + pattern - skipped;
}
