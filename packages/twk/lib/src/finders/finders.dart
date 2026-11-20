/// Finders as data: the values that pick elements out of an app's tree,
/// which JSON carries (`ElementFinder`) between a driver and the app
/// (`ext.twk.find`) and which twk_test's `find` evaluates in-process, and
/// the cells of a render object the screen shows (`shown`).
library;

export 'element_finder.dart' show ElementFinder;
export 'shown.dart';
