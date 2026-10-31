// What the pages of the group share.
part of 'overlays.dart';

/// How the panels of a page stand out: PanelLook's names, raised first.
final _lookOption = ChoiceOption<String>(
  'look',
  'look',
  values: [for (final l in PanelLook.values) l.name],
);

/// The look [o] chooses.
PanelLook _lookOf(Options o) => PanelLook.values.byName(o(_lookOption));

/// The Code's line that passes the look [o] chooses, [indent] in; none
/// for the default, raised.
List<String> _lookLine(Options o, String indent) => [
  if (_lookOf(o) != PanelLook.raised)
    '${indent}look: .${o.nameOf(_lookOption)},',
];
