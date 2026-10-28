/// How the widgets write amounts, so that two of them never write the
/// same one two ways: a ratio as a whole percent ([formatPercent]), a
/// time as a clock ([formatClock]) or as the time something took
/// ([formatTook]), and bytes in decimal units ([formatBytes]).
/// [formatTook] is exported, for an app to write a time taken as the
/// widgets do; the others are internal.
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
String formatTook(Duration time) {
  if (time.inSeconds < 60) {
    final tenths = time.inMilliseconds ~/ 100;
    return '${tenths ~/ 10}.${tenths % 10} s';
  }
  return formatClock(time);
}

String _two(int n) => '$n'.padLeft(2, '0');

/// The decimal unit [bytes] are written in, and how many bytes it is:
/// `(1, 'B')` under 1000, then `kB`, `MB`, `GB`, `TB` and `PB`, each a
/// thousand of the one before; the next unit from where the figures would
/// round to 1000 of this one (999 999 bytes are `1.0 MB`, not `1000 kB`).
(num, String) byteUnit(num bytes) {
  const units = ['kB', 'MB', 'GB', 'TB', 'PB'];
  final b = bytes.abs();
  if (b < 999.5) {
    return (1, 'B');
  }
  num scale = 1000;
  var i = 0;
  while (i < units.length - 1 && b >= scale * 999.5) {
    scale *= 1000;
    i++;
  }
  return (scale, units[i]);
}

/// [bytes] in their decimal unit ([byteUnit]), whole from 100 of it and to
/// the tenth below ([formatFigures]): `512 B`, `4.1 kB`, `620 kB`,
/// `1.2 MB`.
String formatBytes(num bytes) {
  final (scale, suffix) = byteUnit(bytes);
  return scale == 1 && bytes == bytes.roundToDouble()
      ? '${bytes.round()} B'
      : '${formatFigures(bytes / scale)} $suffix';
}

/// [n] whole from 100 on, to the tenth below: `620`, `4.1`; `100`, not
/// `100.0`, for what rounds to it.
String formatFigures(num n) =>
    n.abs() >= 99.95 ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
