/// How the widgets write amounts, so that two of them never write the
/// same one two ways: a ratio as a whole percent ([formatPercent]), a
/// time as a clock ([formatClock]) or as the time something took
/// ([formatTook]), and bytes in decimal or binary units ([formatBytes]).
/// [formatTook], [formatBytes] and [ByteUnits] are exported by
/// `package:twk/format.dart`, for an app to write a time taken and a size as
/// the widgets do; the others are internal.
library;

import 'helpers.dart';

/// [ratio], kept from 0 to 1, as a whole percent, cut rather than rounded,
/// so that only a ratio of 1 reads `100%`: 0.996 is `99%`, 0.29 `29%`
/// (not the `28%` that `(0.29 * 100).floor()` gives).
String formatPercent(double ratio) {
  final r = unitRatio(ratio);
  var p = (r * 100).floor();
  // r * 100 may land a hair past or short of a whole percent: p is the
  // greatest whole percent whose ratio is r or less
  if (p > 0 && p / 100 > r) {
    p--;
  } else if (p < 100 && (p + 1) / 100 <= r) {
    p++;
  }
  return '$p%';
}

/// [time] as a clock, in whole seconds cut: `00:04`, `12:34`, then with
/// the hours, `1:02:03`.
String formatClock(Duration time) {
  final s = time.inSeconds;
  if (s < 3600) {
    return '${_two(s ~/ 60)}:${_two(s % 60)}';
  }
  return '${s ~/ 3600}:${_two(s ~/ 60 % 60)}:${_two(s % 60)}';
}

/// [time] as the time something took, as a `ProgressList`, a `TaskList`
/// and `ProgressTask.summary` write it: to the tenth of a second, cut
/// rather than rounded, under a minute (`3.1 s`), else as a clock in whole
/// seconds (`01:05`, then with the hours, `1:02:03`).
///
/// The line an operation of an app's own ends with:
///
/// ```dart
/// final clock = Stopwatch()..start();
/// // ...
/// final line = '✓ Built in ${formatTook(clock.elapsed)}';
/// // line: ✓ Built in 3.1 s
/// ```
///
/// The point of `3.1 s` is [decimalSeparator], `TwkStrings.decimalSeparator`
/// for the widgets: `3,1 s`.
String formatTook(Duration time, {String decimalSeparator = '.'}) {
  if (time.inSeconds < 60) {
    final tenths = time.inMilliseconds ~/ 100;
    return '${tenths ~/ 10}$decimalSeparator${tenths % 10} s';
  }
  return formatClock(time);
}

String _two(int n) => '$n'.padLeft(2, '0');

/// How sizes in bytes are counted and named.
enum ByteUnits {
  /// Thousands, the SI units: `kB`, `MB`, `GB`, `TB`, `PB`; a kilobyte is
  /// 1000 bytes, as in `ls --si`, `du --si` and what disk makers quote.
  decimal(1000, ['kB', 'MB', 'GB', 'TB', 'PB']),

  /// 1024s, the IEC units: `KiB`, `MiB`, `GiB`, `TiB`, `PiB`; a kibibyte is
  /// 1024 bytes, as `ls -h`, `du -h`, `df -h` and `htop` count.
  binary(1024, ['KiB', 'MiB', 'GiB', 'TiB', 'PiB']);

  const ByteUnits(this.base, this.suffixes);

  /// How many of one unit make the next.
  final int base;

  /// The names of the units above the byte, the smallest first.
  final List<String> suffixes;
}

/// The unit [bytes] are written in under [byteUnits], and how many bytes it
/// is: `(1, 'B')` under a thousand (`ByteUnits.decimal`) or 1024
/// (`ByteUnits.binary`), then the units above, each a thousand or 1024 of
/// the one before; the next unit from where the figures would round to
/// that many of this one (999 999 bytes are `1.0 MB`, not `1000 kB`).
(num, String) byteUnit(
  num bytes, {
  ByteUnits byteUnits = ByteUnits.decimal,
}) {
  final base = byteUnits.base;
  final b = bytes.abs();
  if (b < base - 0.5) {
    return (1, 'B');
  }
  num scale = base;
  var i = 0;
  while (i < byteUnits.suffixes.length - 1 && b >= scale * (base - 0.5)) {
    scale *= base;
    i++;
  }
  return (scale, byteUnits.suffixes[i]);
}

/// [bytes] in their unit under [byteUnits] ([byteUnit]), whole from 100 of it
/// and to the tenth below ([formatFigures]). The sizes a `DirectoryTree`
/// and a `ProgressList` write.
///
/// By default the units are the SI ones ([ByteUnits.decimal]), a kilobyte
/// being 1000 bytes: `512 B`, `4.1 kB`, `620 kB`, `1.2 MB`, the `kB` of
/// `ls --si` and `du --si` and of what disk makers and file managers
/// quote. [ByteUnits.binary] counts by 1024 as `ls -h` and `du -h` do and
/// names the units as the IEC does: `1023 B`, `1.0 KiB`, `1.5 MiB`. A
/// figure reads the same as the widgets' beside it where the same [byteUnits]
/// are given to both.
///
/// ```dart
/// final line = '${formatBytes(4096)} of ${formatBytes(1200000)}';
/// // line: 4.1 kB of 1.2 MB
/// final binary = formatBytes(1536, byteUnits: ByteUnits.binary);
/// // binary: 1.5 KiB
/// ```
///
/// The point of `4.1 kB` is [decimalSeparator], `TwkStrings.decimalSeparator`
/// for the widgets: `4,1 kB`.
String formatBytes(
  num bytes, {
  ByteUnits byteUnits = ByteUnits.decimal,
  String decimalSeparator = '.',
}) {
  final (scale, suffix) = byteUnit(bytes, byteUnits: byteUnits);
  return scale == 1 && bytes == bytes.roundToDouble()
      ? '${bytes.round()} B'
      : '${formatFigures(bytes / scale, decimalSeparator: decimalSeparator)} '
            '$suffix';
}

/// [n] whole from 100 on, to the tenth below: `620`, `4.1`; `100`, not
/// `100.0`, for what rounds to it. The point is [decimalSeparator].
String formatFigures(num n, {String decimalSeparator = '.'}) => n.abs() >= 99.95
    ? n.toStringAsFixed(0)
    : withSeparator(n.toStringAsFixed(1), decimalSeparator);

/// [figures], as `toStringAsFixed` writes them, with [decimalSeparator] for
/// the point.
String withSeparator(String figures, String decimalSeparator) =>
    decimalSeparator == '.'
    ? figures
    : figures.replaceFirst('.', decimalSeparator);
