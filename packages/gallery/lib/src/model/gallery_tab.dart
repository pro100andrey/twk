// The two tabs of a page: its widget on the stage, and the Dart that
// builds it.

/// A page's tab: [preview], the widget on the stage, or [code], the Dart
/// that builds it; a route's `tab=` names the Code one.
enum GalleryTab {
  preview,
  code;

  /// The other tab: what `c` changes to.
  GalleryTab get other => this == preview ? code : preview;
}
