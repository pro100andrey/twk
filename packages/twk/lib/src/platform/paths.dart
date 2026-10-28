/// Paths of the platform's form, as a `FilePicker` and a `DirectoryTree`
/// name what they show: absolute ones start at a root, `/` or on Windows a
/// drive's (`C:\`) or a share's (`\\server\share\`), with the platform's
/// separator between the names, and `/` taken for one on Windows too.
library;

import 'platform.dart';

/// The platform's separator: `\` on Windows, `/` elsewhere.
String get separator => pathSeparator;

/// Whether [unit] is a separator: `/`, and on Windows `\` too.
bool isSeparator(int unit) =>
    unit == 0x2F || (unit == 0x5C && isWindows); // / \

/// The index of the last separator in [path]; -1 for none.
int lastSeparator(String path) {
  for (var i = path.length - 1; i >= 0; i--) {
    if (isSeparator(path.codeUnitAt(i))) {
      return i;
    }
  }
  return -1;
}

/// The last name of [path], after its last separator.
String baseName(String path) => path.substring(lastSeparator(path) + 1);

/// The roots of the drives, `A:\` to `Z:\`, as [rootOf] gives them.
final List<String> _driveRoots = [
  for (var c = 0x41; c <= 0x5A; c++) '${String.fromCharCode(c)}:\\',
];

bool _isLetter(int unit) => (unit | 0x20) >= 0x61 && (unit | 0x20) <= 0x7A;

/// Whether [path] starts with a drive's letter and a colon (`C:`).
bool _isDrive(String path, int at) =>
    path.length >= at + 2 &&
    _isLetter(path.codeUnitAt(at)) &&
    path.codeUnitAt(at + 1) == 0x3A; // :

/// The length of the root [path] starts at, the separator after it
/// counted where there is one; 0 for a relative path. On Windows a
/// drive's (`C:\`), a share's (`\\server\share\`, as much of it as is
/// there: `\\server` is one too, which nothing lists), or either as a long
/// path (`\\?\C:\`, `\\?\UNC\server\share\`); `C:x` is none, on that drive
/// but not from its root.
int _rootLength(String path) {
  if (!isWindows) {
    return path.startsWith('/') ? 1 : 0;
  }
  final n = path.length;
  if (_isDrive(path, 0)) {
    return n > 2 && isSeparator(path.codeUnitAt(2)) ? 3 : 0;
  }
  if (n < 2 ||
      !isSeparator(path.codeUnitAt(0)) ||
      !isSeparator(path.codeUnitAt(1))) {
    return 0;
  }
  var names = 2; // a server and its share
  var at = 2;
  final device = n > 3 && isSeparator(path.codeUnitAt(3));
  if (device && (path.codeUnitAt(2) == 0x3F || path.codeUnitAt(2) == 0x2E)) {
    // \\?\ or \\.\: a long path, of a drive or of a share
    at = 4;
    if (_isDrive(path, at)) {
      return n > at + 2 && isSeparator(path.codeUnitAt(at + 2))
          ? at + 3
          : at + 2;
    }
    names = 1;
    if (n >= at + 3 &&
        (path.codeUnitAt(at) | 0x20) == 0x75 && // u
        (path.codeUnitAt(at + 1) | 0x20) == 0x6E && // n
        (path.codeUnitAt(at + 2) | 0x20) == 0x63 && // c
        (n == at + 3 || isSeparator(path.codeUnitAt(at + 3)))) {
      names = 3; // UNC, then a server and its share
    }
  }
  for (var k = 0; k < names && at < n; k++) {
    while (at < n && !isSeparator(path.codeUnitAt(at))) {
      at++;
    }
    if (at < n) {
      at++;
    }
  }
  return at;
}

/// The root [path] starts at, `/` or on Windows a drive's (`C:\`, its
/// letter a capital) or a share's (`\\server\share\`); null for a relative
/// path.
String? rootOf(String path) {
  final length = _rootLength(path);
  if (length == 0) {
    return null;
  }
  if (!isWindows) {
    return '/';
  }
  if (length == 3 && _isDrive(path, 0)) {
    return _driveRoots[(path.codeUnitAt(0) | 0x20) - 0x61];
  }
  // a share's, or a long path's: `\` for `/`, a separator at its end, and
  // a drive's letter a capital, as the working directory's is
  var root = path.substring(0, length).replaceAll('/', r'\');
  if ((root.startsWith(r'\\?\') || root.startsWith(r'\\.\')) &&
      _isDrive(root, 4)) {
    final letter = root[4].toUpperCase();
    root = '${root.substring(0, 4)}$letter${root.substring(5)}';
  }
  return root.endsWith(r'\') ? root : '$root\\';
}

/// [path] made absolute: below [dir] when it is relative, `~` at its start
/// [home] where it is given; on Windows from the root of [dir]'s drive or
/// share when it starts with a separator (`\x`), and on the drive it names
/// when it starts with one's letter (`D:x`: below [dir] where [dir] is on
/// it, else from its root). Its `.` and `..` worked out, and no separator
/// at its end but the root's.
String resolvePath(String dir, String path, String? home) {
  var p = path;
  if (home != null &&
      (p == '~' || (p.startsWith('~') && isSeparator(p.codeUnitAt(1))))) {
    p = '$home${p.substring(1)}';
  }
  final String full;
  if (_rootLength(p) > 0) {
    full = p;
  } else if (isWindows && p.isNotEmpty && isSeparator(p.codeUnitAt(0))) {
    full = '${rootOf(dir) ?? ''}$p';
  } else if (isWindows && _isDrive(p, 0)) {
    final drive = _driveRoots[(p.codeUnitAt(0) | 0x20) - 0x61];
    final rest = p.substring(2);
    full = rootOf(dir) == drive ? joinPath(dir, rest) : '$drive$rest';
  } else {
    // one separator between them: two at the start are a share's root
    full = joinPath(dir, p);
  }
  final root = rootOf(full) ?? separator;
  final parts = <String>[];
  var from = _rootLength(full);
  for (var i = from; i <= full.length; i++) {
    if (i == full.length || isSeparator(full.codeUnitAt(i))) {
      final part = full.substring(from, i);
      if (part == '..') {
        if (parts.isNotEmpty) {
          parts.removeLast();
        }
      } else if (part.isNotEmpty && part != '.') {
        parts.add(part);
      }
      from = i + 1;
    }
  }
  return '$root${parts.join(separator)}';
}

/// [name] in [dir].
String joinPath(String dir, String name) =>
    dir.endsWith(separator) ? '$dir$name' : '$dir$separator$name';

/// The directory [path] is in; a root's is the root.
String parentOf(String path) {
  final root = _rootLength(path);
  final at = lastSeparator(path);
  return at < root ? rootOf(path) ?? '' : path.substring(0, at);
}

/// Whether [path] is below [dir], both as [resolvePath] gives them.
bool isWithin(String dir, String path) =>
    path.length > dir.length &&
    path.startsWith(dir) &&
    (dir.endsWith(separator) || isSeparator(path.codeUnitAt(dir.length)));
