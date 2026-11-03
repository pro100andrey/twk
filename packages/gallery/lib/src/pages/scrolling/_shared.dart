// What the pages of the group share.
part of 'scrolling.dart';

/// The box each page scrolls in: its width; its window two cells narrower.
const _boxW = 34;

/// The SingleChildScrollView's and the Scrollable's box: its rows.
const _scrollH = 8;

/// The Dart of a Box whose border is primary while the focus is in its
/// child, a FocusBuilder's, [pad] columns in; the child's line follows.
List<String> _focusBox(String pad) => [
  '$pad// the border primary while the focus is in it',
  '${pad}child: FocusBuilder(',
  '$pad  builder: (context, hasFocus, child) => Box(',
  '$pad    border: .all(',
  '$pad      type: .rounded,',
  '$pad      style: hasFocus ? theme.primary : theme.border,',
  '$pad    ),',
  '$pad    child: child,',
  '$pad  ),',
];

/// [child] in a rounded box [width] × [height], its border primary while
/// the focus is in it.
Widget _boxed(int width, int height, Widget child) => SizedBox(
  width: width,
  height: height,
  child: FocusBuilder(
    builder: (context, hasFocus, child) {
      final theme = Theme.of(context);
      return Box(
        border: Border.all(
          type: BorderType.rounded,
          style: hasFocus ? theme.primary : theme.border,
        ),
        child: child,
      );
    },
    child: child,
  ),
);

/// The line under a box: `offset 3 of 40`, as [controller] says it.
Widget _offsetLine(ScrollController controller) => ListenableBuilder(
  listenable: controller,
  builder: (context, _) {
    final theme = Theme.of(context);
    return Text.rich([
      Span('offset ', theme.muted),
      Span('${controller.offset}'),
      Span(' of ', theme.muted),
      Span('${controller.position.maxOffset}'),
    ]);
  },
);

/// The Code's lines of the line under a box, [controller]'s.
List<String> _offsetCode(String controller) => [
  '      ListenableBuilder(',
  '        listenable: $controller,',
  '        builder: (context, _) => Text.rich([',
  "          Span('offset ', theme.muted),",
  "          Span('\${$controller.offset}'),",
  "          Span(' of ', theme.muted),",
  "          Span('\${$controller.position.maxOffset}'),",
  '        ]),',
  '      ),',
];
