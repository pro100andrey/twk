// The webview's pick of a cell: which cell of the terminal a click at a
// point of its screen element is on, and the row of the screen shown the
// cursor is on. Pure functions, so that the unit tests run them under
// node; main.ts hangs them on the page's mouse events.

/**
 * The cell, from 0 at the top left, of the point [x], [y] (pixels from
 * the top left of the screen element, [width] by [height] pixels, showing
 * [columns] by [lines] cells); undefined outside it.
 */
export function cellAt(
  x: number,
  y: number,
  width: number,
  height: number,
  columns: number,
  lines: number,
): { readonly x: number; readonly y: number } | undefined {
  if (width <= 0 || height <= 0 || columns <= 0 || lines <= 0 || x < 0 || y < 0 || x >= width || y >= height) {
    return undefined;
  }
  return {
    x: Math.min(columns - 1, Math.floor((x * columns) / width)),
    y: Math.min(lines - 1, Math.floor((y * lines) / height)),
  };
}

/**
 * The row of the screen shown the cursor is on: xterm.js's `cursorY`,
 * counted from the top of its last screen (`baseY`), as the rows shown
 * from [viewportY] count it (scrolled back, the person sees rows of the
 * history above it). The row may be off the screen shown: below it, or
 * negative above it.
 */
export function cursorRowShown(cursorY: number, baseY: number, viewportY: number): number {
  return cursorY + baseY - viewportY;
}
