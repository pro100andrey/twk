/// Writes the fixtures of the QR tests from two encoders other than this
/// package's, zint (2.16) and libqrencode's `qrencode` (4.1), which must
/// be installed: `dart run test/qr/generate.dart`, from the package's
/// directory.
///
/// `fixtures/symbols.txt` has a line per case of `cases.dart`: the
/// version and level, the hash (`moduleHash`) of the symbol zint makes of
/// its data under each of the eight masks, the mask zint chooses, and the
/// mask qrencode chooses, whose symbol must be the one zint makes under it.
/// `fixtures/capacity.txt` has a line per version and level: the most
/// characters qrencode puts in a symbol of that version in each mode,
/// numeric, alphanumeric and byte.
library;

import 'dart:io';

import 'package:twk_rich/src/qr/symbol.dart';

import 'cases.dart';

Future<void> main() async {
  final symbols = StringBuffer(
    "# version-level, the hashes of zint's symbols under masks 0 to 7, "
    'the masks zint and qrencode choose\n',
  );
  for (final c in qrCases()) {
    final hashes = <String>[];
    for (var mask = 0; mask < 8; mask++) {
      hashes.add(_hash(await _zint(c, mask)));
    }
    final zintMask = hashes.indexOf(_hash(await _zint(c, null)));
    final qrencodeMask = hashes.indexOf(_hash(await _qrencode(c)));
    if (zintMask < 0 || qrencodeMask < 0) {
      throw StateError('$c: zint and qrencode make different symbols');
    }
    symbols.writeln(
      '${c.version}-${c.levelLetter} ${hashes.join(' ')} '
      '$zintMask $qrencodeMask',
    );
    stdout.write('.');
  }
  File('test/qr/fixtures/symbols.txt').writeAsStringSync('$symbols');

  final capacity = StringBuffer(
    '# version-level, the most characters qrencode puts in it: numeric, '
    'alphanumeric, byte\n',
  );
  for (var version = 1; version <= 40; version++) {
    for (final level in QrErrorCorrection.values) {
      final most = [
        for (final mode in QrMode.values) await _most(version, level, mode),
      ];
      capacity.writeln('$version-${'LMQH'[level.index]} ${most.join(' ')}');
      stdout.write('.');
    }
  }
  File('test/qr/fixtures/capacity.txt').writeAsStringSync('$capacity');
  stdout.writeln();
}

/// The modules zint makes of [c]'s data under [mask], or the mask it
/// chooses: rows of 0 and 1.
Future<List<String>> _zint(QrCase c, int? mask) async {
  final process = await Process.start('zint', [
    '-b',
    'QRCODE',
    '--dump',
    '--binary',
    '--secure=${c.level.index + 1}',
    '--vers=${c.version}',
    if (mask != null) '--mask=$mask',
    '-i',
    '-',
  ]);
  process.stdin.add(c.data);
  await process.stdin.close();
  final out = await process.stdout
      .transform(const SystemEncoding().decoder)
      .join();
  if (await process.exitCode != 0) {
    throw StateError('zint failed on $c');
  }
  final size = 4 * c.version + 17;
  return [
    for (final line in out.trim().split('\n'))
      line
          .split(' ')
          .map(
            (hex) => int.parse(
              hex,
              radix: 16,
            ).toRadixString(2).padLeft(4 * hex.length, '0'),
          )
          .join()
          .substring(0, size),
  ];
}

/// The modules qrencode makes of [c]'s data at its version and level:
/// rows of 0 and 1.
Future<List<String>> _qrencode(QrCase c) async {
  final out = await _run([
    '-t',
    'ASCII',
    '-m',
    '0',
    '-l',
    c.levelLetter,
    '-v',
    '${c.version}',
    if (c.mode == QrMode.byte) '-8',
  ], c.data);
  return [
    for (final line in out.split('\n'))
      if (line.isNotEmpty)
        [
          for (var i = 0; i < line.length; i += 2)
            if (line[i] == '#') '1' else '0',
        ].join(),
  ];
}

/// The most characters of [mode] qrencode puts in a symbol of [version] at
/// [level]: the longest data whose symbol is no bigger.
Future<int> _most(int version, QrErrorCorrection level, QrMode mode) async {
  final char = switch (mode) {
    QrMode.numeric => 0x37,
    QrMode.alphanumeric => 0x41,
    QrMode.byte => 0x61,
  };
  final size = 4 * version + 17;
  Future<bool> fits(int count) async {
    final out = await _run([
      '-t',
      'ASCII',
      '-m',
      '0',
      '-l',
      'LMQH'[level.index],
      '-v',
      '$version',
      if (mode == QrMode.byte) '-8',
    ], List.filled(count, char));
    return out.split('\n').first.length == 2 * size;
  }

  var low = 0;
  var high = 8000;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (await fits(mid)) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}

/// What qrencode writes with [args], given [data] on its input.
Future<String> _run(List<String> args, List<int> data) async {
  final process = await Process.start('qrencode', [...args, '-o', '-']);
  process.stdin.add(data);
  await process.stdin.close();
  final out = await process.stdout
      .transform(const SystemEncoding().decoder)
      .join();
  await process.stderr.drain<void>();
  await process.exitCode;
  return out;
}

String _hash(List<String> rows) =>
    moduleHash(rows.length, (x, y) => rows[y].codeUnitAt(x) == 0x31);
