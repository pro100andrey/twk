/// Paths of the platform's form, as a `FilePicker` and a `DirectoryTree`
/// name what they show: absolute ones start at a root, `/` or on Windows a
/// drive's (`C:\`), with the platform's separator between the names, and
/// `/` taken for one on Windows too.
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

/// The root [path] starts at, `/` or on Windows a drive's, `C:\`; null for
/// a relative path.
String? rootOf(String path) {
  if (isWindows) {
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)
        ? '${path.substring(0, 2)}$separator'
        : null;
  }
  return path.startsWith('/') ? '/' : null;
}

/// [path] made absolute: below [dir] when it is relative, `~` at its start
/// [home] where it is given; its `.` and `..` worked out, and no separator
/// at its end but the root's.
String resolvePath(String dir, String path, String? home) {
  var p = path;
  if (home != null &&
      (p == '~' || (p.startsWith('~') && isSeparator(p.codeUnitAt(1))))) {
    p = '$home${p.substring(1)}';
  }
  final full = rootOf(p) == null ? '$dir$separator$p' : p;
  final root = rootOf(full) ?? separator;
  final parts = <String>[];
  var from = root.length;
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
  final root = rootOf(path) ?? '';
  final at = lastSeparator(path);
  return at < root.length ? root : path.substring(0, at);
}

/// Whether [path] is below [dir], both as [resolvePath] gives them.
bool isWithin(String dir, String path) =>
    path.length > dir.length &&
    path.startsWith(dir) &&
    (dir.endsWith(separator) || isSeparator(path.codeUnitAt(dir.length)));
