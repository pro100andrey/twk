// New Project and Install Agent Skill: the pickers and messages over
// app/create.ts, which runs `twk create` and `twk agents`. The person picks
// a template (with its description, as `twk create --list` says it), a
// folder and the files for agents; nothing here decides what is written.
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import * as vscode from 'vscode';

import { AgentsOutcome, CreateOutcome, Creator, TwkOutcome, agentsChoices } from '../app/create';
import { Log } from '../app/ports';
import { startNodeProcess } from '../core/process';
import { projectOf } from '../core/project';
import { cancellable, twkCommand } from './tape';

const defaultCommand = ['dart', 'run', 'twk_dev:twk'];

/** What `twk.newProject` is asked: given whole, it asks nothing (a test's, a keybinding's). */
export interface NewProjectRequest {
  readonly template: string;
  readonly directory: string;
  readonly agents: readonly ('skill' | 'agents-md')[];
}

export function registerCreate(context: vscode.ExtensionContext, log: Log & { show(preserveFocus?: boolean): void }): void {
  const creator = new Creator({
    start: startNodeProcess,
    command: twkCommand,
    defaultCommand,
    globalCommand: ['dart', 'pub', 'global', 'run', 'twk_dev:twk'],
    env: process.env,
    log,
  });

  // twk_dev not being there is the person's to fix, and installing it is theirs to click: it is a Dart package activated on their machine
  const offerInstall = (what: string) =>
    void vscode.window
      .showErrorMessage(`twk: ${what}: twk_dev is not available here, neither in this folder's pubspec.yaml nor activated on this machine.`, 'Activate twk_dev', 'Show Output')
      .then((b) => {
        if (b === 'Activate twk_dev') {
          const terminal = vscode.window.createTerminal('twk_dev');
          terminal.show();
          // typed, not run: Enter is the person's second click
          terminal.sendText('dart pub global activate twk_dev', false);
        } else if (b) {
          log.show(true);
        }
      });

  const failed = (what: string, outcome: TwkOutcome) => {
    if (outcome.cancelled) {
      void vscode.window.showInformationMessage(`twk: ${what} cancelled`);
    } else if (outcome.missing) {
      offerInstall(what);
    } else {
      void vscode.window.showErrorMessage(`twk: ${what}: ${(outcome.error ?? '').split('\n')[0]}`, 'Show Output').then((b) => b && log.show(true));
    }
  };

  const workDir = () => vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? os.homedir();

  context.subscriptions.push(
    vscode.commands.registerCommand('twk.newProject', async (given?: NewProjectRequest): Promise<CreateOutcome | undefined> => {
      try {
        const cwd = workDir();
        let request = given;
        if (!request) {
          const templates = await cancellable('twk create --list', (cancel) => creator.templates(cwd, cancel)).then(
            (t) => t,
            (e: Error) => {
              failed('New Project', { error: e.message, lines: [], cancelled: false, missing: /twk_dev is not available/.test(e.message) });
              return undefined;
            },
          );
          if (!templates) {
            return undefined;
          }
          const template = await vscode.window.showQuickPick(
            templates.map((t) => ({ label: t.name, description: t.description })),
            { title: 'New twk Project (1/3): the template', placeHolder: 'The kind of app' },
          );
          if (!template) {
            return undefined;
          }
          const folder = (
            await vscode.window.showOpenDialog({
              title: 'New twk Project (2/3): the folder',
              openLabel: 'Select Folder',
              canSelectFiles: false,
              canSelectFolders: true,
              canSelectMany: false,
              defaultUri: vscode.Uri.file(cwd),
            })
          )?.[0];
          if (!folder) {
            return undefined;
          }
          let directory = folder.fsPath;
          // the chosen folder is the project's when it is empty, else the project goes in a folder of its own in it
          if (fs.existsSync(directory) && fs.readdirSync(directory).length > 0) {
            const name = await vscode.window.showInputBox({
              title: `${path.basename(directory)} is not empty: the folder for the project in it`,
              prompt: 'The name of the new folder (the package is named after it)',
              validateInput: (v) => (v.trim() === '' || /[\\/]/.test(v) ? 'A name, not a path' : fs.existsSync(path.join(directory, v.trim())) ? 'Already there' : undefined),
            });
            if (!name) {
              return undefined;
            }
            directory = path.join(directory, name.trim());
          }
          const files = await vscode.window.showQuickPick(
            agentsChoices.map((a) => ({ label: a.label, description: a.description, picked: true, flag: a.flag })),
            { title: 'New twk Project (3/3): files for coding agents', placeHolder: 'None, if nothing is picked', canPickMany: true },
          );
          if (!files) {
            return undefined;
          }
          request = { template: template.label, directory, agents: files.map((f) => f.flag) };
        }
        const name = path.basename(request.directory);
        const outcome = await cancellable(`twk create ${name}`, (cancel) => creator.create({ dir: request.directory, template: request.template, agents: request.agents }, cwd, cancel));
        if (outcome.error !== undefined) {
          failed(`New Project ${name}`, outcome);
          return outcome;
        }
        log.show(true);
        const uri = vscode.Uri.file(request.directory);
        // the buttons are not waited for: the project is made either way
        void vscode.window.showInformationMessage(`twk: created ${name} (template ${request.template})`, 'Open', 'Open in New Window').then((b) => {
          if (b) {
            void vscode.commands.executeCommand('vscode.openFolder', uri, { forceNewWindow: b === 'Open in New Window' });
          }
        });
        return outcome;
      } catch (e) {
        void vscode.window.showErrorMessage(`twk: ${e instanceof Error ? e.message : String(e)}`);
        return undefined;
      }
    }),

    vscode.commands.registerCommand('twk.installAgentSkill', async (given?: string): Promise<AgentsOutcome | undefined> => {
      try {
        const project = given ?? (await projectToWrite());
        if (!project) {
          return undefined;
        }
        const name = path.basename(project);
        const outcome = await cancellable(`twk agents ${name}`, (cancel) => creator.agents(project, cancel));
        if (outcome.error !== undefined) {
          failed(`Install Agent Skill in ${name}`, outcome);
          return outcome;
        }
        // what it left as it is (files the person changed) is a warning, with the names; the whole of it is in the output
        if (outcome.left.length > 0) {
          void vscode.window.showWarningMessage(`twk: ${outcome.summary ?? 'twk agents'}\n${outcome.left.join('\n')}`, 'Show Output').then((b) => b && log.show(true));
        } else {
          void vscode.window.showInformationMessage(`twk: ${outcome.summary ?? outcome.lines[0] ?? 'twk agents: done'}`, 'Show Output').then((b) => b && log.show(true));
        }
        return outcome;
      } catch (e) {
        void vscode.window.showErrorMessage(`twk: ${e instanceof Error ? e.message : String(e)}`);
        return undefined;
      }
    }),
  );
}

/** The project to write the skill into: the active file's, else the workspace folder's (asked where there are several). */
async function projectToWrite(): Promise<string | undefined> {
  const file = vscode.window.activeTextEditor?.document.uri;
  const ofFile = file?.scheme === 'file' ? projectOf(file.fsPath) : undefined;
  if (ofFile) {
    return ofFile;
  }
  const folders = vscode.workspace.workspaceFolders ?? [];
  const projects = folders.map((f) => f.uri.fsPath).filter((f) => fs.existsSync(path.join(f, 'pubspec.yaml')));
  if (projects.length <= 1) {
    if (projects[0]) {
      return projects[0];
    }
    void vscode.window.showErrorMessage('twk: Install Agent Skill: no pubspec.yaml in the workspace; open a twk project, or make one with twk: New Project.');
    return undefined;
  }
  return (await vscode.window.showQuickPick(projects, { title: 'Install the agent skill in' })) ?? undefined;
}
