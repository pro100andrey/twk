// The Animation group of the gallery.

import 'dart:async';

import 'package:twk/twk.dart';

import '../../page.dart';
import '../kit/kit.dart';

part '_shared.dart';
part 'animatedalign_animatedpadding.dart';
part 'animatedbox.dart';
part 'animatedbuilder.dart';
part 'animateddefaulttextstyle.dart';
part 'animatedopacity_opacity.dart';
part 'animatedpositioned.dart';
part 'animatedsize.dart';
part 'animatedswitcher.dart';
part 'animationcontroller.dart';
part 'dissolve_fractionaltranslation.dart';
part 'effect.dart';
part 'progressbar.dart';
part 'progresslist.dart';
part 'skeleton_skeletonize.dart';
part 'spinner.dart';
part 'tweenanimationbuilder.dart';

/// The pages of the Animation group that draw.
final animationPages = <GalleryPage>[
  _spinner,
  _progressBar,
  _progressList,
  _skeleton,
  _controller,
  _builder,
  _align,
  _positioned,
  _box,
  _opacity,
  _textStyle,
  _size,
  _tween,
  _switcher,
  _dissolve,
  _effect,
];
