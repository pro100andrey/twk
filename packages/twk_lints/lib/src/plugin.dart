/// The plugin, [TwkLintsPlugin]: the rules, fixes and assists it
/// registers.
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'assists/convert_to_stateful_widget.dart';
import 'assists/convert_to_stateless_widget.dart';
import 'assists/extract_widget.dart';
import 'assists/move_widget.dart';
import 'assists/remove_widget.dart';
import 'assists/swap_widgets.dart';
import 'assists/wrap.dart';
import 'assists/wrap_builder.dart';
import 'assists/wrap_flex.dart';
import 'fixes/add_mounted_check.dart';
import 'fixes/add_row_type.dart';
import 'fixes/add_semantics_label.dart';
import 'fixes/add_value_key.dart';
import 'fixes/dispose_field.dart';
import 'fixes/elapse_fake_clock.dart';
import 'fixes/use_key_bindings.dart';
import 'rules/context_after_await.dart';
import 'rules/dispose_controllers.dart';
import 'rules/key_names.dart';
import 'rules/missing_key_in_children.dart';
import 'rules/prefer_key_bindings.dart';
import 'rules/set_state_after_dispose.dart';
import 'rules/unnamed_control.dart';
import 'rules/untyped_table.dart';
import 'rules/wall_time_in_tests.dart';

/// The plugin: its warnings are on wherever it is enabled, its lints where
/// the analysis options turn them on.
final class TwkLintsPlugin extends Plugin {
  @override
  String get name => 'twk_lints';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(SetStateAfterDispose())
      ..registerWarningRule(ContextAfterAwait())
      ..registerWarningRule(DisposeControllers())
      ..registerWarningRule(KeyNames())
      ..registerLintRule(MissingKeyInChildren())
      ..registerLintRule(UntypedTable())
      ..registerLintRule(PreferKeyBindings())
      ..registerLintRule(WallTimeInTests())
      ..registerLintRule(UnnamedControl())
      ..registerFixForRule(
        SetStateAfterDispose.afterAwait,
        AddMountedCheck.new,
      )
      ..registerFixForRule(ContextAfterAwait.code, AddMountedCheck.new)
      ..registerFixForRule(UnnamedControl.code, AddSemanticsLabel.new)
      ..registerFixForRule(DisposeControllers.code, DisposeField.new)
      ..registerFixForRule(MissingKeyInChildren.code, AddValueKey.new)
      ..registerFixForRule(UntypedTable.code, AddRowType.new)
      ..registerFixForRule(PreferKeyBindings.code, UseKeyBindings.new)
      ..registerFixForRule(WallTimeInTests.code, ElapseFakeClock.new)
      ..registerAssist(WrapInWidget.new)
      ..registerAssist(WrapWithPadding.new)
      ..registerAssist(WrapWithBox.new)
      ..registerAssist(WrapWithCenter.new)
      ..registerAssist(WrapWithSizedBox.new)
      ..registerAssist(WrapWithRow.new)
      ..registerAssist(WrapWithColumn.new)
      ..registerAssist(WrapWithExpanded.new)
      ..registerAssist(WrapWithFlexible.new)
      ..registerAssist(WrapWithBuilder.new)
      ..registerAssist(WrapWithValueListenableBuilder.new)
      ..registerAssist(ConvertToStatefulWidget.new)
      ..registerAssist(ConvertToStatelessWidget.new)
      ..registerAssist(ExtractWidget.new)
      ..registerAssist(RemoveWidget.new)
      ..registerAssist(SwapWithChild.new)
      ..registerAssist(SwapWithParent.new)
      ..registerAssist(MoveWidgetUp.new)
      ..registerAssist(MoveWidgetDown.new);
  }
}
