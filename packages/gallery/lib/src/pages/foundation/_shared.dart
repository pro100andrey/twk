// What the pages of the group share.
part of 'foundation.dart';

/// When the page was first built, in ms: at 0 while time is frozen.
int _born(Map<String, Object?> state, Motion motion) =>
    (state['born'] ??= motion.frozen ? 0 : motion.now.inMilliseconds) as int;
