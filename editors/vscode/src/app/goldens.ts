// The golden screens of twk_test's matchesScreenFile in the editor: what a
// screen file shows (the golden, and the screen a failed test left beside
// it as `<file>.actual`, with the cells that differ), and Accept Actual.
// Over a [GoldenFiles] port and a panel speaking webview/screen_protocol.ts.
//
// Accept Actual makes the actual screen the golden: the very text a rerun of
// the test with TWK_UPDATE_GOLDENS=1 writes, as twk_test leaves `.actual` as
// the file would be written (the legend's characters kept), so the test need
// not be run again, and no test runner of the editor is hooked. The `.actual`
// is removed with it, as the update does.
import { Disposable } from '../core/events';
import { ScreenFileError, diffScreens, parseScreenFile } from '../core/screen_file';
import { ScreenState, ToScreen, isFromScreen } from '../webview/screen_protocol';
import { WebviewPanelPort } from './webview_view';

/** The suffix twk_test gives the screen a failed test leaves beside its golden. */
export const actualSuffix = '.actual';

/** The files of the goldens, as the editor gives them. */
export interface GoldenFiles {
  /** The text of [path], or undefined where there is no such file. */
  read(path: string): Promise<string | undefined>;
  /** When [path] was last changed (ms), or undefined where there is no such file. */
  modified(path: string): Promise<number | undefined>;
  write(path: string, text: string): Promise<void>;
  /** Removes [path]; no error where it is not there. */
  remove(path: string): Promise<void>;
}

/** The screen file at [path] as the editor shows it. */
export async function screenState(files: GoldenFiles, path: string): Promise<ScreenState> {
  const text = await files.read(path);
  if (text === undefined) {
    return { kind: 'bad', message: 'the file is gone' };
  }
  let golden;
  try {
    golden = parseScreenFile(text);
  } catch (e) {
    if (e instanceof ScreenFileError) {
      return { kind: 'bad', message: `not a screen file: ${e.message}` };
    }
    throw e;
  }
  const actualPath = path + actualSuffix;
  const actualText = await files.read(actualPath);
  if (actualText === undefined) {
    return { kind: 'ok', golden, actual: null, diff: null, stale: false };
  }
  // a screen older than the golden is of a run before the golden changed
  const [then, now] = await Promise.all([files.modified(actualPath), files.modified(path)]);
  if (then === undefined || now === undefined || then < now) {
    return { kind: 'ok', golden, actual: null, diff: null, stale: true };
  }
  try {
    const actual = parseScreenFile(actualText);
    return { kind: 'ok', golden, actual, diff: diffScreens(golden, actual), stale: false };
  } catch (e) {
    if (e instanceof ScreenFileError) {
      return { kind: 'bad', message: `${actualPath} is not a screen file: ${e.message}` };
    }
    throw e;
  }
}

/** Accepts the actual screen of the golden at [path]: it becomes the golden. False where there is no fresh one. */
export async function acceptActual(files: GoldenFiles, path: string): Promise<boolean> {
  const state = await screenState(files, path);
  if (state.kind !== 'ok' || state.actual === null) {
    return false;
  }
  const text = await files.read(path + actualSuffix);
  if (text === undefined) {
    return false;
  }
  await files.write(path, text);
  await files.remove(path + actualSuffix);
  return true;
}

/** The editor of one screen file, over its panel. */
export class GoldenEditor {
  private readonly listening: Disposable[];
  private disposed = false;

  constructor(
    private readonly panel: WebviewPanelPort<ToScreen>,
    private readonly files: GoldenFiles,
    readonly path: string,
    private readonly name: string,
    private readonly say: (message: string) => void = () => {},
  ) {
    this.listening = [
      panel.onMessage((m) => {
        if (isFromScreen(m)) {
          void (m.type === 'ready' ? this.refresh() : this.accept());
        }
      }),
      panel.onDispose(() => {
        this.disposed = true;
        this.listening.forEach((d) => d.dispose());
      }),
    ];
  }

  /** Shows the file as it is now: told when it or its `.actual` changed. */
  async refresh(): Promise<void> {
    const state = await screenState(this.files, this.path);
    if (!this.disposed) {
      await this.panel.post({ type: 'show', name: this.name, state });
    }
  }

  private async accept(): Promise<void> {
    try {
      if (await acceptActual(this.files, this.path)) {
        this.say(`twk: ${this.name} now holds the screen of the failed test`);
      } else {
        this.say(`twk: no screen of a failed test beside ${this.name} to accept`);
      }
    } catch (e) {
      this.say(`twk: could not accept the screen: ${e instanceof Error ? e.message : String(e)}`);
    }
    await this.refresh();
  }
}
