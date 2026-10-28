// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/fixes/dispose_field.dart';
import 'package:twk_lints/src/rules/dispose_controllers.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DisposeControllersTest);
  });
}

const _widget = '''
import 'package:twk/twk.dart';

final class W extends StatefulWidget {
  const W({super.key, this.controller});
  final ScrollController? controller;
  @override
  State<W> createState() => _S();
}
''';

@reflectiveTest
class DisposeControllersTest extends TwkRuleTest {
  @override
  void setUp() {
    rule = DisposeControllers();
    super.setUp();
  }

  Future<void> test_initializer() async {
    const code =
        '''
$_widget
final class _S extends State<W> {
  final _text = TextEditingController();
  late final _focus = FocusNode()..addListener(() {});

  @override
  Widget build(BuildContext context) => TextField(controller: _text);
}
''';
    await assertDiagnostics(code, [
      lintAt(
        code,
        '_text',
        messageContainsAll: ["TextEditingController '_text'"],
      ),
      lintAt(code, '_focus'),
    ]);
  }

  Future<void> test_assigned() async {
    const code =
        '''
$_widget
final class _S extends State<W> {
  late ScrollController _scroll;
  FocusNode? _focus;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _focus ??= FocusNode();
  }

  @override
  Widget build(BuildContext context) => Text('');
}
''';
    await assertDiagnostics(code, [
      lintAt(code, '_scroll'),
      lintAt(code, '_focus', messageContainsAll: ["FocusNode '_focus'"]),
    ]);
  }

  Future<void> test_disposed() async {
    await assertNoDiagnostics('''
$_widget
final class _S extends State<W> {
  final _text = TextEditingController();
  late ScrollController _scroll;
  FocusNode? _focus;
  final _other = FocusNode();

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _focus = FocusNode();
  }

  @override
  void dispose() {
    _text.dispose();
    this._scroll.dispose();
    _focus?.dispose();
    _other..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('');
}
''');
  }

  Future<void> test_disposed_in_a_for_loop_over_a_literal() async {
    await assertNoDiagnostics('''
$_widget
final class _S extends State<W> {
  final _a = FocusNode();
  late final _b = FocusNode()..addListener(() {});
  final _c = ScrollController();
  final _d = TextEditingController();
  final _more = <FocusNode>{};

  @override
  void dispose() {
    for (final n in [_a, this._b, ..._more]) {
      n.dispose();
    }
    for (final ChangeNotifier n in {_c}) n.dispose();
    for (final n in [_d]) {
      if (identical(n, _d)) {
        n..dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('');
}
''');
  }

  Future<void> test_disposed_by_for_each() async {
    await assertNoDiagnostics('''
$_widget
final class _S extends State<W> {
  final _a = FocusNode();
  final _b = FocusNode();
  final _c = ScrollController();

  @override
  void dispose() {
    [_a, _b].forEach((n) => n.dispose());
    <ChangeNotifier>[_c].forEach((n) {
      n.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('');
}
''');
  }

  Future<void> test_disposed_through_a_list_field() async {
    await assertNoDiagnostics('''
$_widget
final class _S extends State<W> {
  final _a = FocusNode();
  final _b = FocusNode();
  late final _all = [_a, _b];
  final _c = ScrollController();
  final _d = FocusNode();
  final _e = FocusNode();
  final _f = FocusNode();
  final _added = <ChangeNotifier>[];
  late final _set = <FocusNode>{};

  @override
  void initState() {
    super.initState();
    _added.add(_c);
    _added.addAll([_d, _e]);
    this._set.add(_f);
  }

  @override
  void dispose() {
    for (final n in _all) {
      n.dispose();
    }
    _added.forEach((n) => n.dispose());
    for (final n in this._set) n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('');
}
''');
  }

  Future<void> test_loops_that_dispose_nothing_of_theirs() async {
    // the loop disposes something else than its variable; a list field
    // that no loop disposes; and a list a method returns, which the rule
    // does not follow
    const code =
        '''
$_widget
final class _S extends State<W> {
  final _a = FocusNode();
  final _b = FocusNode();
  final _c = FocusNode();
  late final _kept = [_c];
  final _d = FocusNode();
  final _other = FocusNode();

  List<FocusNode> _nodes() => [_d];

  @override
  void dispose() {
    for (final n in [_a]) {
      n.toString();
      _other.dispose();
    }
    [_b].forEach((n) => n.toString());
    for (final n in _kept) n.toString();
    for (final n in _nodes()) n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('');
}
''';
    await assertDiagnostics(code, [
      lintAt(code, '_a'),
      lintAt(code, '_b'),
      lintAt(code, '_c'),
      lintAt(code, '_d'),
    ]);
  }

  Future<void> test_generic_state() async {
    // the fields read in a generic State are the declared ones with the
    // class's type parameters for arguments
    const code =
        '''
$_widget
final class _Rows<T> extends ChangeNotifier {
  _Rows(this.state);
  final _S<T> state;
}

final class _S<T> extends State<W> {
  late var _rows = _Rows<T>(this);
  late final _kept = _Rows<T>(this);

  void _replace() {
    _rows.dispose();
    _rows = _Rows<T>(this);
  }

  @override
  void dispose() {
    _rows.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('');
}
''';
    await assertDiagnostics(code, [lintAt(code, '_kept')]);
  }

  Future<void> test_not_created() async {
    await assertNoDiagnostics('''
$_widget
final class _S extends State<W> {
  late ScrollController _scroll;
  final _count = 0;

  @override
  void initState() {
    super.initState();
    _scroll = widget.controller!;
  }

  @override
  Widget build(BuildContext context) => Text('');
}
''');
  }

  Future<void> test_not_a_state() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

final class Model {
  final text = TextEditingController();
}
''');
  }

  Future<void> test_fix_before_super_dispose() async {
    const code =
        '''
$_widget
final class _S extends State<W> {
  final _text = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: _text);
}
''';
    await assertDiagnostics(code, [lintAt(code, '_text')]);
    expect(
      await fixed(DisposeField.new),
      code.replaceFirst(
        '    super.dispose();',
        '    _text.dispose();\n    super.dispose();',
      ),
    );
  }

  Future<void> test_fix_creates_the_override_before_build() async {
    const code =
        '''
$_widget
final class _S extends State<W> {
  FocusNode? _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
  }

  /// The field.
  @override
  Widget build(BuildContext context) => Text('');
}
''';
    await assertDiagnostics(code, [lintAt(code, '_focus')]);
    expect(
      await fixed(DisposeField.new),
      code.replaceFirst('  /// The field.', '''
  @override
  void dispose() {
    _focus?.dispose();
    super.dispose();
  }

  /// The field.'''),
    );
  }

  Future<void> test_fix_creates_the_override_after_the_last_member() async {
    const code =
        '''
$_widget
abstract class _Base extends State<W> {
  final _text = TextEditingController();
}

final class _S extends _Base {
  @override
  Widget build(BuildContext context) => Text('');
}
''';
    await assertDiagnostics(code, [lintAt(code, '_text')]);
    expect(
      await fixed(DisposeField.new),
      code.replaceFirst('  final _text = TextEditingController();', '''
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }'''),
    );
  }

  Future<void>
  test_no_fix_without_super_dispose_or_with_the_name_hidden() async {
    const code =
        '''
$_widget
final class _S extends State<W> {
  final _text = TextEditingController();

  @override
  void dispose() => super.dispose();

  @override
  Widget build(BuildContext context) => Text('');
}

final class _T extends State<W> {
  final _text = TextEditingController();

  @override
  void dispose() {
    final _text = 0;
    assert(_text == 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('');
}
''';
    await assertDiagnostics(code, [
      lintAt(code, '_text'),
      lintAt(code, '_text', occurrence: 1),
    ]);
    expect(await fixed(DisposeField.new), isNull);
    expect(await fixed(DisposeField.new, index: 1), isNull);
  }
}
