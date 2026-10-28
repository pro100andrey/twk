// What the commands on "the twk terminal" act on, of the screens open (the
// twk terminals and the recordings played back), and the screen's text as
// it is copied.
import { Screen, Snapshot } from './ports';

/** The screen of [screens] whose view is the editor's active one, else the newest; none when none is open. */
export function activeScreen(screens: readonly Screen[]): Screen | undefined {
  const open = screens.filter((s) => !s.view.isClosed);
  return open.find((s) => s.view.isActive) ?? open.at(-1);
}

/** What [snapshot] shows as text: its rows, each without the blanks that end it, the blank rows at its end left out. */
export function screenText(snapshot: Snapshot): string {
  const rows = snapshot.rows.map((r) => r.trimEnd());
  while (rows.length > 0 && rows[rows.length - 1] === '') {
    rows.pop();
  }
  return rows.length === 0 ? '' : `${rows.join('\n')}\n`;
}
