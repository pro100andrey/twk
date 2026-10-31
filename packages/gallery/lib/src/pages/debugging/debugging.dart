// The Debugging group of the gallery.

import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../../page.dart';
import '../../paint.dart';
import '../../view/tokens.dart';
import '../kit/kit.dart';

part 'aids.dart';
part 'console.dart';
part 'frameoverlay.dart';
part 'repaint_rainbow.dart';
part 'repaintboundary.dart';

/// The pages of the Debugging group that draw.
final List<GalleryPage> debuggingPages = [
  _console,
  _frameOverlay,
  _repaintRainbow,
  _repaintBoundary,
];
