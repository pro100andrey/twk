// How big the gallery's parts are and how long its motions take
// (doc/design.md, "Layout"): the numbers the shell's layout, paint and
// keys share, by name.
import '../page.dart';

/// The page's margin at the left, on a page [padWideFrom] columns wide or
/// more; [pagePadNarrow] on a narrower one.
const pagePad = 3;

/// See [pagePad].
const pagePadNarrow = 2;

/// See [pagePad].
const padWideFrom = 70;

/// The sidebar's width on a screen [cols] wide.
int sidebarWidth(int cols) => cols >= 150
    ? 32
    : cols >= 110
    ? 28
    : cols >= 96
    ? 26
    : 22;

/// The inspector's width on a screen [cols] wide.
int inspectorWidth(int cols) => cols >= 150 ? 34 : 30;

/// A page this wide or more has the inspector beside the stage, where
/// that leaves the widget the columns it needs.
const inspectorBesideFrom = 76;

/// A screen lower than this has the tabs on the title's row.
const lowScreenBelow = 30;

/// A header this wide or more says where the page is: group › page.
const headerWhereFrom = 96;

/// The columns the stage's marks take around its widget, both sides
/// together, and the rows.
const stageMarksWidth = 6;

/// See [stageMarksWidth].
const stageMarksHeight = 2;

/// The room a stage of [width] × [height] gives its widget: less its marks.
StageRoom stageRoomIn(int width, int height) => StageRoom(
  width - stageMarksWidth < 0 ? 0 : width - stageMarksWidth,
  height - stageMarksHeight < 0 ? 0 : height - stageMarksHeight,
);

/// The rows `pageup` and `pagedown` move in the list and the Code.
const pageStep = 10;

/// How far the Code scrolls across at most, and the columns a step across
/// (`left`, `right`, the shifted wheel) moves it.
const codeMaxX = 80;

/// See [codeMaxX].
const codeStepX = 4;

/// The rows a notch of the wheel scrolls the list and the Code.
const wheelRows = 3;

/// The rows a notch of the wheel scrolls the options under the stage.
const wheelOptionRows = 2;

/// The palette's width at most, and the rows of its list.
const paletteWidth = 72;

/// See [paletteWidth].
const paletteRows = 12;

/// The toasts shown at once at most; the oldest goes for a new one.
const toastCap = 3;

/// How long a toast shows, in milliseconds, how long it slides in and
/// how long it fades out at the end.
const toastMs = 2600;

/// See [toastMs].
const toastInMs = 200;

/// See [toastMs].
const toastOutMs = 260;

/// How long a new theme takes to fade in, in milliseconds.
const themeFadeMs = 280;

/// How long a line of the Code that changed stays lit, in milliseconds.
const codeLitMs = 900;

/// How long the shell's glides take, in milliseconds: the list's scroll,
/// the tab's underline, the options' scroll.
const glideMs = 160;

/// How long the palette takes to open, and a segmented choice's highlight
/// to glide to the new choice, in milliseconds.
const paletteOpenMs = 140;

/// See [paletteOpenMs].
const segmentGlideMs = 140;

/// How long a switch's knob takes to cross, and a slider's thumb to move,
/// in milliseconds.
const knobMs = 130;

/// See [knobMs].
const thumbMs = 90;

/// How long the list's selection glides to a row [rows] away, in
/// milliseconds.
int selectionGlideMs(int rows) => (70 + 18 * rows).clamp(0, 220);
