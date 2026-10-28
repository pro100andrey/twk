// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/fixes/use_key_bindings.dart';
import 'package:twk_lints/src/rules/prefer_key_bindings.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferKeyBindingsTest);
  });
}

@reflectiveTest
class PreferKeyBindingsTest extends TwkRuleTest {
  @override
  void setUp() {
    rule = PreferKeyBindings();
    super.setUp();
  }

  Future<void> test_is_and_compare() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f(void Function() quit, Widget child) => InputListener(
  onEvent: (event) {
    if (event is KeyEvent && event.code == KeyCode.char && event.char == 'q') {
      quit();
      return true;
    }
    return false;
  },
  child: child,
);
''';
    await assertDiagnostics(code, [lintAt(code, 'InputListener')]);
  }

  Future<void> test_pattern_in_method() async {
    const code = '''
import 'package:twk/twk.dart';

final class A {
  bool _onEvent(InputEvent event) => switch (event) {
    KeyEvent(code: KeyCode.enter || KeyCode.escape, kind: KeyKind.press) =>
      true,
    _ => false,
  };

  Widget build(Widget child) =>
      InputListener(onEvent: _onEvent, child: child);
}
''';
    await assertDiagnostics(code, [lintAt(code, 'InputListener')]);
  }

  Future<void> test_switch_on_char() async {
    const code = '''
import 'package:twk/twk.dart';

bool onEvent(InputEvent e) {
  if (e is! KeyEvent) return false;
  switch (e.char) {
    case 'j':
      return true;
  }
  return false;
}

Widget f(Widget child) => InputListener(onEvent: onEvent, child: child);
''';
    await assertDiagnostics(code, [lintAt(code, 'InputListener')]);
  }

  Future<void> test_other_events() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f(Widget child) => InputListener(
  onEvent: (e) => switch (e) {
    KeyEvent(char: 'q') => true,
    MouseEvent() => true,
    _ => false,
  },
  child: child,
);
''');
  }

  Future<void> test_every_key() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f(List<InputEvent> log, Widget child) => InputListener(
  onEvent: (e) {
    if (e is KeyEvent && e.char == 'q') {
      log.add(e);
    }
    return true;
  },
  child: child,
);
''');
  }

  Future<void> test_release() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f(Widget child) => InputListener(
  onEvent: (e) => e is KeyEvent && e.char == ' ' && e.kind == KeyKind.release,
  child: child,
);
''');
  }

  Future<void> test_no_comparison() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f(Widget child) =>
    InputListener(onEvent: (e) => e is KeyEvent && e.ctrl, child: child);
''');
  }

  Future<void> test_fix_tear_offs_on_one_line() async {
    const code = '''
import 'package:twk/twk.dart';

void quit() {}

void go() {}

Widget f(Widget app) =>
    InputListener(
      onEvent: (event) {
        if (event is! KeyEvent) return false;
        if (event.char == 'q') {
          quit();
          return true;
        }
        if (event.code == KeyCode.enter || event.char == ' ') {
          go();
          return true;
        }
        return false;
      },
      child: app,
    );
''';
    await assertDiagnostics(code, [lintAt(code, 'InputListener')]);
    final at = code.indexOf('InputListener');
    expect(
      await fixed(UseKeyBindings.new),
      '${code.substring(0, at)}'
      "KeyBindings({'q': quit, 'enter': go, 'space': go}, child: app);\n",
    );
  }

  Future<void> test_fix_closures_on_lines_of_their_own() async {
    const code = '''
import 'package:twk/twk.dart' as twk;

final class A {
  var count = 0;
  void log(String s) {}

  twk.Widget build(twk.Widget child) => twk.InputListener(
    key: const twk.ValueKey(1),
    onEvent: (e) {
      if (e is twk.KeyEvent && (e.char == 'Q')) {
        log('quit');
        log('bye');
        return true;
      }
      if (e is twk.KeyEvent && twk.KeyCode.escape == e.code) {
        count++;
        return true;
      }
      return false;
    },
    child: child,
  );
}
''';
    await assertDiagnostics(code, [lintAt(code, 'twk.InputListener')]);
    final at = code.indexOf('twk.InputListener');
    expect(await fixed(UseKeyBindings.new), '''
${code.substring(0, at)}twk.KeyBindings(
    {
      'Q': () {
        log('quit');
        log('bye');
      },
      'escape': () => count++,
    },
    key: const twk.ValueKey(1),
    child: child,
  );
}
''');
  }

  Future<void> test_no_fix_for_other_shapes() async {
    const code = '''
import 'package:twk/twk.dart';

void quit() {}

void type(String s) {}

final class A {
  bool _onEvent(InputEvent event) {
    if (event is KeyEvent && event.char == 'q') {
      quit();
      return true;
    }
    return false;
  }

  Widget build(Widget child) => Column(
    children: [
      InputListener(onEvent: _onEvent, child: child),
      InputListener(
        onEvent: (event) {
          if (event is KeyEvent && event.char == 'x') {
            type(event.char);
            return true;
          }
          return false;
        },
        child: child,
      ),
      InputListener(
        onEvent: (event) {
          if (event is KeyEvent && (event.char == 'a' || event.char == 'b')) {
            type('ab');
            return true;
          }
          return false;
        },
        child: child,
      ),
      InputListener(
        onEvent: (event) {
          if (event is KeyEvent && event.char == 'a') {
            quit();
            return true;
          } else {
            quit();
          }
          return false;
        },
        child: child,
      ),
      InputListener(
        onEvent: (event) {
          if (event is KeyEvent && event.char == 'a') {
            quit();
            return true;
          }
          if (event is KeyEvent && event.char == 'a') {
            quit();
            return true;
          }
          return false;
        },
        child: child,
      ),
      InputListener(
        onEvent: (event) {
          if (event is KeyEvent && event.code == KeyCode.char) {
            quit();
            return true;
          }
          return false;
        },
        child: child,
      ),
    ],
  );
}
''';
    final listeners = RegExp(r'InputListener\(').allMatches(code).toList();
    await assertDiagnostics(code, [
      for (final m in listeners) lint(m.start, 'InputListener'.length),
    ]);
    for (var i = 0; i < listeners.length; i++) {
      expect(await fixed(UseKeyBindings.new, index: i), isNull, reason: '$i');
    }
  }
}
