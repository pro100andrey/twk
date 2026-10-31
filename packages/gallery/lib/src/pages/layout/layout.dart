// The Layout group of the gallery.

import 'dart:async';
import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../../page.dart';
import '../kit/kit.dart';

part '_shared.dart';
part 'align_center.dart';
part 'box.dart';
part 'coloredbox_decoratedbox.dart';
part 'constrainedbox.dart';
part 'container.dart';
part 'custompaint.dart';
part 'divider.dart';
part 'dockarea.dart';
part 'expanded_spacer.dart';
part 'expansiontile_accordion.dart';
part 'fractionallysizedbox.dart';
part 'grid_gridplacement.dart';
part 'intrinsicwidth_height.dart';
part 'limitedbox_overflowbox.dart';
part 'padding.dart';
part 'row_column_flex.dart';
part 'scaffold.dart';
part 'shadow.dart';
part 'sizedbox.dart';
part 'splitview.dart';
part 'stack_positioned.dart';
part 'transform.dart';
part 'visibility_offstage.dart';
part 'wrap.dart';

/// The pages of the Layout group that draw.
final layoutPages = <GalleryPage>[
  _box,
  _decoratedBox,
  _container,
  _divider,
  _shadow,
  _padding,
  _alignCenter,
  _sizedBox,
  _constrainedBox,
  _limitedBox,
  _fractionallySizedBox,
  _intrinsic,
  _flex,
  _expanded,
  _stack,
  _transform,
  _visibility,
  _expansion,
  _grid,
  _wrap,
  _customPaint,
  _splitView,
  _dockArea,
  _scaffold,
];
