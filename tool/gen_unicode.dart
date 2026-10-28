// Generates the core's (packages/twk_core) lib/src/unicode/tables.g.dart
// and lib/src/unicode/bidi_data.g.dart from the Unicode Character Database,
// then formats them.
//
//   dart run tool/gen_unicode.dart            # uses the cached UCD if present
//   dart run tool/gen_unicode.dart --refresh  # re-downloads the UCD
//
// Two per-code-point properties go to tables.g.dart:
//
//  * segmentation byte  = GCB (bits 0..3) | ExtPict (bit 4) | InCB (bits 5..6)
//  * width byte         = width class (bits 0..1: 0 zero, 1 narrow, 2 wide,
//                         3 ambiguous) | Emoji_Presentation (bit 2) |
//                         Emoji (bit 3)
//
// and three bidi properties (UAX #9) to bidi_data.g.dart: Bidi_Class, as
// the index of BidiClass in lib/src/unicode/bidi.dart; Bidi_Mirroring_Glyph;
// and Bidi_Paired_Bracket with its type.
//
// The GraphemeBreakTest.txt conformance file is copied to the core's
// test/data/. The bidi conformance files, BidiTest.txt and
// BidiCharacterTest.txt (7.6 and 6.6 MB), are not: the core's
// test/unicode/bidi_test.dart downloads them for the Unicode version of
// the tables.
//
// The tables are derived from Unicode data files, which are under the
// Unicode License v3, not the MIT License of this project: each generated
// file names its sources and carries that licence in its header.

import 'dart:io';

const _base = 'https://www.unicode.org/Public/UCD/latest/ucd';

/// Of the files [_files] fetches, those tables.g.dart is derived from, in
/// the order its header names them.
const _sources = [
  'GraphemeBreakProperty.txt',
  'emoji-data.txt',
  'DerivedCoreProperties.txt',
  'EastAsianWidth.txt',
  'DerivedGeneralCategory.txt',
];

/// Of the files [_files] fetches, those bidi_data.g.dart is derived from.
const _bidiSources = [
  'DerivedBidiClass.txt',
  'BidiMirroring.txt',
  'BidiBrackets.txt',
];

/// The Unicode License v3 (https://www.unicode.org/license.txt), as the
/// generated file's header carries it; `{year}` stands for the year of the
/// data files' copyright.
const _unicodeLicense = '''
UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-{year} Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.''';

const _files = <String, String>{
  'GraphemeBreakProperty.txt': '$_base/auxiliary/GraphemeBreakProperty.txt',
  'GraphemeBreakTest.txt': '$_base/auxiliary/GraphemeBreakTest.txt',
  'emoji-data.txt': '$_base/emoji/emoji-data.txt',
  'DerivedCoreProperties.txt': '$_base/DerivedCoreProperties.txt',
  'EastAsianWidth.txt': '$_base/EastAsianWidth.txt',
  'DerivedGeneralCategory.txt': '$_base/extracted/DerivedGeneralCategory.txt',
  'DerivedBidiClass.txt': '$_base/extracted/DerivedBidiClass.txt',
  'BidiMirroring.txt': '$_base/BidiMirroring.txt',
  'BidiBrackets.txt': '$_base/BidiBrackets.txt',
};

/// Bidi_Class values by their short names and by the long names of the
/// `@missing` lines: the index of each in BidiClass.
const _bidiCodes = <String, int>{
  'L': 0,
  'R': 1,
  'AL': 2,
  'EN': 3,
  'ES': 4,
  'ET': 5,
  'AN': 6,
  'CS': 7,
  'NSM': 8,
  'BN': 9,
  'B': 10,
  'S': 11,
  'WS': 12,
  'ON': 13,
  'LRE': 14,
  'LRO': 15,
  'RLE': 16,
  'RLO': 17,
  'PDF': 18,
  'LRI': 19,
  'RLI': 20,
  'FSI': 21,
  'PDI': 22,
  'Left_To_Right': 0,
  'Right_To_Left': 1,
  'Arabic_Letter': 2,
  'European_Terminator': 5,
  'Boundary_Neutral': 9,
};

const _gcbCodes = <String, int>{
  'Other': 0,
  'CR': 1,
  'LF': 2,
  'Control': 3,
  'Extend': 4,
  'ZWJ': 5,
  'Regional_Indicator': 6,
  'Prepend': 7,
  'SpacingMark': 8,
  'L': 9,
  'V': 10,
  'T': 11,
  'LV': 12,
  'LVT': 13,
};

const _incbCodes = <String, int>{'Linker': 1, 'Consonant': 2, 'Extend': 3};

/// Format characters that terminals nevertheless draw with one column.
const _visibleFormat = <int>{
  0x00AD, // soft hyphen
  0x0600, 0x0601, 0x0602, 0x0603, 0x0604, 0x0605, 0x06DD, 0x070F, // PCM
  0x0890, 0x0891, 0x08E2, 0x110BD, 0x110CD,
};

const _maxCp = 0x10FFFF;

Future<void> main(List<String> args) async {
  final root = File.fromUri(Platform.script).parent.parent.path;
  final core = '$root/packages/twk_core';
  final cache = Directory('$root/tool/.ucd_cache')..createSync(recursive: true);
  final refresh = args.contains('--refresh');

  final text = <String, String>{};
  final client = HttpClient();
  try {
    for (final MapEntry(key: name, value: url) in _files.entries) {
      final f = File('${cache.path}/$name');
      if (refresh || !f.existsSync()) {
        stdout.writeln('download $url');
        final req = await client.getUrl(Uri.parse(url));
        final res = await req.close();
        if (res.statusCode != 200) {
          throw StateError('GET $url -> ${res.statusCode}');
        }
        await res.pipe(f.openWrite());
      }
      text[name] = f.readAsStringSync();
    }
  } finally {
    client.close();
  }

  final version = RegExp(r'GraphemeBreakProperty-(\d+\.\d+\.\d+)\.txt')
      .firstMatch(text['GraphemeBreakProperty.txt']!)!
      .group(1)!;
  final year = RegExp(r'© (\d{4}) Unicode')
      .firstMatch(text['GraphemeBreakProperty.txt']!)!
      .group(1)!;

  // ---- segmentation property ------------------------------------------------
  final seg = List<int>.filled(_maxCp + 1, 0);
  _parse(text['GraphemeBreakProperty.txt']!, (lo, hi, fields) {
    final code = _gcbCodes[fields[0]];
    if (code == null) {
      throw StateError('unknown GCB ${fields[0]}');
    }
    for (var c = lo; c <= hi; c++) {
      seg[c] = (seg[c] & ~0x0F) | code;
    }
  });
  // Lone surrogates can occur in Dart (UTF-16) strings. They are not valid
  // code points and UAX #29 leaves them as Other, which would let a
  // following Extend join them; they are treated as controls instead, so
  // they never join and are never drawn.
  for (var c = 0xD800; c <= 0xDFFF; c++) {
    seg[c] = (seg[c] & ~0x0F) | _gcbCodes['Control']!;
  }
  _parse(text['emoji-data.txt']!, (lo, hi, fields) {
    if (fields[0] != 'Extended_Pictographic') {
      return;
    }
    for (var c = lo; c <= hi; c++) {
      seg[c] |= 0x10;
    }
  });
  _parse(text['DerivedCoreProperties.txt']!, (lo, hi, fields) {
    if (fields[0] != 'InCB') {
      return;
    }
    final code = _incbCodes[fields[1]];
    if (code == null) {
      throw StateError('unknown InCB ${fields[1]}');
    }
    for (var c = lo; c <= hi; c++) {
      seg[c] = (seg[c] & ~0x60) | (code << 5);
    }
  });

  // ---- width property -------------------------------------------------------
  final eaw = List<String>.filled(_maxCp + 1, 'N');
  _parse(text['EastAsianWidth.txt']!, (lo, hi, fields) {
    for (var c = lo; c <= hi; c++) {
      eaw[c] = fields[0];
    }
  }, missing: true);
  final gc = List<String>.filled(_maxCp + 1, 'Cn');
  _parse(text['DerivedGeneralCategory.txt']!, (lo, hi, fields) {
    for (var c = lo; c <= hi; c++) {
      gc[c] = fields[0];
    }
  });
  final ignorable = List<bool>.filled(_maxCp + 1, false);
  _parse(text['DerivedCoreProperties.txt']!, (lo, hi, fields) {
    if (fields[0] != 'Default_Ignorable_Code_Point') {
      return;
    }
    for (var c = lo; c <= hi; c++) {
      ignorable[c] = true;
    }
  });
  final emoji = List<bool>.filled(_maxCp + 1, false);
  final emojiPresentation = List<bool>.filled(_maxCp + 1, false);
  _parse(text['emoji-data.txt']!, (lo, hi, fields) {
    final target = switch (fields[0]) {
      'Emoji' => emoji,
      'Emoji_Presentation' => emojiPresentation,
      _ => null,
    };
    if (target == null) {
      return;
    }
    for (var c = lo; c <= hi; c++) {
      target[c] = true;
    }
  });

  final width = List<int>.filled(_maxCp + 1, 0);
  for (var c = 0; c <= _maxCp; c++) {
    final cat = gc[c];
    final e = eaw[c];
    final wide = e == 'W' || e == 'F';
    int w;
    if (cat == 'Cc' || cat == 'Cs') {
      w = 0;
    } else if (cat == 'Mn' || cat == 'Me') {
      w = 0;
    } else if (cat == 'Cf' && !_visibleFormat.contains(c)) {
      w = 0;
    } else if ((c >= 0x1160 && c <= 0x11FF) || (c >= 0xD7B0 && c <= 0xD7FF)) {
      w = 0; // conjoining Hangul vowels / trailing consonants
    } else if (ignorable[c] && !wide && !_visibleFormat.contains(c)) {
      w = 0;
    } else if (wide) {
      w = 2;
    } else if (e == 'A') {
      w = 3;
    } else {
      w = 1;
    }
    if (emojiPresentation[c]) {
      w |= 0x04;
    }
    if (emoji[c]) {
      w |= 0x08;
    }
    width[c] = w;
  }

  // ---- bidi properties ------------------------------------------------------
  final bidiVersion = RegExp(r'DerivedBidiClass-(\d+\.\d+\.\d+)\.txt')
      .firstMatch(text['DerivedBidiClass.txt']!)!
      .group(1)!;
  if (bidiVersion != version) {
    throw StateError(
      'DerivedBidiClass.txt is $bidiVersion, GraphemeBreakProperty.txt '
      '$version: run with --refresh',
    );
  }
  final bidiClass = List<int>.filled(_maxCp + 1, 0);
  _parse(text['DerivedBidiClass.txt']!, (lo, hi, fields) {
    final code = _bidiCodes[fields[0]];
    if (code == null) {
      throw StateError('unknown Bidi_Class ${fields[0]}');
    }
    for (var c = lo; c <= hi; c++) {
      bidiClass[c] = code;
    }
  }, missing: true);
  final mirroring = <int>[];
  _parse(text['BidiMirroring.txt']!, (lo, hi, fields) {
    mirroring
      ..add(lo)
      ..add(int.parse(fields[0], radix: 16));
  });
  final brackets = <int>[];
  _parse(text['BidiBrackets.txt']!, (lo, hi, fields) {
    final type = switch (fields[1]) {
      'o' => 1,
      'c' => 2,
      _ => throw StateError('unknown Bidi_Paired_Bracket_Type ${fields[1]}'),
    };
    brackets
      ..add(lo)
      ..add(int.parse(fields[0], radix: 16))
      ..add(type);
  });

  final out = StringBuffer()
    ..write(_header(version, year, _sources))
    ..writeln()
    ..writeln('// Unformatted, lines of six triples run past 80 columns.')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln(
      '/// The version of the Unicode Character Database the segmentation, '
      'width',
    )
    ..writeln('/// and bidi tables are generated from.')
    ..writeln("const unicodeVersion = '$version';")
    ..writeln()
    ..writeln('/// Flat [start, end, value] triples (inclusive, sorted).')
    ..writeln('const segmentationRanges = <int>[')
    ..write(_ranges(seg))
    ..writeln('];')
    ..writeln()
    ..writeln('/// Flat [start, end, value] triples (inclusive, sorted).')
    ..writeln('const widthRanges = <int>[')
    ..write(_ranges(width))
    ..writeln('];');
  File('$core/lib/src/unicode/tables.g.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(out.toString());

  final bidi = StringBuffer()
    ..write(_header(version, year, _bidiSources))
    ..writeln()
    ..writeln(
      '/// Flat [start, end, Bidi_Class] triples (inclusive, sorted), the',
    )
    ..writeln(
      '/// class as the index of `BidiClass`; code points left out are L.',
    )
    ..writeln('const bidiClassRanges = <int>[')
    ..write(_ranges(bidiClass))
    ..writeln('];')
    ..writeln()
    ..writeln('/// Flat [code point, Bidi_Mirroring_Glyph] pairs, sorted.')
    ..writeln('const bidiMirroring = <int>[')
    ..write(_flat(mirroring, 2))
    ..writeln('];')
    ..writeln()
    ..writeln(
      '/// Flat [code point, Bidi_Paired_Bracket, Bidi_Paired_Bracket_Type]',
    )
    ..writeln('/// triples (type 1 open, 2 close), sorted.')
    ..writeln('const bidiBrackets = <int>[')
    ..write(_flat(brackets, 3))
    ..writeln('];');
  File('$core/lib/src/unicode/bidi_data.g.dart')
      .writeAsStringSync(bidi.toString());

  Directory('$core/test/data').createSync(recursive: true);
  File('$core/test/data/GraphemeBreakTest.txt')
      .writeAsStringSync(text['GraphemeBreakTest.txt']!);

  final format = Process.runSync('dart', [
    'format',
    '$core/lib/src/unicode/tables.g.dart',
    '$core/lib/src/unicode/bidi_data.g.dart',
  ]);
  if (format.exitCode != 0) {
    throw StateError('dart format: ${format.stderr}');
  }

  stdout.writeln('Unicode $version: tables written');
}

/// A generated file's header: that it is generated, the data files of the
/// Unicode Character Database [version] it is derived from, [sources], and
/// the licence they are under, whose copyright runs to [year].
String _header(String version, String year, List<String> sources) {
  final sb = StringBuffer()
    ..writeln('// GENERATED by tool/gen_unicode.dart - do not edit.')
    ..writeln('// Source: Unicode Character Database $version,')
    ..writeln('// https://www.unicode.org/Public/$version/ucd/:')
    ..writeln('//');
  for (final name in sources) {
    sb.writeln('//   ${_files[name]!.substring(_base.length + 1)}');
  }
  sb
    ..writeln('//')
    ..writeln(
      '// The tables below are derived from these Unicode data files and',
    )
    ..writeln('// are under the Unicode License v3, not the MIT License of the')
    ..writeln('// rest of this package:')
    ..writeln('//');
  for (final line in _unicodeLicense.replaceAll('{year}', year).split('\n')) {
    sb.writeln(line.isEmpty ? '//' : '// $line');
  }
  return sb.toString();
}

String _ranges(List<int> values) {
  final sb = StringBuffer();
  var start = 0;
  var count = 0;
  final line = StringBuffer();
  void flush(int end) {
    if (values[start] != 0) {
      line.write(
        '0x${start.toRadixString(16)},0x${end.toRadixString(16)},'
        '${values[start]},',
      );
      if (++count % 6 == 0) {
        sb.writeln('  $line');
        line.clear();
      }
    }
  }

  for (var c = 1; c <= _maxCp; c++) {
    if (values[c] != values[start]) {
      flush(c - 1);
      start = c;
    }
  }
  flush(_maxCp);
  if (line.isNotEmpty) {
    sb.writeln('  $line');
  }
  return sb.toString();
}

/// [values] as hexadecimal code points, [width] to a line, the last of
/// each group (a type) in decimal when [width] is 3.
String _flat(List<int> values, int width) {
  final sb = StringBuffer();
  for (var i = 0; i < values.length; i += width) {
    sb.write(' ');
    for (var k = 0; k < width; k++) {
      final v = values[i + k];
      sb.write(k == 2 ? ' $v,' : ' 0x${v.toRadixString(16)},');
    }
    sb.writeln();
  }
  return sb.toString();
}

/// Calls [onRange] for every data line (and, when [missing] is set, for every
/// `# @missing:` default line, which always precede the explicit data).
void _parse(
  String text,
  void Function(int lo, int hi, List<String> fields) onRange, {
  bool missing = false,
}) {
  for (var raw in text.split('\n')) {
    if (raw.startsWith('# @missing:')) {
      if (!missing) {
        continue;
      }
      raw = raw.substring('# @missing:'.length);
    } else {
      final hash = raw.indexOf('#');
      if (hash >= 0) {
        raw = raw.substring(0, hash);
      }
    }
    if (raw.trim().isEmpty) {
      continue;
    }
    final parts = raw.split(';').map((s) => s.trim()).toList();
    final range = parts[0].split('..');
    final lo = int.parse(range[0], radix: 16);
    final hi = range.length > 1 ? int.parse(range[1], radix: 16) : lo;
    onRange(lo, hi, parts.sublist(1));
  }
}
