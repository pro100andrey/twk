// The paths a FilePicker and a DirectoryTree name, in the platform's form:
// rooted at `/` with `/` between the names, or on Windows at a drive's
// root with `\`, `/` taken for one there too.
import 'package:test/test.dart';
import 'package:twk/src/platform/paths.dart';

void main() {
  group('POSIX', () {
    test('a root is /, the separator /', () {
      expect(separator, '/');
      expect(rootOf('/home/me'), '/');
      expect(rootOf('home/me'), isNull);
      expect(isSeparator(0x2F), isTrue);
      expect(isSeparator(0x5C), isFalse, reason: r'\ is a name');
    });

    test('resolvePath below the directory, ~ the home, . and .. worked '
        'out', () {
      expect(resolvePath('/home/me', 'app/lib', null), '/home/me/app/lib');
      expect(resolvePath('/home/me', '/srv/./x/../y/', null), '/srv/y');
      expect(resolvePath('/home/me', '~/notes', '/home/me'), '/home/me/notes');
      expect(resolvePath('/home', '../../..', null), '/');
    });

    test('joinPath, parentOf, baseName, isWithin', () {
      expect(joinPath('/home', 'me'), '/home/me');
      expect(joinPath('/', 'home'), '/home');
      expect(parentOf('/home/me'), '/home');
      expect(parentOf('/home'), '/');
      expect(parentOf('/'), '/');
      expect(baseName('/home/me'), 'me');
      expect(isWithin('/home', '/home/me'), isTrue);
      expect(isWithin('/home', '/homes'), isFalse);
      expect(isWithin('/', '/home'), isTrue);
    });
  }, testOn: '!windows');

  group('Windows', () {
    test(r"a root is a drive's, C:\, the separator \, / one too", () {
      expect(separator, r'\');
      expect(rootOf(r'C:\Users\me'), r'C:\');
      expect(rootOf('C:/Users/me'), r'C:\');
      expect(rootOf(r'Users\me'), isNull);
      expect(isSeparator(0x2F), isTrue);
      expect(isSeparator(0x5C), isTrue);
    });

    test('resolvePath below the directory, ~ the home, . and .. worked '
        r'out, / taken for \', () {
      expect(
        resolvePath(r'C:\Users\me', 'app/lib', null),
        r'C:\Users\me\app\lib',
      );
      expect(resolvePath(r'C:\Users\me', r'D:\x\.\y\..\z\', null), r'D:\x\z');
      expect(
        resolvePath(r'C:\Users\me', r'~\notes', r'C:\Users\me'),
        r'C:\Users\me\notes',
      );
      expect(resolvePath(r'C:\Users', r'..\..\..', null), r'C:\');
    });

    test('joinPath, parentOf, baseName, isWithin', () {
      expect(joinPath(r'C:\Users', 'me'), r'C:\Users\me');
      expect(joinPath(r'C:\', 'Users'), r'C:\Users');
      expect(parentOf(r'C:\Users\me'), r'C:\Users');
      expect(parentOf(r'C:\Users'), r'C:\');
      expect(parentOf(r'C:\'), r'C:\');
      expect(baseName(r'C:\Users\me'), 'me');
      expect(baseName('C:/Users/me'), 'me');
      expect(isWithin(r'C:\Users', r'C:\Users\me'), isTrue);
      expect(isWithin(r'C:\Users', r'C:\Users2'), isFalse);
      expect(isWithin(r'C:\', r'C:\Users'), isTrue);
    });

    test(r"a share's root is one, \\server\share\, and either root as a "
        r"long path, \\?\; a drive's letter is a capital", () {
      expect(rootOf(r'\\server\share\docs'), r'\\server\share\');
      expect(rootOf('//server/share'), r'\\server\share\');
      expect(rootOf(r'\\wsl$\Ubuntu\home'), r'\\wsl$\Ubuntu\');
      expect(rootOf(r'\\?\C:\x'), r'\\?\C:\');
      expect(rootOf(r'\\?\UNC\server\share\x'), r'\\?\UNC\server\share\');
      expect(rootOf(r'c:\x'), r'C:\');
      expect(rootOf(r'\\?\c:\x'), r'\\?\C:\');
      expect(rootOf(r'\\.\pipe\x'), r'\\.\pipe\');
      // a share not named yet, as one is typed: a root, which nothing lists,
      // not a path on the drive of the directory
      expect(rootOf(r'\\server'), r'\\server\');
      expect(rootOf(r'\\server\'), r'\\server\');
      expect(rootOf(r'\\'), r'\\');
      expect(rootOf(r'\\?\UNC\server'), r'\\?\UNC\server\');
      // a separator alone, a drive's letter without one
      expect(rootOf(r'\x'), isNull);
      expect(rootOf('C:x'), isNull);
      expect(rootOf('C:'), isNull);
    });

    test("a drive's letter without a separator, D: or D:x, is on that drive: "
        'below the directory where it is on it, else from its root', () {
      expect(resolvePath(r'C:\proj', 'D:', null), r'D:\');
      expect(resolvePath(r'C:\proj', 'd:report', null), r'D:\report');
      expect(resolvePath(r'C:\proj', 'C:x', null), r'C:\proj\x');
      expect(resolvePath(r'c:\proj', 'c:..', null), r'C:\');
      // a long path's drive is its drive too
      expect(resolvePath(r'\\?\D:\proj', 'D:sub', null), r'\\?\D:\proj\sub');
    });

    test('a share typed in part stays one, not a path on the drive', () {
      expect(resolvePath(r'C:\Users\me', r'\\nas', null), r'\\nas\');
      expect(resolvePath(r'C:\Users\me', r'\\nas\sh', null), r'\\nas\sh\');
      expect(resolvePath(r'C:\Users\me', r'\\nas\sh\..', null), r'\\nas\sh\');
      expect(parentOf(r'\\nas\'), r'\\nas\');
      // \x from a share typed in part names its share
      expect(resolvePath(r'\\nas', r'\x', null), r'\\nas\x\');
    });

    test(r'resolvePath on a share; \x from the root of the directory, a '
        "drive's or a share's; a drive's letter made a capital", () {
      expect(
        resolvePath(r'\\wsl$\Ubuntu\home\me', 'docs', null),
        r'\\wsl$\Ubuntu\home\me\docs',
      );
      expect(
        resolvePath(r'\\server\share\a', r'..\..\..', null),
        r'\\server\share\',
      );
      expect(resolvePath(r'C:\Users\me', r'\Windows', null), r'C:\Windows');
      expect(resolvePath(r'D:\x', '/y', null), r'D:\y');
      expect(
        resolvePath(r'\\server\share\a', r'\b', null),
        r'\\server\share\b',
      );
      expect(resolvePath(r'C:\Users', r'c:\temp', null), r'C:\temp');
      expect(resolvePath(r'c:\users', 'me', null), r'C:\users\me');
      // a directory of no root, as a tree in memory of POSIX paths has
      expect(resolvePath(r'\', 'app/lib', null), r'\app\lib');
      expect(resolvePath(r'\', '/app/lib', null), r'\app\lib');
    });

    test('parentOf and isWithin on a share', () {
      expect(parentOf(r'\\server\share\a'), r'\\server\share\');
      expect(parentOf(r'\\server\share\'), r'\\server\share\');
      expect(isWithin(r'\\server\share\', r'\\server\share\a'), isTrue);
      expect(isWithin(r'\\server\share\a', r'\\server\share\ab'), isFalse);
    });
  }, testOn: 'windows');
}
