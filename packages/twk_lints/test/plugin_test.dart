// The plugin: what it registers, the warnings on by default, the lints
// off until the analysis options turn them on, its fixes and its assists.
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';
import 'package:test/test.dart';
import 'package:twk_lints/main.dart';
import 'package:twk_lints/src/assists/convert_to_stateful_widget.dart';
import 'package:twk_lints/src/assists/convert_to_stateless_widget.dart';
import 'package:twk_lints/src/assists/extract_widget.dart';
import 'package:twk_lints/src/assists/move_widget.dart';
import 'package:twk_lints/src/assists/remove_widget.dart';
import 'package:twk_lints/src/assists/swap_widgets.dart';
import 'package:twk_lints/src/assists/wrap.dart';
import 'package:twk_lints/src/assists/wrap_builder.dart';
import 'package:twk_lints/src/assists/wrap_flex.dart';
import 'package:twk_lints/src/fixes/add_mounted_check.dart';
import 'package:twk_lints/src/fixes/add_row_type.dart';
import 'package:twk_lints/src/fixes/add_semantics_label.dart';
import 'package:twk_lints/src/fixes/add_value_key.dart';
import 'package:twk_lints/src/fixes/dispose_field.dart';
import 'package:twk_lints/src/fixes/elapse_fake_clock.dart';
import 'package:twk_lints/src/fixes/use_key_bindings.dart';
import 'package:twk_lints/src/rules/context_after_await.dart';
import 'package:twk_lints/src/rules/dispose_controllers.dart';
import 'package:twk_lints/src/rules/missing_key_in_children.dart';
import 'package:twk_lints/src/rules/prefer_key_bindings.dart';
import 'package:twk_lints/src/rules/set_state_after_dispose.dart';
import 'package:twk_lints/src/rules/unnamed_control.dart';
import 'package:twk_lints/src/rules/untyped_table.dart';
import 'package:twk_lints/src/rules/wall_time_in_tests.dart';

/// Keeps what a plugin registers.
final class _Registry implements PluginRegistry {
  final warnings = <String>[];
  final lints = <String>[];
  final assists = <Object>[];
  final fixes = <(DiagnosticCode, Object)>[];

  @override
  void registerWarningRule(AbstractAnalysisRule rule) =>
      warnings.add(rule.name);

  @override
  void registerLintRule(AbstractAnalysisRule rule) => lints.add(rule.name);

  @override
  void registerAssist(Object generator) => assists.add(generator);

  @override
  void registerFixForRule(DiagnosticCode code, Object generator) =>
      fixes.add((code, generator));

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

void main() {
  test('the plugin is named twk_lints and registers its warnings, lints, '
      'fixes and assists', () {
    final registry = _Registry();
    plugin.register(registry);
    expect(plugin.name, 'twk_lints');
    expect(registry.warnings, [
      'set_state_after_dispose',
      'context_after_await',
      'dispose_controllers',
      'key_names',
    ]);
    expect(registry.fixes, [
      (SetStateAfterDispose.afterAwait, AddMountedCheck.new),
      (ContextAfterAwait.code, AddMountedCheck.new),
      (UnnamedControl.code, AddSemanticsLabel.new),
      (DisposeControllers.code, DisposeField.new),
      (MissingKeyInChildren.code, AddValueKey.new),
      (UntypedTable.code, AddRowType.new),
      (PreferKeyBindings.code, UseKeyBindings.new),
      (WallTimeInTests.code, ElapseFakeClock.new),
    ]);
    expect(registry.lints, [
      'missing_key_in_children',
      'untyped_table',
      'prefer_key_bindings',
      'wall_time_in_tests',
      'unnamed_control',
    ]);
    expect(registry.assists, [
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
    ]);
  });
}
