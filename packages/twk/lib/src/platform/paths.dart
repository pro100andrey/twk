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

/// A root on Windows: a drive's (`C:\`), a share's (`\\server\share`), or
/// either as a long path (`\\?\C:\`, `\\?\UNC\server\share`), `/` taken
/// for `\` in each. A drive's letter alone (`C:x`, on that drive's
/// working directory) is none.
final _windowsRoot = RegExp(
  r'^(?:[\\/]{2}[?.][\\/](?:UNC[\\/][^\\/]+[\\/][^\\/]+(?=[\\/]|$)'
  r'|[A-Za-z]:(?=[\\/]))'
  r'|[\\/]{2}[^\\/?.][^\\/]*[\\/][^\\/]+(?=[\\/]|$)'
  r'|[A-Za-z]:(?=[\\/]))',
  caseSensitive: false,
);

/// The root [path] starts at, `/` or on Windows a drive's (`C:\`, its
/// letter a capital) or a share's (`\\server\share\`); null for a relative
/// path.
String? rootOf(String path) {
  if (isWindows) {
    final match = _windowsRoot.matchAsPrefix(path)?[0];
    if (match == null) {
      return null;
    }
    final root = match.replaceAll('/', r'\');
    // a drive's letter a capital, as the working directory's is
    final drive = root.length - 2;
    return root.endsWith(':')
        ? '${root.substring(0, drive)}${root[drive].toUpperCase()}:$separator'
        : '$root$separator';
  }
  return path.startsWith('/') ? '/' : null;
}

/// [path] made absolute: below [dir] when it is relative, `~` at its start
/// [home] where it is given, and on Windows from the root of [dir]'s
/// drive or share when it starts with a separator (`\x`); its `.` and `..`
/// worked out, and no separator at its end but the root's.
String resolvePath(String dir, String path, String? home) {
  var p = path;
  if (home != null &&
      (p == '~' || (p.startsWith('~') && isSeparator(p.codeUnitAt(1))))) {
    p = '$home${p.substring(1)}';
  }
  final String full;
  if (rootOf(p) != null) {
    full = p;
  } else if (isWindows && p.isNotEmpty && isSeparator(p.codeUnitAt(0))) {
    full = '${rootOf(dir) ?? ''}$p';
  } else {
    // one separator between them: two at the start are a share's root
    full = joinPath(dir, p);
  }
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
