// The Style group of the gallery.

import 'dart:async';

import 'package:twk/twk.dart';

import '../../page.dart';
import '../kit/kit.dart';

part 'gradient.dart';
part 'gradientbackground.dart';
part 'gradientforeground.dart';
part 'swatches.dart';
part 'terminalbrightness.dart';
part 'theme.dart';

/// The pages of the Style group that draw.
final stylePages = <GalleryPage>[
  _themePage,
  _terminalbrightnessPage,
  _gradientbackgroundPage,
  _gradientforegroundPage,
];
