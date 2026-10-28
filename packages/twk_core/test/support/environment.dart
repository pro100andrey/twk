// The environment a test gives a program it starts: the process's without
// twk's own variables, so that what the shell running the tests exports
// changes nothing in the program.
import 'dart:io';

/// The process's environment without the variables twk reads (`TWK_*`:
/// `TWK_DEBUG`, `TWK_LOG`, `TWK_SCREEN_READER`, ...), with [given] over it.
/// Passed with `includeParentEnvironment: false`, it is all a started
/// program sees of twk's variables: those the test means to set.
Map<String, String> childEnvironment([
  Map<String, String> given = const {},
]) => {
  for (final MapEntry(:key, :value) in Platform.environment.entries)
    if (!key.startsWith('TWK_')) key: value,
  ...given,
};
