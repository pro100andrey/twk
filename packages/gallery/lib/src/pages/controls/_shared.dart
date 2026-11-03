// What the pages of the group share.
part of 'controls.dart';

/// The look of a control's popup, raised or bordered, [disabled] as
/// [PageOption.disabled] says: one option of the pages of Select,
/// DatePicker and Autocomplete.
ChoiceOption<String> popupLookOption({
  bool Function(Options options)? disabled,
}) => ChoiceOption(
  'popup',
  'popup look',
  values: const ['raised', 'bordered'],
  disabled: disabled,
);

/// What [popupLookOf] reads [popupLookOption] by.
const _popupLook = ChoiceOption<String>(
  'popup',
  'popup look',
  values: ['raised', 'bordered'],
);

/// The [PanelLook] of [popupLookOption] in [o].
PanelLook popupLookOf(Options o) => PanelLook.values.byName(o(_popupLook));

/// The Code's `popupLook:` line of [popupLookOption] in [o], [pad] columns
/// in, where it is not the default.
List<String> popupLookArg(Options o, String pad) => [
  if (popupLookOf(o) != PanelLook.raised)
    '${pad}popupLook: .${popupLookOf(o).name},',
];
