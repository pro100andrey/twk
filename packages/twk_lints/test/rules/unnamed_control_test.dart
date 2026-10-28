// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/fixes/add_semantics_label.dart';
import 'package:twk_lints/src/rules/unnamed_control.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UnnamedControlTest);
  });
}

@reflectiveTest
class UnnamedControlTest extends TwkRuleTest {
  @override
  void setUp() {
    rule = UnnamedControl();
    super.setUp();
  }

  Future<void> test_fields() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f(TextEditingController name) => Column(
  children: [
    TextField(controller: name),
    TextArea(semanticsLabel: '', placeholder: null),
    TextFormField(),
  ],
);
''';
    await assertDiagnostics(code, [
      lintAt(
        code,
        'TextField',
        messageContainsAll: ["this TextField without a name, as 'textbox'"],
      ),
      lintAt(code, 'TextArea'),
      lintAt(code, 'TextFormField'),
    ]);
  }

  Future<void> test_fields_named() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f(String label) => Column(
  children: [
    TextField(semanticsLabel: 'Name'),
    TextField(placeholder: 'Name'),
    TextArea(semanticsLabel: label),
    TextFormField(placeholder: 'City'),
    TextFormField(semanticsLabel: 'City'),
  ],
);
''');
  }

  Future<void> test_slider_and_toggles() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    Slider(value: 0.5),
    Slider(value: 0.5, semanticsLabel: 'Volume'),
    Checkbox(value: true, label: ''),
    Checkbox(value: true, label: 'Remember me'),
    Switch(value: false),
    Switch(value: false, semanticsLabel: 'Wi-Fi'),
  ],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, 'Slider', messageContainsAll: ["as 'slider'"]),
      lintAt(code, 'Checkbox', messageContainsAll: ["as 'checkbox'"]),
      lintAt(code, 'Switch', messageContainsAll: ["as 'switch'"]),
    ]);
  }

  Future<void> test_glyph_button() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f(String label) => Column(
  children: [
    Button(' × ', onPressed: () {}),
    Button('Close', onPressed: () {}),
    Button('▶ 2', onPressed: () {}),
    Button(label, onPressed: () {}),
  ],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, 'Button', messageContainsAll: ["as 'button ×'"]),
    ]);
  }

  Future<void> test_not_in_tests() async {
    final path = '$testPackageRootPath/test/field_test.dart';
    newFile(path, '''
import 'package:twk/twk.dart';

Widget f() => TextField();
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_fix_inserts_before_the_first_argument() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f(TextEditingController name) => TextField(controller: name);
''';
    await assertDiagnostics(code, [lintAt(code, 'TextField')]);
    final fixed = await this.fixed(AddSemanticsLabel.new);
    const want = "TextField(semanticsLabel: '', controller: name)";
    expect(fixed, code.replaceFirst('TextField(controller: name)', want));
    expect(fixSelection, fixed!.indexOf(want) + want.indexOf("''") + 1);
  }

  Future<void> test_fix_on_a_line_of_its_own() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f() => Slider(
  value: 0.5,
);
''';
    await assertDiagnostics(code, [lintAt(code, 'Slider')]);
    expect(
      await fixed(AddSemanticsLabel.new),
      code.replaceFirst(
        '  value: 0.5,',
        "  semanticsLabel: '',\n  value: 0.5,",
      ),
    );
  }

  Future<void> test_fix_in_empty_arguments_and_in_place_of_empty() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [TextFormField(), TextArea(semanticsLabel: null)],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, 'TextFormField'),
      lintAt(code, 'TextArea'),
    ]);
    expect(
      await fixed(AddSemanticsLabel.new),
      code.replaceFirst('TextFormField()', "TextFormField(semanticsLabel: '')"),
    );
    final second = await fixed(AddSemanticsLabel.new, index: 1);
    expect(
      second,
      code.replaceFirst('semanticsLabel: null', "semanticsLabel: ''"),
    );
    expect(fixSelection, second!.indexOf("semanticsLabel: ''") + 17);
  }

  Future<void> test_no_fix_for_a_button() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f() => Button('×', onPressed: null);
''';
    await assertDiagnostics(code, [lintAt(code, 'Button')]);
    expect(await fixed(AddSemanticsLabel.new), isNull);
  }
}
