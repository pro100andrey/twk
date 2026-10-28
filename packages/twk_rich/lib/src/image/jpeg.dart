// This decoder is based in part on the work of the Independent JPEG Group.
// Translated from libjpeg into Dart: _idct from jpeg_idct_islow
// (jidctint.c), the colour tables _crToR, _cbToB, _crToG and _cbToG from
// build_ycc_rgb_table (jdcolor.c), and _Decoder._refineAc from
// decode_mcu_AC_refine (jdphuff.c).
//
// The walk through a scan's MCUs (_Decoder._scan), the baseline, DC and
// first AC block decoding (_Decoder._block, modes 0 to 3) and the colour
// transform of three components follow jpgjs: pdf.js's src/core/jpg.js,
// Copyright 2014 Mozilla Foundation, under the Apache License 2.0, and its
// Dart port in package:image, Copyright (c) 2013-2022 Brendan Duncan,
// under the MIT License. They were changed for this decoder.
//
// This package's NOTICE names the files and lines each part follows and
// what was changed, and carries the licences, which those parts keep.

import 'dart:typed_data';

import 'bitmap.dart';
import 'limits.dart';

// Examples can assume:
// import 'dart:io';

/// Whether [bytes] start as a JPEG file does: SOI and another marker.
bool isJpeg(List<int> bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xFF &&
    bytes[1] == 0xD8 &&
    bytes[2] == 0xFF;

/// Decodes a JPEG file.
///
/// Read are baseline and extended sequential (8-bit samples, Huffman
/// coding, quantization tables of 8 or 16 bits) and progressive JPEG,
/// with restart intervals, of one component (grey), three (YCbCr, or RGB
/// where an Adobe marker or the components' ids say so) or four (CMYK or
/// YCCK, the inks stored inverted as Adobe writes them), each sampled at
/// any factors from 1 to 4. The samples are those of libjpeg's integer
/// IDCT and colour conversion; subsampled chroma is replicated, not
/// interpolated. Arithmetic coding, lossless, hierarchical and 12-bit JPEG
/// are not read, nor is a height given by a DNL marker. The Exif
/// orientation is not applied, nor is a colour profile.
///
/// Throws a [FormatException] when [bytes] are not such a JPEG file or its
/// headers are cut short; entropy-coded data cut short decodes as zeros,
/// so the image's end shows grey.
///
/// ```dart
/// final photo = decodeJpeg(File('photo.jpg').readAsBytesSync());
/// print('${photo.width} × ${photo.height}');
/// ```
///
/// See also:
///
///  * `decodeImage`, for a file that may be a PNG too.
Bitmap decodeJpeg(Uint8List bytes) {
  if (!isJpeg(bytes)) {
    throw const FormatException('Not a JPEG file');
  }
  return _Decoder(bytes).decode();
}

/// The position in a block, in natural (row by row) order, of each
/// coefficient in zigzag order; 16 more for the runs of corrupt data.
final _zigzag = Uint8List.fromList([
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, //
  12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
  63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63,
]);

/// A Huffman table: codes of up to 9 bits found by a lookup, longer ones
/// by the largest code of each length.
final class _Huffman {
  _Huffman(Uint8List counts, this.values) {
    var code = 0;
    var k = 0;
    for (var length = 1; length <= 16; length++) {
      final count = counts[length - 1];
      valueOffset[length] = k - code;
      for (var i = 0; i < count; i++, code++, k++) {
        if (length <= 9 && k < values.length) {
          final shift = 9 - length;
          final entry = length << 8 | values[k];
          for (var j = code << shift; j < (code + 1) << shift; j++) {
            lookup[j] = entry;
          }
        }
      }
      maxCode[length] = count > 0 ? code - 1 : -1;
      code <<= 1;
    }
  }

  final Uint8List values;

  /// For each 9 bits, the length of the code they start with shifted left
  /// by 8 and its value; 0 where the code is longer.
  final lookup = Uint16List(512);
  final maxCode = Int32List(17);
  final valueOffset = Int32List(17);
}

final class _Component {
  _Component(this.id, this.h, this.v, this.table);

  final int id;
  final int h;
  final int v;
  final int table;

  /// Blocks across and down, padded to whole MCUs.
  var blocksPerLine = 0;
  var blocksPerColumn = 0;

  /// Blocks across and down that cover the component's samples, those of
  /// a scan of it alone.
  var scanBlocksWide = 0;
  var scanBlocksHigh = 0;

  var coefficients = Int16List(0);
  _Huffman? dc;
  _Huffman? ac;
  var prediction = 0;
}

final class _Decoder {
  _Decoder(this.bytes);

  final Uint8List bytes;
  final _quantization = List<Int32List?>.filled(4, null);
  final _dcTables = List<_Huffman?>.filled(4, null);
  final _acTables = List<_Huffman?>.filled(4, null);
  List<_Component> _components = const [];
  var _width = 0;
  var _height = 0;
  var _progressive = false;
  var _hMax = 1;
  var _vMax = 1;
  var _mcusPerLine = 0;
  var _mcusPerColumn = 0;
  var _restartInterval = 0;
  var _jfif = false;
  var _adobeTransform = -1;

  // The entropy-coded data being read.
  var _pos = 0;
  var _bits = 0;
  var _bitCount = 0;
  var _atMarker = false;
  var _eobRun = 0;

  Bitmap decode() {
    final bytes = this.bytes;
    var pos = 2;
    while (pos + 1 < bytes.length) {
      if (bytes[pos] != 0xFF) {
        pos++;
        continue;
      }
      final marker = bytes[pos + 1];
      pos += 2;
      if (marker == 0xFF) {
        pos--;
        continue;
      }
      if (marker == 0xD9) {
        break;
      }
      if (marker == 0xD8 ||
          marker == 0x01 ||
          marker >= 0xD0 && marker <= 0xD7) {
        continue;
      }
      if (pos + 2 > bytes.length) {
        throw const FormatException('JPEG file cut short');
      }
      final end = pos + (bytes[pos] << 8 | bytes[pos + 1]);
      if (end > bytes.length || end < pos + 2) {
        throw const FormatException('JPEG file cut short');
      }
      final start = pos + 2;
      switch (marker) {
        case 0xC0 || 0xC1 || 0xC2:
          _frame(start, end, progressive: marker == 0xC2);
        case 0xC4:
          _huffmanTables(start, end);
        case 0xDB:
          _quantizationTables(start, end);
        case 0xDD:
          if (end - start < 2) {
            throw const FormatException('JPEG DRI cut short');
          }
          _restartInterval = bytes[start] << 8 | bytes[start + 1];
        case 0xDA:
          pos = _scan(start, end);
          continue;
        case 0xE0:
          _jfif = _startsWith(start, end, 'JFIF\x00');
        case 0xEE:
          if (_startsWith(start, end, 'Adobe') && end - start >= 12) {
            _adobeTransform = bytes[start + 11];
          }
        case 0xC3 || 0xC5 || 0xC6 || 0xC7:
        case 0xC9 || 0xCA || 0xCB || 0xCD || 0xCE || 0xCF:
          throw const FormatException(
            'Lossless, hierarchical and arithmetic-coded JPEG are not '
            'supported',
          );
        default:
          break;
      }
      pos = end;
    }
    if (_components.isEmpty) {
      throw const FormatException('JPEG file without a frame');
    }
    return _output();
  }

  bool _startsWith(int start, int end, String text) {
    if (end - start < text.length) {
      return false;
    }
    for (var i = 0; i < text.length; i++) {
      if (bytes[start + i] != text.codeUnitAt(i)) {
        return false;
      }
    }
    return true;
  }

  void _quantizationTables(int start, int end) {
    var pos = start;
    while (pos < end) {
      final wide = bytes[pos] >> 4 != 0;
      final id = bytes[pos] & 3;
      pos++;
      if (pos + (wide ? 128 : 64) > end) {
        throw const FormatException('JPEG DQT cut short');
      }
      final table = Int32List(64);
      for (var k = 0; k < 64; k++) {
        table[_zigzag[k]] = wide
            ? bytes[pos] << 8 | bytes[pos + 1]
            : bytes[pos];
        pos += wide ? 2 : 1;
      }
      _quantization[id] = table;
    }
  }

  void _huffmanTables(int start, int end) {
    var pos = start;
    while (pos < end) {
      final ac = bytes[pos] >> 4 != 0;
      final id = bytes[pos] & 3;
      if (pos + 17 > end) {
        throw const FormatException('JPEG DHT cut short');
      }
      final counts = Uint8List.sublistView(bytes, pos + 1, pos + 17);
      var total = 0;
      for (final count in counts) {
        total += count;
      }
      pos += 17;
      if (pos + total > end) {
        throw const FormatException('JPEG DHT cut short');
      }
      final table = _Huffman(
        counts,
        Uint8List.fromList(Uint8List.sublistView(bytes, pos, pos + total)),
      );
      pos += total;
      (ac ? _acTables : _dcTables)[id] = table;
    }
  }

  void _frame(int start, int end, {required bool progressive}) {
    if (_components.isNotEmpty) {
      throw const FormatException('JPEG with more than one frame');
    }
    if (end - start < 6) {
      throw const FormatException('JPEG SOF cut short');
    }
    if (bytes[start] != 8) {
      throw FormatException(
        'JPEG of ${bytes[start]}-bit samples is not supported',
      );
    }
    _progressive = progressive;
    _height = bytes[start + 1] << 8 | bytes[start + 2];
    _width = bytes[start + 3] << 8 | bytes[start + 4];
    final count = bytes[start + 5];
    if (_width == 0 || _height == 0) {
      throw const FormatException(
        'JPEG whose height a DNL marker gives is not supported',
      );
    }
    if (_width * _height > maxImagePixels) {
      throw FormatException('JPEG of $_width × $_height pixels');
    }
    if (count != 1 && count != 3 && count != 4 || end - start < 6 + count * 3) {
      throw FormatException('JPEG of $count components is not supported');
    }
    _components = [
      for (var i = 0, pos = start + 6; i < count; i++, pos += 3)
        _Component(
          bytes[pos],
          bytes[pos + 1] >> 4,
          bytes[pos + 1] & 15,
          bytes[pos + 2] & 3,
        ),
    ];
    for (final c in _components) {
      if (c.h < 1 || c.h > 4 || c.v < 1 || c.v > 4) {
        throw const FormatException('JPEG sampling factor out of range');
      }
      if (c.h > _hMax) {
        _hMax = c.h;
      }
      if (c.v > _vMax) {
        _vMax = c.v;
      }
    }
    _mcusPerLine = (_width + 8 * _hMax - 1) ~/ (8 * _hMax);
    _mcusPerColumn = (_height + 8 * _vMax - 1) ~/ (8 * _vMax);
    for (final c in _components) {
      c
        ..blocksPerLine = _mcusPerLine * c.h
        ..blocksPerColumn = _mcusPerColumn * c.v
        ..scanBlocksWide = ((_width * c.h + _hMax - 1) ~/ _hMax + 7) >> 3
        ..scanBlocksHigh = ((_height * c.v + _vMax - 1) ~/ _vMax + 7) >> 3
        ..coefficients = Int16List(c.blocksPerLine * c.blocksPerColumn * 64);
    }
  }

  /// Decodes the scan whose header is from [start] to [end]; returns where
  /// the marker after its data is.
  int _scan(int start, int end) {
    if (_components.isEmpty) {
      throw const FormatException('JPEG scan before its frame');
    }
    final count = bytes[start];
    if (count < 1 || count > 4 || end - start < 4 + count * 2) {
      throw const FormatException('JPEG SOS cut short');
    }
    final components = <_Component>[];
    for (var i = 0, pos = start + 1; i < count; i++, pos += 2) {
      final id = bytes[pos];
      final c = _components.firstWhere(
        (c) => c.id == id,
        orElse: () => throw FormatException('JPEG scan of component $id'),
      );
      components.add(
        c
          ..dc = _dcTables[bytes[pos + 1] >> 4 & 3]
          ..ac = _acTables[bytes[pos + 1] & 3],
      );
    }
    final pos = start + 1 + count * 2;
    final ss = bytes[pos];
    final se = bytes[pos + 1];
    final ah = bytes[pos + 2] >> 4;
    final al = bytes[pos + 2] & 15;
    final dcOnly = _progressive && ss == 0;
    for (final c in components) {
      final missing = _progressive
          ? (ss == 0 ? ah == 0 && c.dc == null : c.ac == null)
          : c.dc == null || c.ac == null;
      if (missing) {
        throw const FormatException('JPEG scan without its Huffman table');
      }
    }
    _pos = end;
    _bits = 0;
    _bitCount = 0;
    _atMarker = false;
    _eobRun = 0;
    for (final c in components) {
      c.prediction = 0;
    }
    final mode = !_progressive
        ? 0
        : dcOnly
        ? (ah == 0 ? 1 : 2)
        : (ah == 0 ? 3 : 4);
    final single = components.length == 1;
    final first = components.first;
    final mcus = single
        ? first.scanBlocksWide * first.scanBlocksHigh
        : _mcusPerLine * _mcusPerColumn;
    for (var mcu = 0; mcu < mcus; mcu++) {
      if (_restartInterval > 0 && mcu > 0 && mcu % _restartInterval == 0) {
        _restart(components);
      }
      if (single) {
        final row = mcu ~/ first.scanBlocksWide;
        final column = mcu % first.scanBlocksWide;
        _block(
          first,
          (row * first.blocksPerLine + column) * 64,
          mode,
          ss,
          se,
          al,
        );
      } else {
        final mcuRow = mcu ~/ _mcusPerLine;
        final mcuColumn = mcu % _mcusPerLine;
        for (final c in components) {
          for (var v = 0; v < c.v; v++) {
            final row = mcuRow * c.v + v;
            for (var h = 0; h < c.h; h++) {
              final column = mcuColumn * c.h + h;
              _block(
                c,
                (row * c.blocksPerLine + column) * 64,
                mode,
                ss,
                se,
                al,
              );
            }
          }
        }
      }
    }
    return _nextMarker();
  }

  /// Where the marker after the entropy-coded data is: the first 0xFF not
  /// followed by 0 or a restart marker.
  int _nextMarker() {
    var pos = _pos;
    while (pos + 1 < bytes.length) {
      if (bytes[pos] == 0xFF) {
        final next = bytes[pos + 1];
        if (next != 0 && (next < 0xD0 || next > 0xD7)) {
          return pos;
        }
      }
      pos++;
    }
    return bytes.length;
  }

  /// Steps over a restart marker and resets what it resets.
  void _restart(List<_Component> components) {
    _bits = 0;
    _bitCount = 0;
    var pos = _pos;
    var ended = false;
    while (pos + 1 < bytes.length &&
        !(bytes[pos] == 0xFF &&
            bytes[pos + 1] >= 0xD0 &&
            bytes[pos + 1] <= 0xD7)) {
      if (bytes[pos] == 0xFF && bytes[pos + 1] != 0 && bytes[pos + 1] != 0xFF) {
        // Another marker: the data ends early, and the rest decodes as
        // zeros from predictions reset as libjpeg resets them.
        ended = true;
        break;
      }
      pos++;
    }
    _pos = ended ? pos : pos + 2;
    _atMarker = ended;
    _eobRun = 0;
    for (final c in components) {
      c.prediction = 0;
    }
  }

  void _fill() {
    final bytes = this.bytes;
    while (_bitCount <= 24) {
      var byte = 0;
      if (!_atMarker && _pos < bytes.length) {
        byte = bytes[_pos];
        if (byte == 0xFF) {
          final next = _pos + 1 < bytes.length ? bytes[_pos + 1] : 0xD9;
          if (next == 0) {
            _pos += 2;
          } else {
            _atMarker = true;
            byte = 0;
          }
        } else {
          _pos++;
        }
      }
      _bits = (_bits << 8 | byte) & 0xFFFFFFFF;
      _bitCount += 8;
    }
  }

  int _bit() {
    if (_bitCount == 0) {
      _fill();
    }
    _bitCount--;
    return _bits >> _bitCount & 1;
  }

  int _receive(int length) {
    if (_bitCount < length) {
      _fill();
    }
    _bitCount -= length;
    return _bits >> _bitCount & (1 << length) - 1;
  }

  int _extend(int length) {
    final value = _receive(length);
    return value < 1 << (length - 1) ? value - (1 << length) + 1 : value;
  }

  int _decode(_Huffman table) {
    if (_bitCount < 16) {
      _fill();
    }
    final entry = table.lookup[_bits >> (_bitCount - 9) & 0x1FF];
    if (entry != 0) {
      _bitCount -= entry >> 8;
      return entry & 0xFF;
    }
    for (var length = 10; length <= 16; length++) {
      final code = _bits >> (_bitCount - length) & (1 << length) - 1;
      if (code <= table.maxCode[length]) {
        _bitCount -= length;
        final index = table.valueOffset[length] + code;
        return index < table.values.length ? table.values[index] : 0;
      }
    }
    // Not a code of the table: corrupt data, read as a zero.
    return 0;
  }

  void _block(_Component c, int at, int mode, int ss, int se, int al) {
    final coefficients = c.coefficients;
    switch (mode) {
      case 0:
        final t = _decode(c.dc!);
        c.prediction += t == 0 ? 0 : _extend(t);
        coefficients[at] = c.prediction;
        final ac = c.ac!;
        for (var k = 1; k < 64;) {
          final rs = _decode(ac);
          final s = rs & 15;
          final r = rs >> 4;
          if (s == 0) {
            if (r < 15) {
              break;
            }
            k += 16;
            continue;
          }
          k += r;
          coefficients[at + _zigzag[k]] = _extend(s);
          k++;
        }
      case 1:
        final t = _decode(c.dc!);
        c.prediction += t == 0 ? 0 : _extend(t);
        coefficients[at] = c.prediction << al;
      case 2:
        if (_bit() != 0) {
          coefficients[at] |= 1 << al;
        }
      case 3:
        if (_eobRun > 0) {
          _eobRun--;
          return;
        }
        final ac = c.ac!;
        for (var k = ss; k <= se;) {
          final rs = _decode(ac);
          final s = rs & 15;
          final r = rs >> 4;
          if (s == 0) {
            if (r < 15) {
              _eobRun = (1 << r) - 1;
              if (r > 0) {
                _eobRun += _receive(r);
              }
              break;
            }
            k += 16;
            continue;
          }
          k += r;
          coefficients[at + _zigzag[k]] = _extend(s) * (1 << al);
          k++;
        }
      default:
        _refineAc(coefficients, at, c.ac!, ss, se, al);
    }
  }

  /// A progressive scan refining AC coefficients, as libjpeg's
  /// decode_mcu_AC_refine.
  void _refineAc(
    Int16List coefficients,
    int at,
    _Huffman ac,
    int ss,
    int se,
    int al,
  ) {
    final p1 = 1 << al;
    final m1 = -1 << al;
    var k = ss;
    if (_eobRun == 0) {
      for (; k <= se; k++) {
        final rs = _decode(ac);
        var r = rs >> 4;
        var s = rs & 15;
        if (s != 0) {
          s = _bit() != 0 ? p1 : m1;
        } else if (r != 15) {
          _eobRun = 1 << r;
          if (r > 0) {
            _eobRun += _receive(r);
          }
          break;
        }
        while (k <= se) {
          final z = at + _zigzag[k];
          final coefficient = coefficients[z];
          if (coefficient != 0) {
            if (_bit() != 0 && coefficient & p1 == 0) {
              coefficients[z] = coefficient + (coefficient >= 0 ? p1 : m1);
            }
          } else {
            if (--r < 0) {
              break;
            }
          }
          k++;
        }
        if (s != 0 && k <= 63) {
          coefficients[at + _zigzag[k]] = s;
        }
      }
    }
    if (_eobRun > 0) {
      for (; k <= se; k++) {
        final z = at + _zigzag[k];
        final coefficient = coefficients[z];
        if (coefficient != 0 && _bit() != 0 && coefficient & p1 == 0) {
          coefficients[z] = coefficient + (coefficient >= 0 ? p1 : m1);
        }
      }
      _eobRun--;
    }
  }

  Bitmap _output() {
    final planes = [for (final c in _components) _plane(c)];
    final width = _width;
    final height = _height;
    final out = Uint8List(width * height * 4);
    final count = _components.length;
    final columns = [
      for (final c in _components)
        Int32List.fromList([
          for (var x = 0; x < width; x++) x * c.h ~/ _hMax,
        ]),
    ];
    final transform = switch (count) {
      1 => _Transform.grey,
      3 when _adobeTransform == 0 => _Transform.none,
      3 when _adobeTransform < 0 && !_jfif && _rgbIds => _Transform.none,
      3 => _Transform.ycc,
      _ when _adobeTransform == 2 => _Transform.ycck,
      _ => _Transform.cmyk,
    };
    final c0 = planes[0];
    final x0 = columns[0];
    final stride0 = _components[0].blocksPerLine * 8;
    for (var y = 0; y < height; y++) {
      final row0 = y * _components[0].v ~/ _vMax * stride0;
      var o = y * width * 4;
      if (transform == _Transform.grey) {
        for (var x = 0; x < width; x++, o += 4) {
          final g = c0[row0 + x0[x]];
          out[o] = g;
          out[o + 1] = g;
          out[o + 2] = g;
          out[o + 3] = 255;
        }
        continue;
      }
      final c1 = planes[1];
      final c2 = planes[2];
      final x1 = columns[1];
      final x2 = columns[2];
      final row1 =
          y * _components[1].v ~/ _vMax * _components[1].blocksPerLine * 8;
      final row2 =
          y * _components[2].v ~/ _vMax * _components[2].blocksPerLine * 8;
      final c3 = count == 4 ? planes[3] : null;
      final x3 = count == 4 ? columns[3] : null;
      final row3 = count == 4
          ? y * _components[3].v ~/ _vMax * _components[3].blocksPerLine * 8
          : 0;
      for (var x = 0; x < width; x++, o += 4) {
        var a = c0[row0 + x0[x]];
        var b = c1[row1 + x1[x]];
        var c = c2[row2 + x2[x]];
        if (transform != _Transform.none && transform != _Transform.cmyk) {
          final y0 = a;
          a = _clamp(y0 + _crToR[c]);
          final g = _clamp(y0 + ((_cbToG[b] + _crToG[c]) >> 16));
          final blue = _clamp(y0 + _cbToB[b]);
          b = g;
          c = blue;
          if (transform == _Transform.ycck) {
            a = 255 - a;
            b = 255 - b;
            c = 255 - c;
          }
        }
        if (c3 != null) {
          final k = c3[row3 + x3![x]];
          a = (a * k + 127) ~/ 255;
          b = (b * k + 127) ~/ 255;
          c = (c * k + 127) ~/ 255;
        }
        out[o] = a;
        out[o + 1] = b;
        out[o + 2] = c;
        out[o + 3] = 255;
      }
    }
    return Bitmap.fromRgba(width, height, out);
  }

  bool get _rgbIds =>
      _components[0].id == 0x52 &&
      _components[1].id == 0x47 &&
      _components[2].id == 0x42;

  /// The samples of [c], dequantized and transformed back, a block's 8 × 8
  /// samples for each of its blocks.
  Uint8List _plane(_Component c) {
    final table = _quantization[c.table];
    if (table == null) {
      throw const FormatException('JPEG without its quantization table');
    }
    final stride = c.blocksPerLine * 8;
    final plane = Uint8List(stride * c.blocksPerColumn * 8);
    final workspace = Int32List(64);
    final coefficients = c.coefficients;
    for (var row = 0; row < c.blocksPerColumn; row++) {
      for (var column = 0; column < c.blocksPerLine; column++) {
        _idct(
          coefficients,
          (row * c.blocksPerLine + column) * 64,
          table,
          workspace,
          plane,
          row * 8 * stride + column * 8,
          stride,
        );
      }
    }
    return plane;
  }
}

enum _Transform { grey, none, ycc, ycck, cmyk }

int _clamp(int v) => v < 0
    ? 0
    : v > 255
    ? 255
    : v;

// libjpeg's colour conversion tables (jdcolor.c), 16 bits of fraction.
final Int32List _crToR = _table((x) => (91881 * x + 32768) >> 16);
final Int32List _cbToB = _table((x) => (116130 * x + 32768) >> 16);
final Int32List _crToG = _table((x) => -46802 * x);
final Int32List _cbToG = _table((x) => -22554 * x + 32768);

Int32List _table(int Function(int) f) =>
    Int32List.fromList([for (var i = 0; i < 256; i++) f(i - 128)]);

// libjpeg's islow IDCT (jidctint.c): 13 bits of fraction in the constants,
// 2 bits more kept between the passes.
const _fix0298631336 = 2446;
const _fix0390180644 = 3196;
const _fix0541196100 = 4433;
const _fix0765366865 = 6270;
const _fix0899976223 = 7373;
const _fix1175875602 = 9633;
const _fix1501321110 = 12299;
const _fix1847759065 = 15137;
const _fix1961570560 = 16069;
const _fix2053119869 = 16819;
const _fix2562915447 = 20995;
const _fix3072711026 = 25172;

void _idct(
  Int16List input,
  int at,
  Int32List quantization,
  Int32List workspace,
  Uint8List out,
  int outAt,
  int stride,
) {
  // Columns, into the workspace.
  for (var column = 0; column < 8; column++) {
    final i = at + column;
    if (input[i + 8] == 0 &&
        input[i + 16] == 0 &&
        input[i + 24] == 0 &&
        input[i + 32] == 0 &&
        input[i + 40] == 0 &&
        input[i + 48] == 0 &&
        input[i + 56] == 0) {
      final dc = input[i] * quantization[column] << 2;
      for (var row = 0; row < 64; row += 8) {
        workspace[row + column] = dc;
      }
      continue;
    }
    var z2 = input[i + 16] * quantization[column + 16];
    var z3 = input[i + 48] * quantization[column + 48];
    var z1 = (z2 + z3) * _fix0541196100;
    var tmp2 = z1 + z3 * -_fix1847759065;
    var tmp3 = z1 + z2 * _fix0765366865;
    z2 = input[i] * quantization[column];
    z3 = input[i + 32] * quantization[column + 32];
    var tmp0 = (z2 + z3) << 13;
    var tmp1 = (z2 - z3) << 13;
    final tmp10 = tmp0 + tmp3;
    final tmp13 = tmp0 - tmp3;
    final tmp11 = tmp1 + tmp2;
    final tmp12 = tmp1 - tmp2;
    tmp0 = input[i + 56] * quantization[column + 56];
    tmp1 = input[i + 40] * quantization[column + 40];
    tmp2 = input[i + 24] * quantization[column + 24];
    tmp3 = input[i + 8] * quantization[column + 8];
    z1 = tmp0 + tmp3;
    z2 = tmp1 + tmp2;
    z3 = tmp0 + tmp2;
    var z4 = tmp1 + tmp3;
    final z5 = (z3 + z4) * _fix1175875602;
    tmp0 *= _fix0298631336;
    tmp1 *= _fix2053119869;
    tmp2 *= _fix3072711026;
    tmp3 *= _fix1501321110;
    z1 *= -_fix0899976223;
    z2 *= -_fix2562915447;
    z3 = z3 * -_fix1961570560 + z5;
    z4 = z4 * -_fix0390180644 + z5;
    tmp0 += z1 + z3;
    tmp1 += z2 + z4;
    tmp2 += z2 + z3;
    tmp3 += z1 + z4;
    const round = 1 << 10;
    workspace[column] = (tmp10 + tmp3 + round) >> 11;
    workspace[column + 56] = (tmp10 - tmp3 + round) >> 11;
    workspace[column + 8] = (tmp11 + tmp2 + round) >> 11;
    workspace[column + 48] = (tmp11 - tmp2 + round) >> 11;
    workspace[column + 16] = (tmp12 + tmp1 + round) >> 11;
    workspace[column + 40] = (tmp12 - tmp1 + round) >> 11;
    workspace[column + 24] = (tmp13 + tmp0 + round) >> 11;
    workspace[column + 32] = (tmp13 - tmp0 + round) >> 11;
  }
  // Rows, into the samples, 128 added.
  for (var row = 0; row < 64; row += 8) {
    final o = outAt + (row >> 3) * stride;
    if (workspace[row + 1] == 0 &&
        workspace[row + 2] == 0 &&
        workspace[row + 3] == 0 &&
        workspace[row + 4] == 0 &&
        workspace[row + 5] == 0 &&
        workspace[row + 6] == 0 &&
        workspace[row + 7] == 0) {
      final dc = _clamp(((workspace[row] + 16) >> 5) + 128);
      for (var x = 0; x < 8; x++) {
        out[o + x] = dc;
      }
      continue;
    }
    var z2 = workspace[row + 2];
    var z3 = workspace[row + 6];
    var z1 = (z2 + z3) * _fix0541196100;
    var tmp2 = z1 + z3 * -_fix1847759065;
    var tmp3 = z1 + z2 * _fix0765366865;
    var tmp0 = (workspace[row] + workspace[row + 4]) << 13;
    var tmp1 = (workspace[row] - workspace[row + 4]) << 13;
    final tmp10 = tmp0 + tmp3;
    final tmp13 = tmp0 - tmp3;
    final tmp11 = tmp1 + tmp2;
    final tmp12 = tmp1 - tmp2;
    tmp0 = workspace[row + 7];
    tmp1 = workspace[row + 5];
    tmp2 = workspace[row + 3];
    tmp3 = workspace[row + 1];
    z1 = tmp0 + tmp3;
    z2 = tmp1 + tmp2;
    z3 = tmp0 + tmp2;
    var z4 = tmp1 + tmp3;
    final z5 = (z3 + z4) * _fix1175875602;
    tmp0 *= _fix0298631336;
    tmp1 *= _fix2053119869;
    tmp2 *= _fix3072711026;
    tmp3 *= _fix1501321110;
    z1 *= -_fix0899976223;
    z2 *= -_fix2562915447;
    z3 = z3 * -_fix1961570560 + z5;
    z4 = z4 * -_fix0390180644 + z5;
    tmp0 += z1 + z3;
    tmp1 += z2 + z4;
    tmp2 += z2 + z3;
    tmp3 += z1 + z4;
    const round = 1 << 17;
    out[o] = _clamp(((tmp10 + tmp3 + round) >> 18) + 128);
    out[o + 7] = _clamp(((tmp10 - tmp3 + round) >> 18) + 128);
    out[o + 1] = _clamp(((tmp11 + tmp2 + round) >> 18) + 128);
    out[o + 6] = _clamp(((tmp11 - tmp2 + round) >> 18) + 128);
    out[o + 2] = _clamp(((tmp12 + tmp1 + round) >> 18) + 128);
    out[o + 5] = _clamp(((tmp12 - tmp1 + round) >> 18) + 128);
    out[o + 3] = _clamp(((tmp13 + tmp0 + round) >> 18) + 128);
    out[o + 4] = _clamp(((tmp13 - tmp0 + round) >> 18) + 128);
  }
}
