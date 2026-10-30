/// Text widgets: [Text] and [Text.rich], drawn in their styles merged onto
/// that of the [DefaultTextStyle] above them.
library;

import 'package:twk_core/twk_core.dart'
    show
        ClusterScan,
        Pen,
        RenderParagraph,
        TextAlign,
        TextOverflow,
        TextSegmenter,
        TextWrap;

import '../framework/framework.dart';
import '../gestures/mouse.dart'
    show PointerEvent, RenderListener, listenOver, stopListeningOver;
import '../gestures/selection.dart'
    show SelectionArea, addToSelectionArea, selectedInSelectionArea;
import '../style/gradient.dart' show textColorsAlong;
import '../style/style.dart';

// Examples can assume:
// late String notes;

export 'package:twk_core/twk_core.dart' show TextAlign, TextOverflow, TextWrap;

/// Text in [style] merged onto the [DefaultTextStyle] above it: a string
/// ([data]), or [spans], each in its own style merged onto that one
/// ([Text.rich]), a span with a gradient ([Span.gradient]) in its colors
/// grapheme by grapheme, laid out as it would be without. Its lines are
/// broken as [wrap] says, at most [maxLines] of them, each placed as
/// [align] says; where text is cut off, [overflow] says how it shows. It
/// is as wide as its widest line and as tall as its lines, within its
/// constraints. See [RenderParagraph]. Below a [SelectionArea] it can be
/// selected with the mouse, what is selected drawn in the area's style
/// merged onto its own. A click on text that links ([Style.link]) is told
/// to [onLinkTap].
///
/// A title in bold, then a description of two lines at most, cut off with
/// `…`:
///
/// ```dart
/// Column(
///   children: [
///     const Text('Release notes', style: Style(attrs: Attr.bold)),
///     Text(notes, maxLines: 2, overflow: TextOverflow.ellipsis),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [Span] and [StringStyles], the styled pieces of a [Text.rich].
///  * [DefaultTextStyle], the style the text is merged onto.
final class Text extends LeafRenderObjectWidget {
  /// Shows [data] in [style]; the text breaks at words ([wrap]), is clipped
  /// ([overflow]), shows as many lines as it has ([maxLines]) and is
  /// aligned left ([align]) unless told otherwise.
  const Text(
    String this.data, {
    super.key,
    this.style = const Style(),
    this.wrap = TextWrap.word,
    this.overflow = TextOverflow.clip,
    this.maxLines,
    this.align = TextAlign.left,
    this.onLinkTap,
  }) : spans = null;

  /// Shows [spans], each in its style merged onto [style], as one
  /// paragraph: a line breaks between spans as it does inside one.
  ///
  /// ```dart
  /// Text.rich(['Error: '.bold.fg(Color.red), const Span('not found')])
  /// ```
  const Text.rich(
    List<Span> this.spans, {
    super.key,
    this.style = const Style(),
    this.wrap = TextWrap.word,
    this.overflow = TextOverflow.clip,
    this.maxLines,
    this.align = TextAlign.left,
    this.onLinkTap,
  }) : data = null;

  /// The text, in [style]; null for [spans].
  final String? data;

  /// The text in spans, each in its style merged onto [style]; null for
  /// [data].
  final List<Span>? spans;

  /// Merged onto the style of the [DefaultTextStyle] above.
  final Style style;

  /// Where lines break when the text is wider than its room: at words
  /// ([TextWrap.word], the default), between any graphemes, or nowhere.
  final TextWrap wrap;

  /// How text that does not fit shows where it is cut off: clipped
  /// ([TextOverflow.clip], the default), or with `…` in place of its end,
  /// start or middle.
  final TextOverflow overflow;

  /// The most lines it shows; null for any number.
  final int? maxLines;

  /// Where each line is placed in the width of the text: on the left
  /// ([TextAlign.left], the default), in the middle, on the right, or
  /// stretched to the whole width.
  final TextAlign align;

  /// Told the link ([Style.link]) of the text clicked on: the left button
  /// pressed and released on the same cell, of a cluster whose style
  /// links it; a click beside the text, on text that links nowhere, or
  /// with another button tells it nothing. Null, the default, for none.
  /// The text is written as a hyperlink still, which a terminal that knows
  /// them (OSC 8) may open itself as well. While it is set the terminal
  /// reports the mouse's buttons.
  ///
  /// ```dart
  /// Text.rich(
  ///   [const Span('see '), 'the docs'.link('https://dart.dev').underline],
  ///   onLinkTap: (url) => print('open $url'),
  /// )
  /// ```
  final void Function(String url)? onLinkTap;

  @override
  RenderParagraph createRenderObject(BuildContext context) {
    final paragraph = RenderParagraph(
      _spansIn(context, null),
      wrap: wrap,
      overflow: overflow,
      maxLines: maxLines,
      align: align,
    );
    addToSelectionArea(context, paragraph);
    _tellTaps(context, paragraph);
    return paragraph;
  }

  @override
  void updateRenderObject(BuildContext context, RenderParagraph renderObject) {
    renderObject
      ..spans = _spansIn(context, renderObject)
      ..wrap = wrap
      ..overflow = overflow
      ..maxLines = maxLines
      ..align = align;
    _tellTaps(context, renderObject);
  }

  @override
  void didUnmountRenderObject(RenderParagraph renderObject) {
    if (_linkTaps[renderObject] != null) {
      _linkTaps[renderObject] = null;
      stopListeningOver(renderObject);
    }
  }

  /// Gives the clicks on [paragraph] to [onLinkTap], or none when it is
  /// null.
  void _tellTaps(BuildContext context, RenderParagraph paragraph) {
    final onLinkTap = this.onLinkTap;
    final taps = _linkTaps[paragraph];
    if (onLinkTap == null) {
      if (taps != null) {
        _linkTaps[paragraph] = null;
        stopListeningOver(paragraph);
      }
    } else if (taps != null) {
      taps.onLinkTap = onLinkTap;
    } else {
      final taps = _linkTaps[paragraph] = _LinkTaps(paragraph, onLinkTap);
      listenOver(context, paragraph, taps.listener);
    }
  }

  /// The text as (text, pen), in the styles merged onto that of the
  /// [DefaultTextStyle] at [context]; the part of [paragraph] a
  /// [SelectionArea] selected in its style merged onto those.
  List<(String, Pen)> _spansIn(
    BuildContext context,
    RenderParagraph? paragraph,
  ) {
    final style = DefaultTextStyle.of(context).merge(this.style);
    final selected = paragraph == null
        ? null
        : selectedInSelectionArea(context, paragraph);
    if (spans == null && selected == null) {
      // the common case, rebuilt in every frame of a clock or a counter:
      // one span, without the lists below
      return [(data!, style.pen)];
    }
    final styled = [
      if (spans case final spans?)
        for (final s in spans)
          if (s.gradient case final gradient?)
            ..._graded(s.text, style.merge(s.style), gradient, context)
          else
            (s.text, style.merge(s.style))
      else
        (data!, style),
    ];
    if (selected == null) {
      return [for (final (text, style) in styled) (text, style.pen)];
    }
    // each span split where the selection starts and ends
    final (start, end, selection) = selected;
    final out = <(String, Pen)>[];
    var at = 0;
    for (final (text, style) in styled) {
      final s = (start - at).clamp(0, text.length);
      final e = (end - at).clamp(s, text.length);
      if (s > 0) {
        out.add((text.substring(0, s), style.pen));
      }
      if (e > s) {
        out.add((text.substring(s, e), style.merge(selection).pen));
      }
      if (e < text.length || text.isEmpty) {
        out.add((text.substring(e), style.pen));
      }
      at += text.length;
    }
    return out;
  }
}

// the clicks each paragraph of a Text with an onLinkTap tells it
final _linkTaps = Expando<_LinkTaps>('Text.onLinkTap');

/// What tells [onLinkTap] the links clicked on in [paragraph]: the
/// [listener] of its presses and releases.
final class _LinkTaps {
  _LinkTaps(this.paragraph, this.onLinkTap);

  final RenderParagraph paragraph;
  void Function(String url) onLinkTap;

  late final listener = RenderListener(onDown: _down, onUp: _up);

  /// The cell the left button was pressed on, while it is held.
  (int, int)? _pressed;

  void _down(PointerEvent event) =>
      _pressed = event.button == 0 ? (event.x, event.y) : null;

  void _up(PointerEvent event) {
    final pressed = _pressed;
    _pressed = null;
    if (event.button != 0 || pressed != (event.x, event.y)) {
      return;
    }
    if (_linkAt(event.x, event.y) case final url?) {
      onLinkTap(url);
    }
  }

  /// The link of the cluster at [x], [y] of [paragraph], as its last
  /// layout placed it; null beside its text, or where that links nowhere.
  String? _linkAt(int x, int y) {
    final (start, end) = paragraph.textRangeAt(x, y);
    if (start == end) {
      return null;
    }
    var at = 0;
    for (final (text, pen) in paragraph.spans) {
      at += text.length;
      if (start < at) {
        return pen.link;
      }
    }
    return null;
  }
}

final _graphemes = TextSegmenter();
final _scan = ClusterScan();

/// [text] in [style] cut before each grapheme after the first that takes a
/// cell, each piece in the text color of its grapheme along [gradient], as
/// the app [context] is in mixes it (`textColorsAlong`): a
/// span of the paragraph each, broken into lines as the text is whole,
/// since a line breaks between spans as it does inside one.
List<(String, Style)> _graded(
  String text,
  Style style,
  Gradient gradient,
  BuildContext context,
) {
  final cuts = <int>[];
  var graphemes = 0;
  for (var i = 0; i < text.length;) {
    final start = i;
    _graphemes.scan(text, i, _scan);
    i = _scan.end;
    if ((_scan.width > 0 || _scan.first == 0x09) && graphemes++ > 0) {
      cuts.add(start);
    }
  }
  if (graphemes == 0) {
    return [(text, style)];
  }
  final colors = textColorsAlong(gradient, graphemes, context);
  return [
    for (var k = 0; k < graphemes; k++)
      (
        text.substring(
          k == 0 ? 0 : cuts[k - 1],
          k == cuts.length ? text.length : cuts[k],
        ),
        style.merge(Style(fg: colors[k].$1, fgAlpha: colors[k].$2)),
      ),
  ];
}

/// The style the [Text]s below it are drawn in under their own: [style]
/// merged onto that of the [DefaultTextStyle] above it.
///
/// A panel whose text is dim unless a [Text] says otherwise:
///
/// ```dart
/// DefaultTextStyle(
///   style: const Style(attrs: Attr.dim),
///   child: Column(
///     children: [
///       const Text('dim'),
///       const Text('bright', style: Style(attrsOff: Attr.dim)),
///     ],
///   ),
/// )
/// ```
final class DefaultTextStyle extends StatelessWidget {
  /// Gives the [Text]s in [child]'s subtree [style], merged onto the one
  /// above.
  const DefaultTextStyle({required this.style, required this.child, super.key});

  /// What the text below takes where its own style leaves a field unset.
  final Style style;

  /// The widgets whose text takes [style].
  final Widget child;

  /// The style the [Text]s at [context] are drawn in under their own: that
  /// of the nearest [DefaultTextStyle], merged onto those above it; an
  /// empty style without one. [context] depends on it, as on an
  /// [InheritedWidget].
  static Style of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TextStyleScope>()?.style ??
      const Style();

  @override
  Widget build(BuildContext context) =>
      _TextStyleScope(style: of(context).merge(style), child: child);
}

/// What [DefaultTextStyle.of] finds: the style merged onto those above.
final class _TextStyleScope extends InheritedWidget {
  const _TextStyleScope({required this.style, required super.child});

  final Style style;

  @override
  bool updateShouldNotify(_TextStyleScope oldWidget) =>
      style != oldWidget.style;
}
