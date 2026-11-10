// The command that opens a file in the editor the extension runs in, for the
// apps it starts: their TWK_EDITOR (twk's `editorCommand`: `{file}`, `{line}`
// and `{column}` put in, words in quotes keep their blanks), so the app's
// console opens a frame of its stack here. The editor's own command line
// (`<appRoot>/bin/code`), by its path: `code` need not be on the PATH. No
// message over the twk terminal's wire: the terminal does not name a command
// for the app to run (twk_core's `Terminal.settingNames`), and a path to a
// program of this machine, set in the environment of the app the extension
// starts, is the user's own editor and nothing a remote end can change.
import * as path from 'node:path';

/** The names of the editors' command lines in `<appRoot>/bin`, VS Code's first. */
const binaries = ['code', 'code-insiders', 'codium', 'cursor'];

/**
 * TWK_EDITOR for the editor installed at [appRoot] (`vscode.env.appRoot`),
 * whose command line is the first of [binaries] that [exists] finds in its
 * `bin` (`.cmd` on Windows); undefined where it has none. `-r` reuses the
 * window the app's project is open in, `-g` goes to the line.
 */
export function editorCommandOf(appRoot: string, platform: string, exists: (file: string) => boolean): string | undefined {
  for (const name of binaries) {
    const file = path.join(appRoot, 'bin', platform === 'win32' ? `${name}.cmd` : name);
    if (exists(file) && !file.includes('"')) {
      return `"${file}" -r -g {file}:{line}:{column}`;
    }
  }
  return undefined;
}
