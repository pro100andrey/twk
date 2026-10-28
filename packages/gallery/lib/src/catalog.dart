// The groups and pages of the gallery, in the order of its list: each
// page's title and what it is about. A page that draws registers itself
// by its group and title (pages/pages.dart).

/// A group of the catalog: [title], where its widgets come from
/// ([source]), and its pages.
final class CatalogGroup {
  const CatalogGroup(this.title, this.source, this.pages);

  final String title;
  final String source;
  final List<CatalogPage> pages;
}

/// A page of the catalog: its [title] and what it is about.
final class CatalogPage {
  const CatalogPage(this.title, this.about);

  final String title;
  final String about;
}

/// The 20 groups of the catalog, the 141 pages in them.
const catalog = [
  CatalogGroup('Text', 'text.dart', [
    CatalogPage(
      'Text',
      'A paragraph in one style, its lines broken to fit, cut off and '
          'aligned as asked.',
    ),
    CatalogPage(
      'Rich text',
      'Spans in styles of their own: attributes, colors and links, '
          "'text'.bold.fg(…) for short.",
    ),
    CatalogPage(
      'DefaultTextStyle',
      'The style of the text below it, which a Text merges its own over.',
    ),
    CatalogPage(
      'Right to left',
      'Hebrew and Arabic among left-to-right text: put in the order it '
          'reads where the app reorders it (TextOrder.visual), left as stored '
          'where the terminal reorders it itself.',
    ),
  ]),
  CatalogGroup('Layout', 'layout.dart', [
    CatalogPage(
      'Box',
      'A border, titles on it, padding and a background around a child.',
    ),
    CatalogPage(
      'ColoredBox, DecoratedBox',
      "A child's cells filled with a color, and a BoxDecoration (a fill, a "
          'border, titles) drawn under the child or over its edges.',
    ),
    CatalogPage(
      'Container',
      'Align, Padding, a color or a decoration, a size and a margin put '
          "together around one child, as Flutter's Container puts them.",
    ),
    CatalogPage(
      'Divider',
      'A line across, and a VerticalDivider down; merged, they join the '
          'lines drawn before them where they meet.',
    ),
    CatalogPage(
      'Shadow',
      'A drop shadow: the cells beside and below a child, moved by its '
          'offset, what is under them darkened.',
    ),
    CatalogPage(
      'Padding',
      'Empty cells around a child.',
    ),
    CatalogPage(
      'Align, Center',
      'A child placed in the room it is given; Center in the middle of it.',
    ),
    CatalogPage(
      'SizedBox',
      'A child of a size: SizedBox.expand fills the room, SizedBox.shrink '
          'takes none.',
    ),
    CatalogPage(
      'ConstrainedBox',
      'Constraints a child is laid out within, merged with those it is '
          'given.',
    ),
    CatalogPage(
      'LimitedBox, OverflowBox',
      'Other constraints than the room gives: LimitedBox limits a child only '
          'where the room has no limit, OverflowBox and SizedOverflowBox give '
          'it others in its place, cut off where it sticks out.',
    ),
    CatalogPage(
      'FractionallySizedBox',
      'A child a fraction of the room it is given.',
    ),
    CatalogPage(
      'IntrinsicWidth/Height',
      'A child as wide or as tall as it would like to be: stretched items '
          'all as wide as the widest, boxes all as tall as the tallest.',
    ),
    CatalogPage(
      'Row, Column, Flex',
      'Children one after another along an axis, aligned along and across '
          'it.',
    ),
    CatalogPage(
      'Expanded, Spacer',
      'Children of a Row or Column that share the room the others leave '
          'by their flex factors: Expanded fills its share, a Flexible may '
          'take less, a Spacer is empty.',
    ),
    CatalogPage(
      'Stack, Positioned',
      'Children over one another, pinned to the edges or aligned.',
    ),
    CatalogPage(
      'Transform',
      'A child shown moved by whole cells, laid out where it was: '
          'Transform.translate, the one transform a terminal has.',
    ),
    CatalogPage(
      'Visibility, Offstage',
      'A child hidden: Offstage keeps it laid out and running without '
          'painting it; Visibility takes its room away too, or keeps it.',
    ),
    CatalogPage(
      'ExpansionTile, Accordion',
      'Sections that fold under their headers: Enter, Space or a click '
          'opens one, Right and Left open and close it; in an accordion one '
          'is open at a time, Up and Down go from header to header.',
    ),
    CatalogPage(
      'Grid, GridPlacement',
      'Children in the cells of tracks: fixed, a share of the rest, or as '
          'long as their content; a child may span several.',
    ),
    CatalogPage(
      'Wrap',
      'Children in runs that go on in the next run where they would not '
          'fit: tags, buttons and key hints on a terminal that narrows.',
    ),
    CatalogPage(
      'CustomPaint',
      'Cells a CellPainter draws itself, under the child or over it, painted '
          'again when what it paints changes.',
    ),
    CatalogPage(
      'SplitView',
      'Panes the mouse or the arrows resize by their dividers; Tab '
          'focuses one. The last one collapses.',
    ),
    CatalogPage(
      'DockArea',
      'Panels in splits and tabs: a tab dragged onto a target of a group '
          "docks its panel there, and dropped elsewhere floats it; a window's "
          'title bar dragged onto one docks it again.',
    ),
    CatalogPage(
      'Scaffold',
      "An app's frame: a header, a sidebar beside the body, a status bar and "
          'the key hints, each part a zone of the focus; the sidebar '
          'collapsed on a narrow screen and resized by a drag.',
    ),
  ]),
  CatalogGroup('Style', 'style.dart', [
    CatalogPage(
      'Theme',
      'The styles of an app by what they are for, which the widgets below '
          "it draw in: a preset, or the terminal's own colors.",
    ),
    CatalogPage(
      'TerminalBrightness',
      'Whether the terminal is dark or light, as it reports it; '
          'Theme.adaptive picks a dark or a light theme by it.',
    ),
    CatalogPage(
      'GradientBackground',
      'A background whose color changes from cell to cell, along the '
          'columns or down the rows, from stop to stop.',
    ),
    CatalogPage(
      'GradientForeground',
      'Text whose color changes from glyph to glyph along each line, or '
          'from line to line down the rows.',
    ),
  ]),
  CatalogGroup('Scrolling', 'scroll.dart', [
    CatalogPage(
      'SingleChildScrollView',
      'One child scrolled in the room it is given: Tab to it, then the '
          'arrows, PageUp and PageDown, or the wheel over it.',
    ),
    CatalogPage(
      'Scrollable',
      "What scrolls a viewport: here one of the page's own, a ruler that "
          'tells the scrollable how long it is as it is laid out.',
    ),
    CatalogPage(
      'ListView',
      'Items built as they come into view, however many there are; the wheel '
          'and the keys scroll it. Separated, reversed as a chat, or kept on '
          'what it shows as items come before it.',
    ),
    CatalogPage(
      'LogView',
      'Lines that keep coming, followed at the bottom: levels, a filter and a '
          'search, a count of the new lines while it is scrolled up.',
    ),
    CatalogPage(
      'Scrollbar',
      'A bar by the scrollable below it, its thumb where the window is; '
          'the thumb dragged and the track clicked scroll it.',
    ),
  ]),
  CatalogGroup('Data', 'data.dart', [
    CatalogPage(
      'Sparkline',
      'A series of values as bars an eighth of a cell fine, the newest on '
          'the right.',
    ),
    CatalogPage(
      'Gauge, LineGauge',
      'How much of something there is: a block filled to a ratio, or a '
          'line.',
    ),
    CatalogPage(
      'BarChart',
      'Bars in groups, up or across, their values on them and their '
          'labels under them.',
    ),
    CatalogPage(
      'Chart',
      'Datasets of points on two axes, as lines or dots, with a legend.',
    ),
    CatalogPage(
      'DotCanvas',
      'Shapes drawn finer than the cells, in data coordinates, with '
          'labels over them.',
    ),
    CatalogPage(
      'Calendar',
      'A month to pick a day of: the arrows move the cursor, PageUp and '
          'PageDown a month, Enter or a click picks the day.',
    ),
    CatalogPage(
      'Heatmap, ActivityHeatmap',
      'Values over a grid as shades or colors, its rows and columns '
          'labelled; counts by day over weeks, a column a week. The arrows '
          'move a cursor, its tooltip saying what is there.',
    ),
    CatalogPage(
      'Table',
      'Rows in columns that size by their content or a share, sorted by a '
          'click on a title; the arrows select a row or a cell.',
    ),
    CatalogPage(
      'DescriptionList',
      'Terms and their values, the values in a column of their own, '
          'aligned group by group; a long value wraps under itself, and on '
          'a narrow screen each goes under its term.',
    ),
    CatalogPage(
      'TreeView',
      'Nodes under their parents: the arrows move and expand, Enter or a '
          'click on the expander opens one; test/ loads a while.',
    ),
    CatalogPage(
      'TreeTable',
      'A tree in the first column of a table: rows that expand and collapse, '
          'sorted within their parents, selected one or many at a time.',
    ),
    CatalogPage(
      'DirectoryTree',
      'The files under a directory as a tree for a side panel: each '
          'directory listed as it is opened and again as it changes, what '
          '.gitignore ignores left out.',
    ),
    CatalogPage(
      'TaskList',
      'Tasks and how far they have got: pending, running with a spinner '
          'and the time it has run, done, failed or skipped; their steps '
          'below.',
    ),
  ]),
  CatalogGroup('Editing', 'editing.dart', [
    CatalogPage(
      'TextField',
      'A line of text to edit: Tab to it and type; Enter submits it, '
          'Ctrl+Z undoes.',
    ),
    CatalogPage(
      'InputDecoration',
      'What is drawn around a field: a label, an icon, a prefix and a '
          'suffix, a helper, an error and a counter, in a box, over a line '
          'or bare, filled.',
    ),
    CatalogPage(
      'TextArea',
      'Lines of text to edit, wrapped to the width: Enter breaks a line, '
          'the area grows from its least lines to its most, then scrolls.',
    ),
    CatalogPage(
      'Autocomplete',
      'Suggestions under a field as one types, after a trigger or for the '
          'whole text: Up and Down pick one, Enter or Tab puts it in.',
    ),
  ]),
  CatalogGroup('Controls', 'controls.dart', [
    CatalogPage(
      'Button',
      'A label pressed by a click, or by Enter or Space while it has the '
          'focus; disabled with no onPressed.',
    ),
    CatalogPage(
      'Pressable',
      'What the controls are built of: a node of the focus tree that Tab '
          'passes by while it is disabled, the keys it takes while it has the '
          'focus, a press that focuses it and a tap; it builds its look by '
          'whether it has the focus.',
    ),
    CatalogPage(
      'Checkbox, Switch',
      'What is on or off: a click, or Space or Enter, flips it.',
    ),
    CatalogPage(
      'RadioGroup',
      'One of several choices: the arrows or a click choose one.',
    ),
    CatalogPage(
      'SegmentedButton',
      'A few values joined in one row, one on at a time or any of them: '
          'the arrows, a digit or a click turn one on.',
    ),
    CatalogPage(
      'SelectionList',
      'Items selected by their keys: in a single selection the cursor '
          'selects, in a multiple one Space does.',
    ),
    CatalogPage(
      'Select, MultiSelect',
      'A field that opens its choices to pick one, or several, from, or a '
          'PopupController from the app; typing filters them.',
    ),
    CatalogPage(
      'ConfirmInput',
      'A question answered by y, n or Enter.',
    ),
    CatalogPage(
      'Slider',
      'A value along a track: the arrows, a press or a drag move the '
          'thumb, which stands in eighths of a cell.',
    ),
    CatalogPage(
      'NumberInput',
      'A number typed, or stepped by Up and Down, the wheel or a click on '
          '▴▾; kept within its bounds.',
    ),
    CatalogPage(
      'DatePicker',
      'A date typed, stepped by Up and Down, or picked from the calendar '
          'that Alt+Down, a click on ▾ or a PopupController opens.',
    ),
    CatalogPage(
      'FilePicker',
      'A file picked from the directory listed under a field that names '
          'its path: the arrows and Enter go through it, Tab completes a '
          'name; a FilePickerController goes to a directory.',
    ),
    CatalogPage(
      'Form, FormField',
      'Fields validated and submitted together: Enter goes on to the next '
          'field, and from the last submits the form.',
    ),
    CatalogPage(
      'TabBar, TabView',
      'Tabs to pick a view by: Left and Right, or a click.',
    ),
    CatalogPage(
      'KeyHintsBar',
      'The keys that can be pressed now, with their hints, as the focus '
          'moves: Tab to the field to see its keys.',
    ),
    CatalogPage(
      'StatusMessage, Badge',
      'A message of a kind after its icon, in its color; a short label on '
          'its color.',
    ),
    CatalogPage(
      'Callout',
      'A notice in a box lined in the color of its kind, its title on '
          'the top edge; [×] or Escape dismisses it, and buttons below act '
          'on it.',
    ),
    CatalogPage(
      'Link',
      'Text linked to a URL, which a terminal that knows hyperlinks opens.',
    ),
    CatalogPage(
      'ListTile',
      'A row of a list: a title over a subtitle, something before and after '
          'them; tapped by a click or Enter, lit while focused or under '
          'the mouse.',
    ),
    CatalogPage(
      'StatusBar',
      'A row of three sections, left, centre and right; those that do not '
          'fit give way, the centre first.',
    ),
  ]),
  CatalogGroup('Overlays', 'overlay.dart', [
    CatalogPage(
      'Overlay',
      'A layer over the app that dialogs, toasts, menus and tooltips go '
          'in; an entry of its own goes in it too.',
    ),
    CatalogPage(
      'Dialog',
      'A box over the app, the rest dimmed behind a barrier; Tab stays in '
          'it, Escape closes it.',
    ),
    CatalogPage(
      'Toast',
      'A message that shows for a while and goes, over a corner of the '
          'app.',
    ),
    CatalogPage(
      'Tooltip',
      'A message by a widget while the mouse or the keyboard focus rests '
          'on it, or while the app shows it.',
    ),
    CatalogPage(
      'Popover',
      'A widget by another while the app says so; Escape or a click '
          'outside closes it.',
    ),
    CatalogPage(
      'MenuBar',
      'Menus in a bar: F10 or a click opens one, Alt and a mnemonic too, '
          'or a MenuController from the app; the arrows, Enter and the '
          'mnemonics choose.',
    ),
    CatalogPage(
      'ContextMenu',
      'A menu at the mouse on a right click, under the focus on '
          'Shift+F10, or where a MenuController opens it.',
    ),
    CatalogPage(
      'CommandPalette',
      'What can be done, found by typing: Ctrl+K on a button, or a '
          'CommandPaletteController opening it with a query; commandsFor '
          "adds more. The gallery's own, Ctrl+P, goes to a page.",
    ),
    CatalogPage(
      'OptionList',
      'Options in rows, one highlighted, the characters a query matched '
          'standing out and a detail at the right edge: what an autocomplete, '
          'a Select and a command palette list.',
    ),
    CatalogPage(
      'ModalBarrier',
      'What dims the app under a dialog and keeps the mouse from it.',
    ),
    CatalogPage(
      'WindowLayer',
      'Windows over the app: a title bar drags one, an edge resizes it, '
          'its buttons minimise, maximise and close it; Tab to a title bar, '
          'then the arrows move it.',
    ),
  ]),
  CatalogGroup('Animation', 'animation.dart', [
    CatalogPage(
      'Spinner',
      'Frames shown in turn while something goes on; spinners of the same '
          'frames step together.',
    ),
    CatalogPage(
      'ProgressBar',
      'A bar filled as far as its value, in eighths of a cell; a block '
          'going to and fro while the value is not known.',
    ),
    CatalogPage(
      'ProgressList',
      'Many tasks at once, a row each: its mark, a bar, how much is '
          'done, its rate and the time it has left, from a ProgressTracker '
          'the work counts on.',
    ),
    CatalogPage(
      'Skeleton, Skeletonize',
      'Placeholders while content loads: blocks where it will be, or a '
          'subtree drawn as blocks in the layout it has, a shimmer sweeping '
          'over them as a SkeletonTheme says.',
    ),
    CatalogPage(
      'AnimationController',
      "An animation of the page's own: a controller from 0 to 1 and back, "
          'a frame at a time, through a curve and a tween.',
    ),
    CatalogPage(
      'AnimatedBuilder',
      'A builder run again at each tick of an animation, the part that does '
          'not change built once and passed in as its child.',
    ),
    CatalogPage(
      'AnimatedAlign, AnimatedPadding',
      'A child that runs to the place its alignment or its padding gives '
          'it, a cell at a time.',
    ),
    CatalogPage(
      'AnimatedPositioned',
      'A child pinned in a stack that runs to the edges it is pinned to.',
    ),
    CatalogPage(
      'AnimatedBox',
      'A box whose size, padding, background and border colors run to the '
          'new ones; a border of another type switches halfway.',
    ),
    CatalogPage(
      'AnimatedOpacity, Opacity',
      'A child shown at an opacity, mixed cell by cell with what is under '
          'it; the one on the left runs to the opacity chosen.',
    ),
    CatalogPage(
      'AnimatedDefaultTextStyle',
      'The style of the text below it, its colors running to the new ones.',
    ),
    CatalogPage(
      'AnimatedSize',
      'As big as its child, running to the new size when the child grows '
          'or shrinks.',
    ),
    CatalogPage(
      'TweenAnimationBuilder',
      'Builds with a value that runs to the one it is given, through the '
          'tweens it makes.',
    ),
    CatalogPage(
      'AnimatedSwitcher',
      'A child that gives way to another as the transition shows them: '
          'faded, slid or dissolved.',
    ),
    CatalogPage(
      'Dissolve, FractionalTranslation',
      'What the transitions are made of: a share of the cells of a child, '
          'and a child moved a share of its size.',
    ),
    CatalogPage(
      'Effect',
      "A child shown through an effect over its cells, run on the app's "
          'clock: recolored, swept, dissolved, typed or glitched in, while '
          'the child repaints underneath.',
    ),
  ]),
  CatalogGroup('Mouse', 'gestures.dart', [
    CatalogPage(
      'GestureDetector',
      'Taps, double taps, long presses and drags of the mouse over a '
          'widget.',
    ),
    CatalogPage(
      'Listener, MouseRegion',
      'The mouse events over a widget as they come: presses, releases, '
          'motion and the wheel; the mouse coming in and going out, the '
          'pointer a hand over it where the terminal shows that.',
    ),
    CatalogPage(
      'IgnorePointer, AbsorbPointer',
      'A subtree the mouse passes by: IgnorePointer lets it through to what '
          'is under it, AbsorbPointer stops it there.',
    ),
    CatalogPage(
      'SelectionArea',
      'Text selected with the mouse as in a terminal, and copied to the '
          'clipboard: drag over it, or click twice or three times; a painted '
          'Selectable is selected in too, and a drag past its edge scrolls '
          'it.',
    ),
    CatalogPage(
      'Draggable, DragTarget',
      'Data dragged from a widget with the mouse and dropped on another '
          'that accepts it.',
    ),
  ]),
  CatalogGroup('Focus and keys', 'focus.dart', [
    CatalogPage(
      'Focus, FocusScope',
      'Nodes the keys go to: Tab moves the focus from one to the next, a '
          'click takes it; in a scope Tab stays, Escape leaves.',
    ),
    CatalogPage(
      'ExcludeFocus',
      'A subtree Tab passes by: its nodes take no focus while it excludes '
          'them, and give it up when it starts to.',
    ),
    CatalogPage(
      'KeyBindings, LeaderKey',
      'Keys and sequences bound to callbacks while the focus is below '
          'them: Tab to the box, then +, -, g g or the leader , and r.',
    ),
    CatalogPage(
      'Shortcuts, Actions',
      'Keys bound to intents, which the nearest action for them does: Tab '
          'to the box, then Up or Down; a key whose action is off passes on.',
    ),
  ]),
  CatalogGroup('Navigation', 'navigation.dart', [
    CatalogPage(
      'Navigator',
      'Screens on a stack: a route pushed covers the one under it and '
          'takes the focus, Escape or Back pops it.',
    ),
    CatalogPage(
      'PopScope, NavigatorObserver',
      'A route that asks before it is popped, by Escape or by the back key, a '
          'dialog too; and an observer told of every push, pop and removal.',
    ),
    CatalogPage(
      'Breadcrumbs',
      'Where a screen is in a hierarchy, each level a link up: the '
          'arrows and Enter or a click go to one, and the middle collapses '
          'into … where the row does not fit.',
    ),
    CatalogPage(
      'Pagination',
      'The pages of a long list on one row, the current one among its '
          'siblings: the arrows, PageUp and PageDown, a page number typed '
          'or a click go to another.',
    ),
    CatalogPage(
      'Stepper',
      'A wizard of steps under their headers, each left forward once '
          'its validation takes it: Next or PageDown validates, Back or '
          'PageUp goes back, a header clicked goes to it.',
    ),
  ]),
  CatalogGroup('Foundation', 'foundation.dart', [
    CatalogPage(
      'ListenableBuilder',
      'What is built again each time a listenable notifies; '
          'ValueListenableBuilder is given its value.',
    ),
    CatalogPage(
      'FutureBuilder, StreamBuilder',
      'What is built from the latest snapshot of a future or a stream: '
          'waiting, done, or each event.',
    ),
  ]),
  CatalogGroup('Framework', 'framework.dart', [
    CatalogPage(
      'LayoutBuilder',
      'What is built by the constraints it is laid out within: side by '
          'side when wide, one under another when narrow.',
    ),
    CatalogPage(
      'NotificationListener',
      'The notifications that bubble up to it from below, such as those '
          'of a list as it scrolls: the wheel over it, or Tab to it and the '
          'arrows.',
    ),
    CatalogPage(
      'Slot, SlotScope',
      'Places the app names that plugins fill with the entries of a '
          'SlotRegistry: Tab to a plugin, then Space puts its entry in the '
          'status bar or takes it out.',
    ),
  ]),
  CatalogGroup('App', 'binding.dart', [
    CatalogPage(
      'InputListener',
      'The input no widget took: keys nothing is bound to, the mouse '
          'where no Listener is, pastes, focus and resizes.',
    ),
    CatalogPage(
      'ErrorWidget',
      'An error shown in place of what failed to build, as the app does '
          'by itself.',
    ),
    CatalogPage(
      'Static',
      'Output that is finished once shown: in place here; in the inline '
          "mode above the app, in the terminal's history.",
    ),
    CatalogPage(
      'TerminalProgress',
      "The program's progress in the terminal's tab or taskbar, where the "
          'terminal shows one (Ghostty, kitty, Windows Terminal, ConEmu).',
    ),
    CatalogPage(
      'Viewport',
      'The app in a fixed rectangle of the screen (Viewport.fixed): '
          'nothing outside it is written, so what the terminal showed around '
          'it stays.',
    ),
    CatalogPage(
      'Window title',
      "The title of the terminal's window or tab while the app runs; the "
          "user's own comes back when it ends.",
    ),
    CatalogPage(
      'Notifications',
      'A desktop notification of a title and a body, where the terminal '
          'shows one (OSC 9, 777 or 99); nothing where it does not.',
    ),
    CatalogPage(
      'Cli',
      "A command-line tool's console (twk_cli) as it runs: questions that "
          'leave their answer as a line, a spinner, tasks with bars, a '
          'traceback.',
    ),
  ]),
  CatalogGroup('Screen readers', 'semantics.dart', [
    CatalogPage(
      'Semantics',
      'What a widget is to a screen reader: a role, a label, a value and '
          'a state, read as a line of text. TWK_SCREEN_READER=1 reads an app '
          'out so.',
    ),
  ]),
  CatalogGroup('Debugging', 'debug.dart', [
    CatalogPage(
      'Console',
      'Log records listed over the app, newest last; the app has one of '
          'its own, which Ctrl+G then c opens.',
    ),
    CatalogPage(
      'FrameOverlay',
      "Each frame's numbers over the app: the time its build, layout, "
          'paint and write took and the bytes it wrote; Ctrl+G then o.',
    ),
    CatalogPage(
      'Repaint rainbow',
      'Each repaint boundary tinted a new colour when it paints, and '
          'relayouts marked, to see what a change redraws; Ctrl+G then r, and '
          'l.',
    ),
    CatalogPage(
      'RepaintBoundary',
      'A subtree painted on its own layer: what changes in it is painted '
          'again without what is around it, and the other way round.',
    ),
  ]),
  CatalogGroup('Rich', 'packages/twk_rich', [
    CatalogPage(
      'MarkdownView',
      'A Markdown document as widgets, a blank row between the blocks; '
          "its links the app's with onLinkTap, a MarkdownController "
          'scrolling to a heading.',
    ),
    CatalogPage(
      'CodeView',
      'Source code highlighted for its language, with line numbers, its '
          'long lines wrapped or cut off at the width; a CodeViewController '
          'scrolls it to a line, highlights lines and finds text.',
    ),
    CatalogPage(
      'SyntaxThemeScope',
      'The styles of the code below it, a style for each kind of token, in '
          'place of those derived from the theme: a SyntaxTheme of its own, or '
          'the derived one with a few changed.',
    ),
    CatalogPage(
      'DiffView',
      'The changes between two texts, unified or side by side, the words '
          'that changed marked and both sides highlighted.',
    ),
    CatalogPage(
      'JsonView',
      'JSON or a Dart value as a tree that folds, each kind of value in '
          'its color: c copies the path of the value selected, y the value, '
          '/ filters the keys.',
    ),
    CatalogPage(
      'BigText',
      'Text in letters several cells tall, drawn with full or half blocks '
          'or with box drawing, in a font of its own.',
    ),
    CatalogPage(
      'QrCode',
      "Text as a QR code a phone's camera reads: in half blocks, two modules "
          'to a cell, black on white whatever the theme, with as much of the '
          'quiet zone around it as the rows allow.',
    ),
    CatalogPage(
      'ANSI',
      'Output with ANSI colour codes, from a program or a log, as styled '
          'spans: all at once with parseAnsi, or as it streams in with '
          'AnsiStream.',
    ),
  ]),
  CatalogGroup('Images', 'packages/twk_rich', [
    CatalogPage(
      'Image',
      "A PNG or JPEG fitted to its cells: placed with the terminal's "
          'graphics protocol (kitty, sixel, iTerm2), or drawn in half blocks '
          'or quadrants where it has none.',
    ),
  ]),
  CatalogGroup('Terminal', 'packages/twk_term', [
    CatalogPage(
      'TerminalView',
      'A program running in a pseudo-terminal, its screen drawn in the '
          'view: keys, pastes, the mouse and resizes go to it, and its '
          'scrollback scrolls.',
    ),
  ]),
];
