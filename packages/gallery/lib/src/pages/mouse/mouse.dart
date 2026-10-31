// The Mouse group of the gallery.

import 'package:twk/twk.dart';

import '../../page.dart';
import '../kit/kit.dart';

part '_shared.dart';
part 'draggable_dragtarget.dart';
part 'gesturedetector.dart';
part 'ignorepointer_absorbpointer.dart';
part 'listener_mouseregion.dart';
part 'selectionarea.dart';

/// The group of the catalog these pages are in.
const _group = 'Mouse';

/// The pages of the Mouse group that draw.
final mousePages = <GalleryPage>[
  _gesturedetectorPage,
  _listenerMouseregionPage,
  _ignorepointerAbsorbpointerPage,
  _selectionareaPage,
  _draggableDragtargetPage,
];
