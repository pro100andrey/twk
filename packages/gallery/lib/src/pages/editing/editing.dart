// The Editing group of the gallery.

import 'package:twk/twk.dart';

import '../../page.dart';
import '../controls/controls.dart'
    show popupLookArg, popupLookOf, popupLookOption;
import '../kit/kit.dart';

part '_shared.dart';
part 'autocomplete.dart';
part 'inputdecoration.dart';
part 'textarea.dart';
part 'textfield.dart';

/// The pages of the Editing group that draw.
final editingPages = <GalleryPage>[
  _textfieldPage,
  _inputdecorationPage,
  _textareaPage,
  _autocompletePage,
];
