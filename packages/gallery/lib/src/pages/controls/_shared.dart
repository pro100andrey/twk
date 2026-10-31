// What the pages of the group share.
part of 'controls.dart';

/// The look of a control's popup, raised or bordered, [disabled] as
/// [PageOption.disabled] says: one option of the pages of Select,
/// DatePicker and Autocomplete.
ChoiceOption popupLookOption({bool Function(Options options)? disabled}) =>
    ChoiceOption(
      'popup',
      'popup look',
      values: const ['raised', 'bordered'],
      disabled: disabled,
    );

/// The [PanelLook] of [popupLookOption] in [o].
PanelLook popupLookOf(Options o) => PanelLook.values.byName(o.choice('popup'));

/// The Code's `popupLook:` line of [popupLookOption] in [o], [pad] columns
/// in, where it is not the default.
List<String> popupLookArg(Options o, String pad) => [
  if (popupLookOf(o) != PanelLook.raised)
    '${pad}popupLook: .${popupLookOf(o).name},',
];
