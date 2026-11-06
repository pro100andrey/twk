// The Controls group of the gallery.

import 'dart:async';

import 'package:twk/twk.dart';

import '../../page.dart';
import '../kit/kit.dart';

part '_shared.dart';
part 'button.dart';
part 'callout.dart';
part 'checkbox_switch.dart';
part 'chip_chiplist.dart';
part 'confirminput.dart';
part 'datepicker.dart';
part 'filepicker.dart';
part 'form_formfield.dart';
part 'hyperlink.dart';
part 'keyhintsbar.dart';
part 'listtile.dart';
part 'numberinput.dart';
part 'pressable.dart';
part 'radiogroup.dart';
part 'segmentedbutton.dart';
part 'select_multiselect.dart';
part 'selectionlist.dart';
part 'slider.dart';
part 'statusbar.dart';
part 'statusmessage_badge.dart';
part 'tabbar_tabbarview.dart';
part 'valuestepper.dart';

/// The group of the catalog these pages are in.
const _group = 'Controls';

/// The pages of the Controls group that draw.
final List<GalleryPage> controlsPages = [
  _buttonPage,
  _pressablePage,
  _checkboxSwitchPage,
  _radiogroupPage,
  _segmented,
  _chipsPage,
  _stepperPage,
  _selectionlistPage,
  _selectMultiselectPage,
  _confirminputPage,
  _sliderPage,
  _numberinputPage,
  _datepickerPage,
  _filepickerPage,
  _formFormfieldPage,
  _tabbarTabviewPage,
  _keyhintsbarPage,
  _statusmessageBadgePage,
  _callout,
  _linkPage,
  _listtilePage,
  _statusbarPage,
];
