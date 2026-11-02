// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/rules/key_names.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(KeyNamesTest);
  });
}

@reflectiveTest
class KeyNamesTest extends TwkRuleTest {
  @override
  void setUp() {
    rule = KeyNames();
    super.setUp();
  }

  Future<void> test_kitty_only() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f(void Function() go, Widget child) => KeyBindings(
  {
    'ctrl+i': go,
    'ctrl+shift+c': go,
    'shift+enter': go,
    'super+s': go,
    'ctrl+tab': go,
    'ctrl+x ctrl+m': go,
  },
  child: child,
);
''';
    await assertDiagnostics(code, [
      lintAt(
        code,
        "'ctrl+i'",
        messageContainsAll: [
          "'ctrl+i' fires only with the kitty keyboard protocol",
          "send it as 'tab'",
        ],
      ),
      lintAt(code, "'ctrl+shift+c'", messageContainsAll: ["as 'ctrl+c'"]),
      lintAt(code, "'shift+enter'", messageContainsAll: ["as 'enter'"]),
      lintAt(code, "'super+s'", messageContainsAll: ['not at all']),
      lintAt(code, "'ctrl+tab'", messageContainsAll: ['no key of its own']),
      lintAt(
        code,
        "'ctrl+x ctrl+m'",
        messageContainsAll: ["'ctrl+m' fires", "as 'enter'"],
      ),
    ]);
  }

  Future<void> test_keys_every_terminal_sends() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f(void Function() go, Widget child) => KeyBindings(
  {
    'tab': go,
    'shift+tab': go,
    'ctrl+s': go,
    'alt+S': null,
    'A': go,
    'alt+enter': go,
    'ctrl+backspace': go,
    'ctrl+alt+shift+up': go,
    'leader w': go,
    'g g': go,
    'alt++': go,
    'ctrl+]': go,
  },
  hints: {'ctrl+s': 'save', 'shift+a': 'add'},
  child: child,
);
''');
  }

  Future<void> test_not_a_key() async {
    const code = '''
import 'package:twk/twk.dart';

final class Save extends Intent {
  const Save();
}

Widget f(void Function() go, Widget child) => Shortcuts(
  {'ret': const Save(), 'cmd+s': const Save(), 'g  g': const Save()},
  child: child,
);
''';
    await assertDiagnostics(code, [
      lintAt(
        code,
        "'ret'",
        messageContainsAll: [
          "The key name 'ret' fails the build",
          '"enter" is meant?',
        ],
      ),
      lintAt(code, "'cmd+s'", messageContainsAll: ['"super" is meant?']),
      lintAt(code, "'g  g'", messageContainsAll: ['one space each']),
    ]);
  }

  Future<void> test_same_keys_and_unbound_hints() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f(void Function() go, Widget child, bool on) => Column(
  children: [
    KeyBindings(
      {'A': go, 'shift+a': go, 'g g': go, 'g  g': go},
      hints: {'shift+A': 'add', 'q': 'quit'},
      child: child,
    ),
    KeyBindings(
      {'x': go, if (on) 'X': go else 'shift+x': go},
      hints: {'q': 'quit'},
      child: child,
    ),
  ],
);
''';
    await assertDiagnostics(code, [
      lintAt(
        code,
        "'shift+a'",
        messageContainsAll: ["'A' and 'shift+a' fail the build", 'same key.'],
      ),
      lintAt(code, "'g  g'"),
      lintAt(
        code,
        "'q'",
        messageContainsAll: ["The hint of 'q' fails the build"],
      ),
      // the second map has an `if`: what it binds is not read whole
    ]);
  }

  Future<void> test_other_places() async {
    const code = '''
import 'package:twk/twk.dart';
import 'package:twk_term/twk_term.dart';

final a = KeyCombo.parse('ctrl+j');
final b = KeyCombo.parse('g g');
final c = KeyCombo.parseSequence('ctrl+x ctrl+[');
final d = KeyCombo.parseSequence('leader w');
final e = KeyCombo.parseSequence('leader w', leader: a);
Widget f(Widget child) => Column(
  children: [
    LeaderKey('ctrl+h', child: child),
    SelectionArea(copyKey: 'ctrl+shift+c', clearKey: 'Escape', child: child),
    TerminalView(ignoredKeys: const ['ctrl+q', 'super+q']),
  ],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, "'ctrl+j'", messageContainsAll: ["as 'enter'"]),
      lintAt(code, "'g g'", messageContainsAll: ['is 2 keys; one is meant']),
      lintAt(code, "'ctrl+x ctrl+['", messageContainsAll: ["as 'escape'"]),
      lintAt(
        code,
        "'leader w'",
        messageContainsAll: ['stands for a leader key, and none is given'],
      ),
      lintAt(code, "'ctrl+h'", messageContainsAll: ["as 'ctrl+backspace'"]),
      lintAt(code, "'ctrl+shift+c'", messageContainsAll: ["as 'ctrl+c'"]),
      lintAt(code, "'Escape'", messageContainsAll: ['"escape" is meant?']),
      lintAt(code, "'super+q'", messageContainsAll: ['not at all']),
    ]);
  }

  Future<void> test_names_not_written_in_place_are_not_read() async {
    await assertNoDiagnostics(r'''
import 'package:twk/twk.dart';

Widget f(String key, Map<String, void Function()> keys, Widget child) =>
    Column(
      children: [
        KeyBindings(keys, hints: {'ctrl+s': 'save'}, child: child),
        KeyBindings({key: () {}, 'ctrl+$key': () {}}, child: child),
        Text('ctrl+i'),
      ],
    );
''');
  }

  Future<void> test_in_tests_only_names_that_fail_the_build() async {
    final path = '$testPackageRootPath/test/keys_test.dart';
    const code = '''
import 'package:twk/twk.dart';

final kitty = KeyCombo.parse('ctrl+i');
final typo = KeyCombo.parse('ctlr+i');
''';
    newFile(path, code);
    await assertDiagnosticsInFile(path, [lintAt(code, "'ctlr+i'")]);
  }
}
