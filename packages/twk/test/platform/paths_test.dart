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
  }, testOn: 'windows');
}
