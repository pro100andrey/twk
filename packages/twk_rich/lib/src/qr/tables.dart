/// The tables of ISO/IEC 18004 a QR code is built by: the error
/// correction blocks of each version and level (Table 9) and where the
/// alignment patterns go (Annex E).
library;

/// The error correction codewords of each block, by level (L, M, Q, H) and
/// then version (1 to 40): Table 9 of ISO/IEC 18004, the same in every
/// block of a symbol.
const ecCodewordsPerBlock = <List<int>>[
  // L
  [
    7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, //
    28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
    30, 30, 30, 30,
  ],
  // M
  [
    10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, //
    26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    28, 28, 28, 28,
  ],
  // Q
  [
    13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, //
    26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
    30, 30, 30, 30,
  ],
  // H
  [
    17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, //
    26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
    30, 30, 30, 30,
  ],
];

/// The error correction blocks of a symbol, by level (L, M, Q, H) and then
/// version (1 to 40): Table 9 of ISO/IEC 18004, the blocks of both of its
/// groups counted together.
const ecBlocks = <List<int>>[
  // L
  [
    1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, //
    10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25,
  ],
  // M
  [
    1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, //
    17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47,
    49,
  ],
  // Q
  [
    1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, //
    23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62,
    65, 68,
  ],
  // H
  [
    1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, //
    25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74,
    77, 81,
  ],
];

/// The rows and columns the centers of the alignment patterns are on, by
/// version (1 to 40): Table E.1 of ISO/IEC 18004. A pattern is at each
/// pair of them but the three the finder patterns take.
const List<List<int>> alignmentCenters = [
  [],
  [6, 18],
  [6, 22],
  [6, 26],
  [6, 30],
  [6, 34],
  [6, 22, 38],
  [6, 24, 42],
  [6, 26, 46],
  [6, 28, 50],
  [6, 30, 54],
  [6, 32, 58],
  [6, 34, 62],
  [6, 26, 46, 66],
  [6, 26, 48, 70],
  [6, 26, 50, 74],
  [6, 30, 54, 78],
  [6, 30, 56, 82],
  [6, 30, 58, 86],
  [6, 34, 62, 90],
  [6, 28, 50, 72, 94],
  [6, 26, 50, 74, 98],
  [6, 30, 54, 78, 102],
  [6, 28, 54, 80, 106],
  [6, 32, 58, 84, 110],
  [6, 30, 58, 86, 114],
  [6, 34, 62, 90, 118],
  [6, 26, 50, 74, 98, 122],
  [6, 30, 54, 78, 102, 126],
  [6, 26, 52, 78, 104, 130],
  [6, 30, 56, 82, 108, 134],
  [6, 34, 60, 86, 112, 138],
  [6, 30, 58, 86, 114, 142],
  [6, 34, 62, 90, 118, 146],
  [6, 30, 54, 78, 102, 126, 150],
  [6, 24, 50, 76, 102, 128, 154],
  [6, 28, 54, 80, 106, 132, 158],
  [6, 32, 58, 84, 110, 136, 162],
  [6, 26, 54, 82, 110, 138, 166],
  [6, 30, 58, 86, 114, 142, 170],
];

/// The modules of a symbol of [version] that hold codewords and remainder
/// bits: all of them but those of the finder patterns with their
/// separators, the timing patterns, the alignment patterns, the format
/// information with the dark module and, from version 7, the version
/// information.
int dataModules(int version) {
  final size = 4 * version + 17;
  // three finders with their separators, 8 × 8 each; the format
  // information twice and the dark module
  var modules = size * size - 3 * 64 - 31;
  // the timing patterns between the separators
  modules -= 2 * (size - 16);
  final n = alignmentCenters[version - 1].length;
  if (n > 0) {
    // n² patterns of 25 but the three at the finders; those on row and
    // column 6 cover 5 modules of a timing pattern each
    modules -= 25 * (n * n - 3) - 2 * 5 * (n - 2);
  }
  if (version >= 7) {
    modules -= 2 * 18;
  }
  return modules;
}

/// The codewords a symbol of [version] holds, data and error correction.
int totalCodewords(int version) => dataModules(version) ~/ 8;

/// The data codewords a symbol of [version] holds at the level of index
/// [level] (L, M, Q, H).
int dataCodewords(int version, int level) =>
    totalCodewords(version) -
    ecBlocks[level][version - 1] * ecCodewordsPerBlock[level][version - 1];
