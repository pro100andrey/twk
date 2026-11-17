import '../text/text.dart' show Text;

/// The string of [text]: its data, or its spans joined. The whole of it,
/// as the tree's description cuts it off.
String wholeText(Text text) =>
    text.data ?? [for (final s in text.spans!) s.text].join();
