import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// Matches a notifier disposed: adding a listener fails an assert.
final Matcher isDisposed = isA<ChangeNotifier>().having(
  (notifier) =>
      () => notifier.addListener(() {}),
  'adding a listener',
  throwsA(isA<AssertionError>()),
);
