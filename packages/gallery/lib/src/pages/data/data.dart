// The Data group of the gallery.

import 'dart:async';
import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../../page.dart';
import '../kit/kit.dart';

part '_shared.dart';
part 'barchart.dart';
part 'calendar.dart';
part 'chart.dart';
part 'descriptionlist.dart';
part 'directorytree.dart';
part 'dotcanvas.dart';
part 'gauge_linegauge.dart';
part 'heatmap_activityheatmap.dart';
part 'sparkline.dart';
part 'table.dart';
part 'tasklist.dart';
part 'treetable.dart';
part 'treeview.dart';

/// The pages of the Data group that draw, in the catalog's order.
final List<GalleryPage> dataPages = [
  _sparkline,
  _gauge,
  _barChart,
  _chart,
  _dotCanvas,
  _heatmap,
  _calendar,
  _table,
  _descriptionList,
  _treeView,
  _treeTable,
  _directoryTree,
  _taskList,
];
