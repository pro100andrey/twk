// What the core asks of the process on the VM (platform/io.dart), and the
// process's own terminal link where stdin is no terminal, as under
// `dart test`: its raw mode refused, its restore harmless.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_core/src/platform/platform.dart';
import 'package:twk_core/src/terminal/plain.dart';
import 'package:twk_core/src/terminal/posix_tty.dart';
import 'package:twk_core/src/terminal/stdio_link.dart';
import 'package:twk_core/src/terminal/windows_console.dart';
import 'package:twk_core/twk_core.dart';

/// Whether stdin is a terminal whose modes can be set: what these tests
/// would change, so they are skipped there.
bool get _stdinIsTty {
  try {
    stdin.echoMode;
    return true;
  } on StdinException {
    return false;
  }
}

/// [name] in the environment as a positive number, [otherwise] where it is
/// none.
int _sizeOf(String name, int otherwise) {
  final n = int.tryParse(Platform.environment[name] ?? '');
  return n != null && n > 0 ? n : otherwise;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('twk_io'));
  tearDown(() => dir.deleteSync(recursive: true));

  test("the process's id, platform and environment are dart:io's", () {
    expect(processId, pid);
    expect(isWindows, Platform.isWindows);
    expect(environment, Platform.environment);
  });

  test("the process's own terminal is there only where stdin and stdout "
      'both are one', () {
    final both = stdin.hasTerminal && stdout.hasTerminal;
    expect(outputIsTerminal, stdout.hasTerminal);
    expect(ownTerminalLink(), both ? isA<StdioLink>() : isNull);
  });

  test('plain stdio is sized by COLUMNS and LINES, and reads stdin only '
      'where it is a terminal', () async {
    final link = plainStdio();
    expect(link, isA<PlainLink>());
    expect(link.windows, isFalse);
    expect(link.eraseChar, isNull);
    expect(
      (link.columns, link.lines),
      (
        _sizeOf('COLUMNS', 80),
        _sizeOf('LINES', 24),
      ),
    );
    if (!stdin.hasTerminal) {
      expect(await link.input.isEmpty, isTrue);
    }
  });

  group('createFile', () {
    test('writes the header, then each write, until closed', () async {
      final path = '${dir.path}/trace';
      final file = createFile(path, ascii.encode('head\n'));
      await file.write(ascii.encode('one'));
      await file.write(ascii.encode('two'));
      await file.close();
      expect(File(path).readAsStringSync(), 'head\nonetwo');
    });

    test('empties a file that is there', () async {
      final path = '${dir.path}/trace';
      File(path).writeAsStringSync('old and long');
      await createFile(path, ascii.encode('new')).close();
      expect(File(path).readAsStringSync(), 'new');
    });

    test('throws what writing the header failed with', () {
      expect(
        () => createFile('/dev/full', ascii.encode('head')),
        throwsA(isA<FileSystemException>()),
      );
    }, testOn: 'linux');
  });

  group('on a stdin that is no terminal', () {
    final skip = _stdinIsTty ? 'stdin is a terminal' : null;

    test('the own terminal link refuses raw mode, and restore leaves '
        'stdin as it is', () {
      final link = StdioLink();
      expect(link.environment, Platform.environment);
      expect(link.windows, Platform.isWindows);
      expect(link.input, same(stdin));
      expect(
        link.enterRaw,
        throwsA(
          isA<TerminalException>().having(
            (e) => e.message,
            'message',
            'not a terminal',
          ),
        ),
      );
      expect(link.eraseChar, isNull);
      link.restore();
    }, skip: skip);

    test(
      "the termios flags can't be read: raw mode fails, there is no "
      'erase character, and restore changes nothing',
      () {
        final tty = PosixTty.forStdin()!;
        expect(tty.enterRaw(), isFalse);
        expect(tty.eraseChar, isNull);
        tty.restore();
      },
      skip: skip,
      testOn: 'linux || mac-os',
    );
  });

  test('a Windows console takes kernel32: none elsewhere', () {
    expect(WindowsConsole.new, throwsArgumentError);
  }, testOn: '!windows');
}
