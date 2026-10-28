/// Whether a library is under its package's tests, asked of the analyzer
/// once per library for every rule: [inTestDirectory].
library;

import 'package:analyzer/analysis_rule/rule_context.dart';

/// [RuleContext.isInTestDirectory] of [context], kept while the context
/// is. The plugin gives one context to every rule of a library, and the
/// analyzer looks the folders up on each call (about 11 µs).
bool inTestDirectory(RuleContext context) =>
    _inTests[context] ??= context.isInTestDirectory;

final _inTests = Expando<bool>('isInTestDirectory');
