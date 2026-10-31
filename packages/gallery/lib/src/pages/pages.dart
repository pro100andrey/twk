// The pages that draw, by group, in the catalog's order: a group's file
// holds its list.
import '../page.dart';
import 'animation/animation.dart';
import 'app/app.dart';
import 'controls/controls.dart';
import 'data/data.dart';
import 'debugging/debugging.dart';
import 'editing/editing.dart';
import 'focus/focus.dart';
import 'foundation/foundation.dart';
import 'framework/framework.dart';
import 'images/images.dart';
import 'layout/layout.dart';
import 'mouse/mouse.dart';
import 'navigation/navigation.dart';
import 'overlays/overlays.dart';
import 'rich.dart';
import 'screen_readers.dart';
import 'scrolling.dart';
import 'style.dart';
import 'terminal.dart';
import 'text.dart';

/// Every page that draws; the catalog's others show a placeholder.
final List<GalleryPage> galleryPages = [
  ...textPages,
  ...layoutPages,
  ...stylePages,
  ...scrollingPages,
  ...dataPages,
  ...editingPages,
  ...controlsPages,
  ...overlayPages,
  ...animationPages,
  ...mousePages,
  ...focusPages,
  ...navigationPages,
  ...foundationPages,
  ...frameworkPages,
  ...appPages,
  ...screenReaderPages,
  ...debuggingPages,
  ...richPages,
  ...imagePages,
  ...terminalPages,
];
