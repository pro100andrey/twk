/// What a new document has after the one a [MarkdownView] parsed: the
/// check by which the view parses on rather than again.
library;

import 'markdown_view.dart' show MarkdownView;

/// The code units [appendedTo] has compared since the program started,
/// those its asserts compare left out: what a test reads to see how much
/// of a document a piece cost.
var comparedUnits = 0;

/// The text [data] has after [last], where it begins with [last]; null
/// where it does not.
///
/// [appended], where given, is said to be that text, as
/// [MarkdownView.appended] is: where [data] is as long as [last] and
/// [appended] together and ends with [appended], it is, and [last] is not
/// compared again, so that a piece costs its own length and not that of
/// the document. Otherwise, and where [appended] is null, the whole of
/// [last] is compared with the start of [data].
String? appendedTo(String last, String data, String? appended) {
  if (appended != null && data.length == last.length + appended.length) {
    comparedUnits += appended.length;
    if (data.endsWith(appended)) {
      assert(
        data.startsWith(last),
        'MarkdownView.appended is not all the data has after the data '
        'before: "$appended"',
      );
      return appended;
    }
  }
  if (data.length < last.length) {
    return null;
  }
  comparedUnits += last.length;
  return data.startsWith(last) ? data.substring(last.length) : null;
}
