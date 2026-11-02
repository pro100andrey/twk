// The Text group of the gallery.

import 'dart:math' as math;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show BidiText, TextDirection;

import '../../page.dart';
import '../kit/kit.dart';

part 'ansi.dart';
part 'defaulttextstyle.dart';
part 'rich_text.dart';
part 'right_to_left.dart';
part 'text_page.dart';

/// The group of the catalog these pages are in.
const _group = 'Text';

/// The pages of the Text group that draw.
final textPages = <GalleryPage>[
  _textPage,
  _richTextPage,
  _defaulttextstylePage,
  _rightToLeftPage,
  _ansi,
];
