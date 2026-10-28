// What opens a file of a stack from the console: the command TWK_EDITOR,
// VISUAL or EDITOR makes, and Enter on a frame running it, a terminal
// editor with the app suspended.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'console_record_test.dart' show vmStack;

/// The platform's separator, in the paths a stack's file: URIs give.
final String sep = Platform.pathSeparator;

void main() {
  group('editorCommand', () {
    EditorCommand? of(Map<String, String> env) =>
        editorCommand(env, '/src/my app/main.dart', 12, 5);

    test('TWK_EDITOR, its {file}, {line} and {column} put in, words in '
        'quotes kept whole', () {
      final c = of({
        'TWK_EDITOR': 'code -g {file}:{line}:{column}',
        'EDITOR': 'vim',
      })!;
      expect(c.executable, 'code');
      expect(c.arguments, ['-g', '/src/my app/main.dart:12:5']);
      expect(c.inTerminal, isFalse);
      expect(
        of({'TWK_EDITOR': '"/opt/my editor/bin/ed" --at={line} {file}'})!
            .executable,
        '/opt/my editor/bin/ed',
      );
      final vim = of({'TWK_EDITOR': 'nvim +{line} {file}'})!;
      expect(vim.arguments, ['+12', '/src/my app/main.dart']);
      expect(vim.inTerminal, isTrue);
    });

    test('VISUAL, else EDITOR, given the file and line as that editor takes '
        'them, in the terminal for a terminal editor', () {
      final cases = {
        'vim': (['+12', '/src/my app/main.dart'], true),
        '/usr/bin/nano': (['+12', '/src/my app/main.dart'], true),
        'hx': (['/src/my app/main.dart:12:5'], true),
        'emacs -nw': (['-nw', '+12', '/src/my app/main.dart'], true),
        'emacs': (['+12', '/src/my app/main.dart'], false),
        'code --wait': (['--wait', '-g', '/src/my app/main.dart:12:5'], false),
        'idea': (['--line', '12', '/src/my app/main.dart'], false),
        'zed': (['/src/my app/main.dart:12:5'], false),
        'gedit': (['/src/my app/main.dart'], false),
      };
      for (final MapEntry(key: editor, value: (args, terminal))
          in cases.entries) {
        final c = of({'EDITOR': editor})!;
        expect(c.arguments, args, reason: editor);
        expect(c.inTerminal, terminal, reason: editor);
      }
      expect(of({'VISUAL': 'zed', 'EDITOR': 'vim'})!.executable, 'zed');
    });

    test('none of the three set, or set to blanks: none', () {
      expect(of({}), isNull);
      expect(of({'TWK_EDITOR': '  ', 'EDITOR': ''}), isNull);
    });
  });

  group('Enter on a frame', () {
    late List<EditorCommand> ran;
    final kept = DebugAids.runEditor;
    setUp(() => ran = []);
    tearDown(() {
      DebugAids.runEditor = kept;
    });

    /// The console open on a record with [vmStack], shown whole, its
    /// first frame selected; the app's environment is [environment].
    Future<void> onFrame(
      TwkTester t, {
      Map<String, String> environment = const {},
    }) async {
      await t.pumpWidget(
        const Text('app'),
        size: (80, 30),
        environment: environment,
      );
      t.binding.debug
        ..keys = true
        ..console.openOnError = false;
      t.logs.add(
        LogRecord(
          DateTime(2026),
          LogLevel.error,
          'failed',
          error: 'boom',
          stack: vmStack(),
        ),
      );
      await t.press('ctrl+g c up enter down down');
      await t.pump();
      expect(
        t.binding.debug.console.selectedLine!.frame!.member,
        'main.<fn>',
      );
    }

    testTwk('runs a terminal editor with the app suspended until it ends', (
      t,
    ) async {
      var suspendedWhileRunning = false;
      DebugAids.runEditor = (c) async {
        ran.add(c);
        suspendedWhileRunning = t.terminal.suspends == 1;
        return 0;
      };
      await onFrame(t, environment: {'TWK_EDITOR': 'nvim +{line} {file}'});
      await t.press('enter');
      await t.pump();
      expect(ran, hasLength(1));
      expect(ran.single.executable, 'nvim');
      expect(ran.single.arguments, [
        '+12',
        '${Directory.current.path}${sep}lib${sep}main.dart',
      ]);
      expect(suspendedWhileRunning, isTrue);
      expect(t.binding.debug.console.shownRecord, isNotNull);
    });

    testTwk('runs an editor of its own window apart, the app not suspended; '
        'one that ends badly is said in the log', (t) async {
      DebugAids.runEditor = (c) async {
        ran.add(c);
        return 2;
      };
      await onFrame(t, environment: {'VISUAL': 'code', 'EDITOR': 'vim'});
      await t.press('enter');
      await t.pump();
      expect(ran.single.arguments, [
        '-g',
        '${Directory.current.path}${sep}lib${sep}main.dart:12:5',
      ]);
      expect(t.terminal.suspends, 0);
      expect(t.logs.records.last.message, 'code ended with 2');
    });

    testTwk('with none of TWK_EDITOR, VISUAL and EDITOR, says what to set', (
      t,
    ) async {
      DebugAids.runEditor = (c) async {
        ran.add(c);
        return 0;
      };
      await onFrame(t);
      await t.press('enter');
      await t.pump();
      expect(ran, isEmpty);
      expect(
        t.logs.records.last.message,
        startsWith('to open code from the console, set TWK_EDITOR'),
      );
    });

    testTwk('a frame without a file opens nothing and says why', (t) async {
      DebugAids.runEditor = (c) async {
        ran.add(c);
        return 0;
      };
      await onFrame(t);
      // the package the program does not resolve
      await t.press('down down enter');
      await t.pump();
      expect(ran, isEmpty);
      expect(
        t.logs.records.last.message,
        'no file to open for package:my_app/widgets.dart: the program does '
        'not say where it is',
      );
    });
  });
}
