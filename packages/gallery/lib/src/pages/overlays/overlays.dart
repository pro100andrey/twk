// The Overlays group of the gallery.

import 'dart:async';

import 'package:twk/twk.dart';

import '../../page.dart';
import '../kit/kit.dart';

part '_shared.dart';
part 'app.dart';
part 'commandpalette.dart';
part 'contextmenu.dart';
part 'dialog.dart';
part 'menubar.dart';
part 'modalbarrier.dart';
part 'optionlist.dart';
part 'overlay.dart';
part 'popover.dart';
part 'toast.dart';
part 'tooltip.dart';
part 'windowlayer.dart';

/// The group of the catalog these pages are in.
const _group = 'Overlays';

/// The pages of the Overlays group that draw.
final overlayPages = <GalleryPage>[
  _overlayPage,
  _appPage,
  _dialogPage,
  _toastPage,
  _tooltipPage,
  _popoverPage,
  _menubarPage,
  _contextmenuPage,
  _commandpalettePage,
  _optionlistPage,
  _modalbarrierPage,
  _windowlayerPage,
];
