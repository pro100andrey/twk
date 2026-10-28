// The pages that draw, by group, in the catalog's order: a group's file
// holds its list.
import '../page.dart';
import 'animation.dart';
import 'app.dart';
import 'controls.dart';
import 'data.dart';
import 'debugging.dart';
import 'editing.dart';
import 'focus.dart';
import 'foundation.dart';
import 'framework.dart';
import 'images.dart';
import 'layout.dart';
import 'mouse.dart';
import 'navigation.dart';
import 'overlays.dart';
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
