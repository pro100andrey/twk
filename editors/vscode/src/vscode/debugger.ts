// The [Debugger] of vscode.debug, with Dart-Code's sessions of the launches
// the extension made followed: a tracker on each tells that it started and
// the address of its VM service (`dart.debuggerUris`).
import * as vscode from 'vscode';

import { Emitter } from '../core/events';
import { fromConfiguration, toConfiguration } from '../app/launch';
import { DartLaunch, DebugSession, Debugger } from '../app/ports';

export class VsCodeDebugger implements Debugger, vscode.Disposable {
  private readonly starts = new Emitter<DebugSession>();
  private readonly vmServices = new Emitter<{ session: DebugSession; uri: string }>();
  private readonly terminated = new Emitter<string>();
  readonly onStarted = this.starts.event;
  readonly onVmService = this.vmServices.event;
  readonly onTerminated = this.terminated.event;
  private readonly sessions = new Map<string, vscode.DebugSession>();
  private readonly listening: vscode.Disposable[];

  constructor() {
    this.listening = [
      vscode.debug.registerDebugAdapterTrackerFactory('dart', {
        createDebugAdapterTracker: (s) => {
          const configuration = fromConfiguration(s.configuration);
          if (!configuration) {
            return undefined;
          }
          const session: DebugSession = { id: s.id, configuration };
          this.sessions.set(s.id, s);
          this.starts.fire(session);
          return {
            onDidSendMessage: (m: unknown) => {
              const uri = debuggerUri(m);
              if (uri) {
                this.vmServices.fire({ session, uri });
              }
            },
          };
        },
      }),
      vscode.debug.onDidTerminateDebugSession((s) => {
        this.sessions.delete(s.id);
        this.terminated.fire(s.id);
      }),
    ];
  }

  async start(launch: DartLaunch): Promise<boolean> {
    const folder = vscode.workspace.getWorkspaceFolder(vscode.Uri.file(launch.program));
    return vscode.debug.startDebugging(folder, { ...toConfiguration(launch), type: launch.type, name: launch.name, request: launch.request });
  }

  async stop(session: DebugSession): Promise<void> {
    const s = this.sessions.get(session.id);
    // stopDebugging(undefined) would stop every session
    if (s) {
      await vscode.debug.stopDebugging(s);
    }
  }

  dispose(): void {
    this.listening.forEach((d) => d.dispose());
    [this.starts, this.vmServices, this.terminated].forEach((e) => e.dispose());
  }
}

/** The VM service address of a `dart.debuggerUris` event, else undefined. */
function debuggerUri(m: unknown): string | undefined {
  if (typeof m !== 'object' || m === null || !('type' in m) || !('event' in m) || !('body' in m)) {
    return undefined;
  }
  const { type, event, body } = m;
  if (type !== 'event' || event !== 'dart.debuggerUris' || typeof body !== 'object' || body === null || !('vmServiceUri' in body)) {
    return undefined;
  }
  return typeof body.vmServiceUri === 'string' ? body.vmServiceUri : undefined;
}
