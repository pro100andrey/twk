part of '../sample_app.dart';

extension on _SampleAppState {
  /// No rows: a status a screen reader reads as `status saved, 2 files`,
  /// a tab bar of its own nodes, and a barrier over what is before it,
  /// leaving out what is below it.
  List<Widget> _semantics() => const [
    Semantics(
      role: SemanticsRole.status,
      label: 'saved',
      value: '2 files',
      child: Semantics(
        role: SemanticsRole.tabList,
        nodes: [
          SemanticsNode(
            role: SemanticsRole.tab,
            label: 'one',
            state: SemanticsState(selected: true),
            focused: true,
          ),
          SemanticsNode(role: SemanticsRole.tab, label: 'two'),
        ],
        child: BlockSemantics(
          child: ExcludeSemantics(child: SizedBox.shrink()),
        ),
      ),
    ),
  ];
}
