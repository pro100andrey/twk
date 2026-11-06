/// The words twk writes itself: [TwkStrings], and [Localizations] that
/// gives them to the widgets below.
library;

import '../framework/framework.dart';

// Examples can assume:
// late Widget app;

/// The words twk's widgets and `Cli` prompts write on their own, in
/// English unless given others: the `ETA` of a progress list, the hint of
/// a yes or no question, what a refused answer says.
///
/// Plain data: the words of a language are a [TwkStrings] an app builds
/// from whatever holds its translations (slang, `intl`, a map) and gives
/// to [Localizations] for its widgets, or to `Cli(strings:)` for a
/// console. There is no global and no default to set: a widget with no
/// [Localizations] above it writes English.
///
/// A message with a number or a time in it is a function of that value, so
/// that a language can put it where it belongs.
///
/// ```dart
/// const german = TwkStrings(eta: _eta, yes: 'ja', no: 'nein');
/// String _eta(String time) => 'noch $time';
/// ```
///
/// A confirmation read from a log takes `y`, `yes`, `n` and `no` whatever
/// the language, and [yes] and [no] too, or their first letters.
final class TwkStrings {
  /// The words given, English for those not.
  const TwkStrings({
    this.tookIn = _tookIn,
    this.eta = _eta,
    this.moreTasks = _moreTasks,
    this.confirmHint = 'y/n',
    this.confirmHintYes = 'Y/n',
    this.confirmHintNo = 'y/N',
    this.yes = 'yes',
    this.no = 'no',
    this.none = 'none',
    this.yesLabel = 'Yes',
    this.noLabel = 'No',
    this.answerYesOrNo = 'answer y or n',
    this.enterNumber = 'Enter a number',
    this.enterNumbers = 'Enter numbers separated by commas',
    this.answerNumber = _answerNumber,
    this.answerNumbers = _answerNumbers,
    this.chooseAtLeast = _chooseAtLeast,
    this.chooseAtMost = _chooseAtMost,
    this.typeToFilter = 'type to filter',
    this.spaceToToggle = 'space to toggle',
    this.typeToFilterAndToggle = 'type to filter, space to toggle',
    this.decimalSeparator = '.',
  });

  /// What follows a finished task's message in a log, from how long it
  /// took (`formatTook`): ` in 3s`, led by a space.
  final String Function(String took) tookIn;

  /// The time left of a running task in a progress list, from the time
  /// as `00:07`: `ETA 00:07`.
  final String Function(String time) eta;

  /// The row of a progress list standing for the tasks not shown: `+3
  /// more`.
  final String Function(int count) moreTasks;

  /// The hint of a yes or no question without a default.
  final String confirmHint;

  /// The hint of a yes or no question that takes yes by default.
  final String confirmHintYes;

  /// The hint of a yes or no question that takes no by default.
  final String confirmHintNo;

  /// The answer to a yes or no question as it is written down.
  final String yes;

  /// The answer to a yes or no question, no, as it is written down.
  final String no;

  /// The answer to a choice of any when nothing is chosen.
  final String none;

  /// The label of yes in the interactive yes or no question.
  final String yesLabel;

  /// The label of no in the interactive yes or no question.
  final String noLabel;

  /// Why a yes or no question was asked again.
  final String answerYesOrNo;

  /// The prompt of a choice of one in a log.
  final String enterNumber;

  /// The prompt of a choice of any in a log.
  final String enterNumbers;

  /// Why a choice of one was asked again, from the number of choices.
  final String Function(int count) answerNumber;

  /// Why a choice of any was asked again, from the number of choices.
  final String Function(int count) answerNumbers;

  /// Why fewer than the minimum were chosen.
  final String Function(int min) chooseAtLeast;

  /// Why more than the maximum were chosen.
  final String Function(int max) chooseAtMost;

  /// The hint of a choice that can be filtered.
  final String typeToFilter;

  /// The hint of a choice of any.
  final String spaceToToggle;

  /// The hint of a choice of any that can be filtered.
  final String typeToFilterAndToggle;

  /// What stands for the point in the sizes and times twk writes: `4.5
  /// GB` and `3.1 s` with the default `.`, `4,5 GB` and `3,1 s` with `,`.
  final String decimalSeparator;

  /// The words at [context]: those of the nearest [Localizations], else
  /// English. [context] depends on them, so that a widget is built again
  /// when they change.
  // a lookup in the tree, as Theme.of is, not a constructor
  // ignore: prefer_constructors_over_static_methods
  static TwkStrings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Localizations>()?.strings ??
      const TwkStrings();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TwkStrings &&
          tookIn == other.tookIn &&
          eta == other.eta &&
          moreTasks == other.moreTasks &&
          confirmHint == other.confirmHint &&
          confirmHintYes == other.confirmHintYes &&
          confirmHintNo == other.confirmHintNo &&
          yes == other.yes &&
          no == other.no &&
          none == other.none &&
          yesLabel == other.yesLabel &&
          noLabel == other.noLabel &&
          answerYesOrNo == other.answerYesOrNo &&
          enterNumber == other.enterNumber &&
          enterNumbers == other.enterNumbers &&
          answerNumber == other.answerNumber &&
          answerNumbers == other.answerNumbers &&
          chooseAtLeast == other.chooseAtLeast &&
          chooseAtMost == other.chooseAtMost &&
          typeToFilter == other.typeToFilter &&
          spaceToToggle == other.spaceToToggle &&
          typeToFilterAndToggle == other.typeToFilterAndToggle &&
          decimalSeparator == other.decimalSeparator;

  @override
  int get hashCode => Object.hashAll([
    tookIn,
    eta,
    moreTasks,
    confirmHint,
    confirmHintYes,
    confirmHintNo,
    yes,
    no,
    none,
    yesLabel,
    noLabel,
    answerYesOrNo,
    enterNumber,
    enterNumbers,
    answerNumber,
    answerNumbers,
    chooseAtLeast,
    chooseAtMost,
    typeToFilter,
    spaceToToggle,
    typeToFilterAndToggle,
    decimalSeparator,
  ]);
}

String _tookIn(String took) => ' in $took';
String _eta(String time) => 'ETA $time';
String _moreTasks(int count) => '+$count more';
String _answerNumber(int count) => 'answer a number from 1 to $count';
String _answerNumbers(int count) => 'answer numbers from 1 to $count';
String _chooseAtLeast(int min) => 'choose at least $min';
String _chooseAtMost(int max) => 'choose at most $max';

/// Gives the widgets below it the words [strings], as `Theme` gives them
/// a look: [TwkStrings.of] finds them. An app puts it at the top; a
/// console gets one from `Cli(strings:)`.
///
/// ```dart
/// Localizations(
///   strings: const TwkStrings(yes: 'ja', no: 'nein'),
///   child: app,
/// )
/// ```
final class Localizations extends InheritedWidget {
  /// Gives [child]'s subtree [strings].
  const Localizations({
    required this.strings,
    required super.child,
    super.key,
  });

  /// The words below.
  final TwkStrings strings;

  @override
  bool updateShouldNotify(Localizations oldWidget) =>
      strings != oldWidget.strings;
}
