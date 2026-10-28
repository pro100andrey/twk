// F5: the debug configurations of type `twk` (launch.json, the snippet
// "twk: Debug in twk Terminal"), and Dart ones with `"twkTerminal": true`,
// resolved into Dart-Code's launch in a twk terminal of its own. VS Code
// resolves a configuration again by its new type when a provider changes
// it, so a `twk` one goes on as a Dart one through Dart-Code's providers;
// once its variables are substituted, the terminal is opened for it
// (app/hot_apps.ts, `debugLaunch`) and TWK_SHELL put in its `env`.
import * as vscode from 'vscode';

import { DebugRequest, asDartConfiguration, debugRequest, toConfiguration, wantsTerminal } from '../app/launch';
import { DartLaunch } from '../app/ports';

/** The debug type of the twk configurations. */
export const twkDebugType = 'twk';

/** What the providers hand the use case: a new terminal and the launch for it. */
export type LaunchFor = (request: DebugRequest) => Promise<DartLaunch>;

/** The first configuration of a new launch.json, and the snippet. */
export const currentFile: vscode.DebugConfiguration = {
  type: twkDebugType,
  request: 'launch',
  name: 'twk: current file',
  program: '${file}',
};

/** Registers the providers: `twk` turned into Dart, Dart's with `twkTerminal` given their terminal. */
export function registerLaunches(launchFor: LaunchFor, error: (message: string) => void): vscode.Disposable {
  const twk: vscode.DebugConfigurationProvider = {
    provideDebugConfigurations: () => [currentFile],
    resolveDebugConfiguration: (_folder, c) => {
      // F5 with no launch.json: the current file
      const dart = asDartConfiguration(c.type ? c : { ...currentFile, ...c });
      if (typeof dart === 'string') {
        error(dart);
        return undefined;
      }
      return { ...dart, type: 'dart', name: typeof dart.name === 'string' ? dart.name : 'twk', request: 'launch' };
    },
  };
  const dart: vscode.DebugConfigurationProvider = {
    resolveDebugConfiguration: (_folder, c) => (wantsTerminal(c) && c.program === undefined ? { ...c, program: '${file}' } : c),
    resolveDebugConfigurationWithSubstitutedVariables: async (_folder, c) => {
      if (!wantsTerminal(c)) {
        return c;
      }
      const request = debugRequest(c);
      if (typeof request === 'string') {
        error(request);
        return undefined;
      }
      try {
        const launch = await launchFor(request);
        return { ...toConfiguration(launch), type: launch.type, name: launch.name, request: launch.request };
      } catch (e) {
        error(e instanceof Error ? e.message : String(e));
        return undefined;
      }
    },
  };
  const registered = [
    vscode.debug.registerDebugConfigurationProvider(twkDebugType, twk),
    // offered in the Run and Debug view's list without a launch.json
    vscode.debug.registerDebugConfigurationProvider(
      twkDebugType,
      { provideDebugConfigurations: () => [currentFile] },
      vscode.DebugConfigurationProviderTriggerKind.Dynamic,
    ),
    vscode.debug.registerDebugConfigurationProvider('dart', dart),
  ];
  return { dispose: () => registered.forEach((d) => d.dispose()) };
}
