/// Stubs of twk and twk_core for the fixtures, and the bases of the tests.
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/src/correction/assist_generators.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:analyzer_testing/correction/assist_processor.dart';
import 'package:analyzer_testing/package_config_file_builder.dart';
import 'package:analyzer_testing/src/analysis_rule/pub_package_resolution.dart'
    show ExpectedDiagnostic;
import 'package:test/test.dart';
import 'package:twk_lints/src/assists/convert_to_stateful_widget.dart';
import 'package:twk_lints/src/assists/convert_to_stateless_widget.dart';
import 'package:twk_lints/src/assists/extract_widget.dart';
import 'package:twk_lints/src/assists/move_widget.dart';
import 'package:twk_lints/src/assists/remove_widget.dart';
import 'package:twk_lints/src/assists/swap_widgets.dart';
import 'package:twk_lints/src/assists/wrap.dart';
import 'package:twk_lints/src/assists/wrap_builder.dart';
import 'package:twk_lints/src/assists/wrap_flex.dart';

/// The parts of twk_core the fixtures use, where twk has them from.
const twkCoreStub = '''
sealed class InputEvent {
  const InputEvent();
}

enum KeyCode { char, enter, escape, up, down }

enum KeyKind { press, repeat, release }

final class KeyEvent extends InputEvent {
  const KeyEvent(this.code, {this.char = '', this.kind = KeyKind.press});
  final KeyCode code;
  final String char;
  final KeyKind kind;
  bool get ctrl => false;
}

final class MouseEvent extends InputEvent {
  const MouseEvent();
}

final class EdgeInsets {
  const EdgeInsets.all(int cells);
}
''';

/// The parts of twk the fixtures use.
const twkStub = '''
export 'package:twk_core/twk_core.dart';

abstract class Key {
  const Key();
}

final class ValueKey<T> extends Key {
  const ValueKey(this.value);
  final T value;
}

abstract interface class BuildContext {
  bool get mounted;
}

abstract class Widget {
  const Widget({this.key});
  final Key? key;
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget({super.key});
  Widget build(BuildContext context);
}

abstract class StatefulWidget extends Widget {
  const StatefulWidget({super.key});
  State<StatefulWidget> createState();
}

abstract class State<T extends StatefulWidget> {
  T get widget => throw 0;
  BuildContext get context => throw 0;
  bool get mounted => true;
  void initState() {}
  void dispose() {}
  Widget build(BuildContext context);
  void setState(void Function() fn) {}
}

mixin class ChangeNotifier {
  void addListener(void Function() listener) {}
  void dispose() {}
}

final class TextEditingController with ChangeNotifier {
  TextEditingController({String text = ''});
}

final class ScrollController with ChangeNotifier {}

class FocusNode with ChangeNotifier {}

final class Text extends StatelessWidget {
  const Text(this.data, {super.key});
  final String data;
  @override
  Widget build(BuildContext context) => this;
}

abstract class Flex extends Widget {
  const Flex({this.children = const [], super.key});
  final List<Widget> children;
}

final class Row extends Flex {
  const Row({super.children, super.key});
}

final class Column extends Flex {
  const Column({super.children, super.key});
}

final class Stack extends Widget {
  const Stack({this.children = const [], super.key});
  final List<Widget> children;
}

class Flexible extends Widget {
  const Flexible({required this.child, super.key, this.flex = 1});
  final Widget child;
  final int flex;
}

final class Expanded extends Flexible {
  const Expanded({required super.child, super.key, super.flex});
}

final class Spacer extends StatelessWidget {
  const Spacer({super.key});
  @override
  Widget build(BuildContext context) => this;
}

final class Center extends Widget {
  const Center({super.key, this.child});
  final Widget? child;
}

final class SizedBox extends Widget {
  const SizedBox({super.key, this.width, this.height, this.child});
  final int? width;
  final int? height;
  final Widget? child;
}

typedef WidgetBuilder = Widget Function(BuildContext context);

final class Builder extends StatelessWidget {
  const Builder({required this.builder, super.key});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => builder(context);
}

abstract class ValueListenable<T> {
  T get value;
}

typedef ValueWidgetBuilder<T> =
    Widget Function(BuildContext context, T value, Widget? child);

final class ValueListenableBuilder<T> extends StatefulWidget {
  const ValueListenableBuilder({
    required this.valueListenable,
    required this.builder,
    super.key,
    this.child,
  });
  final ValueListenable<T> valueListenable;
  final ValueWidgetBuilder<T> builder;
  final Widget? child;
  @override
  State<ValueListenableBuilder<T>> createState() => throw 0;
}

final class Padding extends Widget {
  const Padding({required this.padding, super.key, this.child});
  final EdgeInsets padding;
  final Widget? child;
}

final class Border {
  const Border.all();
}

final class Box extends Widget {
  const Box({super.key, this.border, this.child});
  final Border? border;
  final Widget? child;
}

final class TextField extends StatefulWidget {
  const TextField({
    super.key,
    this.controller,
    this.placeholder,
    this.semanticsLabel,
  });
  final TextEditingController? controller;
  final String? placeholder;
  final String? semanticsLabel;
  @override
  State<TextField> createState() => throw 0;
}

final class TextArea extends StatefulWidget {
  const TextArea({super.key, this.placeholder, this.semanticsLabel});
  final String? placeholder;
  final String? semanticsLabel;
  @override
  State<TextArea> createState() => throw 0;
}

final class TextFormField extends StatefulWidget {
  const TextFormField({super.key, this.placeholder, this.semanticsLabel});
  final String? placeholder;
  final String? semanticsLabel;
  @override
  State<TextFormField> createState() => throw 0;
}

final class Slider extends StatefulWidget {
  const Slider({required this.value, super.key, this.semanticsLabel});
  final double value;
  final String? semanticsLabel;
  @override
  State<Slider> createState() => throw 0;
}

final class Checkbox extends StatelessWidget {
  const Checkbox({
    required this.value,
    super.key,
    this.label = '',
    this.semanticsLabel,
  });
  final bool value;
  final String label;
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) => this;
}

final class Switch extends StatelessWidget {
  const Switch({
    required this.value,
    super.key,
    this.label = '',
    this.semanticsLabel,
  });
  final bool value;
  final String label;
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) => this;
}

final class Button extends StatefulWidget {
  const Button(this.label, {required this.onPressed, super.key});
  final String label;
  final void Function()? onPressed;
  @override
  State<Button> createState() => throw 0;
}

final class Spinner extends StatefulWidget {
  const Spinner();
  @override
  State<Spinner> createState() => throw 0;
}

final class InputListener extends StatefulWidget {
  const InputListener({required this.onEvent, required this.child, super.key});
  final bool Function(InputEvent event) onEvent;
  final Widget child;
  @override
  State<InputListener> createState() => throw 0;
}

final class TableCell {
  const TableCell(String text);
}

final class TableColumn<T> {
  const TableColumn({required this.title, required this.cell});
  final String title;
  final TableCell Function(T row) cell;
}

final class KeyCombo {
  const KeyCombo._();
  factory KeyCombo.parse(String spec) => throw 0;
  static List<KeyCombo> parseSequence(String spec, {KeyCombo? leader}) =>
      throw 0;
}

abstract class Intent {
  const Intent();
}

final class KeyBindings extends StatefulWidget {
  const KeyBindings(
    this.bindings, {
    required this.child,
    this.hints = const {},
    super.key,
  });
  final Map<String, void Function()?> bindings;
  final Map<String, String> hints;
  final Widget child;
  @override
  State<KeyBindings> createState() => throw 0;
}

final class Shortcuts extends StatefulWidget {
  const Shortcuts(
    this.shortcuts, {
    required this.child,
    this.hints = const {},
    super.key,
  });
  final Map<String, Intent> shortcuts;
  final Map<String, String> hints;
  final Widget child;
  @override
  State<Shortcuts> createState() => throw 0;
}

final class LeaderKey extends Widget {
  const LeaderKey(this.leader, {required this.child, super.key});
  final String leader;
  final Widget child;
}

final class SelectionArea extends StatefulWidget {
  const SelectionArea({
    required this.child,
    this.copyKey,
    this.clearKey = 'escape',
    super.key,
  });
  final String? copyKey;
  final String? clearKey;
  final Widget child;
  @override
  State<SelectionArea> createState() => throw 0;
}

final class Table<T> extends StatefulWidget {
  const Table({required List<T> this.rows, required this.columns, super.key});
  final List<T>? rows;
  final List<TableColumn<T>> columns;
  @override
  State<Table<T>> createState() => throw 0;
}
''';

/// The parts of twk_term the fixtures use.
const twkTermStub = '''
import 'package:twk/twk.dart';

final class TerminalView extends StatefulWidget {
  const TerminalView({this.ignoredKeys = const [], super.key});
  final List<String> ignoredKeys;
  @override
  State<TerminalView> createState() => throw 0;
}
''';

/// A test of a rule on fixtures that import twk.
abstract class TwkRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage('twk_core').addFile('lib/twk_core.dart', twkCoreStub);
    newPackage('twk').addFile('lib/twk.dart', twkStub);
    newPackage('twk_term').addFile('lib/twk_term.dart', twkTermStub);
    super.setUp();
  }

  /// The rule's diagnostic at the [occurrence]th [text] of [code], over
  /// its first [length] characters (all of them by default).
  ExpectedDiagnostic lintAt(
    String code,
    String text, {
    int occurrence = 0,
    int? length,
    List<Pattern> messageContainsAll = const [],
  }) {
    var offset = code.indexOf(text);
    for (var i = 0; i < occurrence; i++) {
      offset = code.indexOf(text, offset + 1);
    }
    return lint(
      offset,
      length ?? text.length,
      messageContainsAll: messageContainsAll,
    );
  }

  /// Where the last fix [fixed] made leaves the selection: its offset in
  /// the fixed fixture; null where it sets none.
  int? fixSelection;

  /// The fixture of the last analysis as the fix [make] makes it of the
  /// rule's [index]th diagnostic, by offset (the analyzer's own, such as
  /// an unused variable, not counted); null where the fix is not offered.
  Future<String?> fixed(
    CorrectionProducer Function({required CorrectionProducerContext context})
    make, {
    int index = 0,
  }) async {
    final diagnostics = [
      for (final d in result.diagnostics)
        if (rule.diagnosticCodes.contains(d.diagnosticCode)) d,
    ]..sort((a, b) => a.offset.compareTo(b.offset));
    final diagnostic = diagnostics[index];
    final library = await result.session.getResolvedLibrary(result.path);
    final producer = make(
      context: CorrectionProducerContext.createResolved(
        libraryResult: library as ResolvedLibraryResult,
        unitResult: result,
        diagnostic: diagnostic,
        selectionOffset: diagnostic.offset,
        selectionLength: diagnostic.length,
      ),
    );
    final builder = ChangeBuilder(session: result.session);
    await producer.compute(builder);
    // each read of sourceChange adds the imports to it again
    final change = builder.sourceChange;
    final edits = change.edits;
    fixSelection = change.selection?.offset;
    if (edits.isEmpty) {
      return null;
    }
    return SourceEdit.applySequence(result.content, edits.single.edits);
  }
}

/// A test of an assist of this package on fixtures that import twk.
abstract class TwkAssistTest extends AssistProcessorTest {
  @override
  void setUp() {
    super.setUp();
    for (final generator in [
      WrapInWidget.new,
      WrapWithPadding.new,
      WrapWithBox.new,
      WrapWithCenter.new,
      WrapWithSizedBox.new,
      WrapWithRow.new,
      WrapWithColumn.new,
      WrapWithExpanded.new,
      WrapWithFlexible.new,
      WrapWithBuilder.new,
      WrapWithValueListenableBuilder.new,
      ConvertToStatefulWidget.new,
      ConvertToStatelessWidget.new,
      ExtractWidget.new,
      RemoveWidget.new,
      SwapWithChild.new,
      SwapWithParent.new,
      MoveWidgetUp.new,
      MoveWidgetDown.new,
    ]) {
      registeredAssistGenerators.registerGenerator(generator);
    }
    newFile('/packages/twk_core/lib/twk_core.dart', twkCoreStub);
    newFile('/packages/twk/lib/twk.dart', twkStub);
    writeTestPackageConfig2(
      config: PackageConfigFileBuilder()
        ..add(name: 'twk_core', rootFolder: getFolder('/packages/twk_core'))
        ..add(name: 'twk', rootFolder: getFolder('/packages/twk')),
    );
  }
}

/// Expects [change] in the one shape the analysis server sends to the
/// editor as a snippet, its linked edit groups the tab stops the editor
/// selects for typing: one `SourceEdit` of one file, and a group.
///
/// For any other shape, two edits of the file among them, the server's
/// `createWorkspaceEdit` (pkg/analysis_server, lib/src/lsp/mapping.dart)
/// sends a plain edit and the groups are lost: the name is left to be
/// renamed by hand. Dart-Code holds to the same (one file, one edit) in
/// the code actions it applies as snippets.
void expectSnippetShape(SourceChange change) {
  expect(change.edits, hasLength(1), reason: 'one file edited');
  expect(
    change.edits.single.edits,
    hasLength(1),
    reason: 'one edit of the file: more, and the editor gets no snippet',
  );
  expect(change.linkedEditGroups, isNotEmpty);
}
