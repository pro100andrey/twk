// The Scrolling group of the gallery.

import 'package:twk/twk.dart';

import '../../page.dart';
import '../kit/kit.dart';

part '_shared.dart';
part 'listview.dart';
part 'logview.dart';
part 'scrollable.dart';
part 'scrollbar.dart';
part 'singlechildscrollview.dart';

/// The group of the catalog these pages are in.
const _group = 'Scrolling';

/// The pages of the Scrolling group that draw.
final scrollingPages = <GalleryPage>[
  _singlechildscrollviewPage,
  _scrollablePage,
  _listviewPage,
  _logviewPage,
  _scrollbarPage,
];
