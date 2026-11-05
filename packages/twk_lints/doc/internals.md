# How twk_lints works and is tested

For those who work on the package. The [README](../README.md) is where to
start with using it, the [reference](reference.md) lists every rule.

## What it is built on

An analyzer plugin for apps built on [twk](https://pub.dev/packages/twk):
warnings and lints that `dart analyze` and the editor report, and assists that
the editor offers at the cursor. It is a plugin of the analysis server's own
plugin system (Dart 3.10 and later), on `analysis_server_plugin` 0.3 and
`analyzer` 14, the analyzer that version of the plugin package pins; it does
not depend on twk, and knows twk's classes by name and package (`package:twk`,
`package:twk_core`); its tests alone depend on twk, to hold what it ports of
twk to twk.

## What works where

`dart analyze` runs the plugin and reports its warnings and the lints turned
on, with the analyzer's own diagnostics; warnings fail it as the analyzer's
do. In an editor the analysis server reports the same as you type and offers
the assists. Checked from a scratch app on the SDK of this repository
(3.13.5): `dart analyze` reported each rule, and an LSP client of
`dart language-server` got the assists as code actions, and the edits of the
tree edits (remove, swap, move), of the wraps and of Convert to
StatelessWidget as their tests have them. What an assist leaves to be named
(Wrap with widget...'s `widget`, SizedBox's sizes, ValueListenableBuilder's
`valueListenable`, Extract widget's `NewWidget`) the server sends as a
snippet, which VS Code (with Dart-Code 3.144, Dart 3.13.7) selects to be typed
over, only when the change is one edit of one file: with more it sends a plain
edit, and the name stays to be renamed by hand. Extract widget therefore
rewrites the text from the widget to the end of its declaration in one
replacement; where twk has to be imported for it, the import is a second edit
and the snippet is lost. This repository enables the plugin, with
`wall_time_in_tests`, in the `analysis_options.yaml` of every package and tool
(and `unnamed_control` in twk's and the gallery's), so that the analyze steps
of its handover enforce it; each package's own `dart analyze` is what counts
there, as an analyze from a directory above several packages left out some of
the plugin's findings in the packages below (Dart 3.13.5). custom_lint, the
other way to write such a plugin, is not used: its last release (0.8.1,
September 2025) takes analyzer 8, which knows the language of a year ago, and
runs on the old plugin system.

## Tests

`test/support.dart` holds stubs of the parts of twk and twk_core the fixtures
use, as packages the fixtures import, and the test bases: a rule's on
`analyzer_testing`'s `AnalysisRuleTest`, which analyzes a fixture with the
rule and compares the diagnostics (`lintAt` finds where one is expected by its
text), and an assist's on its `AssistProcessorTest`, which applies the assist
at the `^` of a fixture and compares the result. `test/rules/<rule>_test.dart`
and `test/assists/<assist>_test.dart` are run by `test_reflective_loader`,
whose test methods are named `test_*`; a rule's test checks its fix with
`fixed`, which applies it to one of the rule's diagnostics of the fixture (the
analyzer's own, such as an unused variable, not counted).
`test/key_names_test.dart` holds `key_names`' port of twk's key names to twk,
twk_core and twk_test, its dev dependencies, which do not reach the plugin.
`test/plugin_test.dart` checks what the plugin registers: its warnings, its
lints, its fixes and its assists.

The checks, from this directory:

```bash
dart pub get
dart analyze
dart test
dart format --output=none --set-exit-if-changed lib test
```
