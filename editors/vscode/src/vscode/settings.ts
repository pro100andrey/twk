// The [Settings] of the `twk.*` configuration.
import * as vscode from 'vscode';

import { Choice, choiceOf } from '../core/capabilities';
import { Switches, switchesOf } from '../core/switches';
import { Settings } from '../app/ports';

export class Configuration implements Settings {
  private get c(): vscode.WorkspaceConfiguration {
    return vscode.workspace.getConfiguration('twk');
  }

  capabilities(): Choice {
    return choiceOf(this.c.get<unknown>('terminal.profile'), this.c.get<unknown>('terminal.capabilities'));
  }

  switches(): Switches {
    return switchesOf(this.c.get<unknown>('terminal.screenReader'), this.c.get<unknown>('terminal.debugAids'));
  }

  size(): { columns: number | null; lines: number | null } {
    return { columns: this.c.get<number | null>('terminal.columns') ?? null, lines: this.c.get<number | null>('terminal.lines') ?? null };
  }

  hotReloadOnSave(): boolean {
    return this.c.get<boolean>('hotReloadOnSave', true);
  }
}
