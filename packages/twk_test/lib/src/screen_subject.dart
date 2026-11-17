/// What the matchers of the screen read: [ScreenSubject], a [TwkTester]'s
/// screen or a driven app's ([DriverScreen]).
///
/// @docImport 'driver_screen.dart';
/// @docImport 'matchers.dart';
/// @docImport 'tester.dart';
library;

import '../vt.dart';
import 'finders.dart';

/// The screen a matcher of [containsLine], [hasTextAt], [styleAt],
/// [cursorAt] and [matchesScreen] reads, and what its mismatch adds after
/// the screen.
abstract interface class ScreenSubject {
  /// The emulator that has the screen.
  Vt get vt;

  /// The rows of the screen as text.
  List<String> get lines;

  /// The rows of [region] as text.
  List<String> linesIn(CellRect region);

  /// The cursor's column and row.
  (int, int) get cursor;

  /// Whether the cursor shows.
  bool get cursorVisible;

  /// The cells the one widget [finder] finds takes; a [StateError] saying
  /// why where they cannot be told.
  CellRect rect(Finder finder);

  /// What a mismatch adds after the screen: the app's widget tree.
  String get context;
}
