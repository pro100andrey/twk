// `.tape` in the editor: hovers from the statements' documentation, the
// lenses Run, Check and Preview over the first statement, the diagnostics
// of what `twk tape` said, and the preview panel (the stills and the end of
// a tape, a strip of frames, a click going to the statement). The work is
// app/tape.ts's (running) and core/tape*.ts's (reading what it says).
import * as fs from 'node:fs';
import * as path from 'node:path';
import { randomBytes } from 'node:crypto';

import * as vscode from 'vscode';

import { DiagnosticsSink, TapeDiagnostic, Tapes } from '../app/tape';
import { tapeHover, tapeOutputs, tapeStatements } from '../core/tape';
import { PreviewFrame, previewClick, previewHtml } from '../core/tape_preview';
import { isInside, projectOf } from '../core/project';
import { startNodeProcess } from '../core/process';
import { Log } from '../app/ports';

export const tapeLanguage = 'tape';

/** What `twk` is, from the setting `twk.command`. */
export const twkCommand = (): string[] => vscode.workspace.getConfiguration('twk').get<string[]>('command', ['dart', 'run', 'twk_dev:twk']);

/** [work] under a notification with a Cancel that aborts what it runs. */
export function cancellable<T>(title: string, work: (cancel: AbortSignal) => Promise<T>): Thenable<T> {
  return vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title, cancellable: true }, (_progress, token) => {
    const abort = new AbortController();
    const listener = token.onCancellationRequested(() => abort.abort());
    return work(abort.signal).finally(() => listener.dispose());
  });
}

/** [DiagnosticsSink] over a VS Code collection; a change of the file's text takes its diagnostics away, as they say what the earlier text did. */
export class TapeDiagnostics implements DiagnosticsSink, vscode.Disposable {
  readonly collection = vscode.languages.createDiagnosticCollection('twk tape');
  private readonly listener = vscode.workspace.onDidChangeTextDocument((e) => {
    if (e.document.languageId === tapeLanguage && e.contentChanges.length > 0) {
      this.collection.delete(e.document.uri);
    }
  });

  set(file: string, diagnostics: readonly TapeDiagnostic[]): void {
    const uri = vscode.Uri.file(file);
    const doc = vscode.workspace.textDocuments.find((d) => d.uri.fsPath === file);
    this.collection.set(
      uri,
      diagnostics.map((d) => {
        const range = doc && d.line < doc.lineCount ? doc.lineAt(d.line).range : new vscode.Range(d.line, 0, d.line, 0);
        const diagnostic = new vscode.Diagnostic(range, d.message, vscode.DiagnosticSeverity.Error);
        diagnostic.source = 'twk tape';
        return diagnostic;
      }),
    );
  }

  clear(file: string): void {
    this.collection.delete(vscode.Uri.file(file));
  }

  dispose(): void {
    this.listener.dispose();
    this.collection.dispose();
  }
}

export class TapeLenses implements vscode.CodeLensProvider {
  provideCodeLenses(document: vscode.TextDocument): vscode.CodeLens[] {
    const first = tapeStatements(document.getText())[0];
    if (!first) {
      return [];
    }
    const at = new vscode.Range(first.line, 0, first.line, 0);
    return [
      new vscode.CodeLens(at, { title: 'Run', command: 'twk.tape.run', arguments: [document.uri] }),
      new vscode.CodeLens(at, { title: 'Check', command: 'twk.tape.check', arguments: [document.uri] }),
      new vscode.CodeLens(at, { title: 'Preview', command: 'twk.tape.preview', arguments: [document.uri] }),
    ];
  }
}

export class TapeHovers implements vscode.HoverProvider {
  provideHover(document: vscode.TextDocument, position: vscode.Position): vscode.Hover | undefined {
    const line = document.lineAt(position.line).text;
    const statement = tapeStatements(line)[0];
    if (!statement) {
      return undefined;
    }
    const docs = tapeHover(statement.keyword, statement.source);
    return docs ? new vscode.Hover(new vscode.MarkdownString(docs), document.lineAt(position.line).range) : undefined;
  }
}

/** The tape commands: what the lenses and the palette run. Returns the disposables registered. */
export function registerTape(context: vscode.ExtensionContext, log: Log & { show(preserveFocus?: boolean): void }): { tapes: Tapes; diagnostics: TapeDiagnostics } {
  const diagnostics = new TapeDiagnostics();
  const tapes = new Tapes({
    start: startNodeProcess,
    command: twkCommand,
    projectOf,
    env: process.env,
    diagnostics,
    version: (file) => vscode.workspace.textDocuments.find((d) => d.uri.fsPath === file)?.version,
    log,
  });
  const lenses = new TapeLenses();
  const selector: vscode.DocumentSelector = { language: tapeLanguage, scheme: 'file' };
  context.subscriptions.push(
    diagnostics,
    vscode.languages.registerCodeLensProvider(selector, lenses),
    vscode.languages.registerHoverProvider(selector, new TapeHovers()),
  );

  /** The tape of the command: the one given, else the active editor's; saved first, as what runs is the file. */
  async function tapeFile(uri?: vscode.Uri): Promise<string> {
    const target = uri ?? vscode.window.activeTextEditor?.document.uri;
    if (!target || !target.fsPath.endsWith('.tape')) {
      throw new Error('no .tape file open');
    }
    const open = vscode.workspace.textDocuments.find((d) => d.uri.fsPath === target.fsPath);
    if (open?.isDirty) {
      await open.save();
    }
    return target.fsPath;
  }
  const command = (name: string, f: (file: string) => Promise<unknown>) =>
    context.subscriptions.push(
      vscode.commands.registerCommand(name, async (uri?: vscode.Uri) => {
        try {
          return await f(await tapeFile(uri));
        } catch (e) {
          void vscode.window.showErrorMessage(`twk: ${e instanceof Error ? e.message : String(e)}`);
          return undefined;
        }
      }),
    );

  command('twk.tape.check', async (file) => {
    const report = await cancellable(`twk tape --check ${path.basename(file)}`, (cancel) => tapes.check(file, cancel));
    if (report.cancelled) {
      void vscode.window.showInformationMessage(`twk: ${path.basename(file)}: check cancelled`);
    } else if (report.exit === 0) {
      void vscode.window.showInformationMessage(`twk: ${path.basename(file)}: ${report.summary ?? 'passed'}`);
    } else {
      const shown = report.summary ?? report.error?.message.split('\n')[0] ?? `exit ${report.exit}`;
      void vscode.window.showErrorMessage(`twk: ${path.basename(file)}: ${shown}`, 'Show Output').then((b) => b && log.show(true));
    }
    return report;
  });
  command('twk.tape.run', async (file) => {
    const report = await cancellable(`twk tape ${path.basename(file)}`, (cancel) => tapes.run(file, cancel));
    if (report.cancelled) {
      void vscode.window.showInformationMessage(`twk: ${path.basename(file)}: run cancelled`);
    } else if (report.exit === 0) {
      const outputs = tapeOutputs(fs.readFileSync(file, 'utf8')).filter((o) => o.kind === 'Output');
      const cast = outputs.find((o) => o.file.endsWith('.cast'));
      const buttons = ['Preview', ...(cast ? ['Play'] : [])];
      void vscode.window.showInformationMessage(`twk: ${path.basename(file)} recorded: ${outputs.map((o) => o.file).join(', ') || 'no Output'}`, ...buttons).then((b) => {
        if (b === 'Preview') {
          void vscode.commands.executeCommand('twk.tape.preview', vscode.Uri.file(file));
        } else if (b === 'Play' && cast) {
          void vscode.commands.executeCommand('twk.play', vscode.Uri.file(path.resolve(report.cwd, cast.file)));
        }
      });
    } else {
      const shown = report.error?.message.split('\n')[0] ?? `exit ${report.exit}`;
      void vscode.window.showErrorMessage(`twk: ${path.basename(file)}: ${shown}`, 'Show Output').then((b) => b && log.show(true));
    }
    return report;
  });
  const previews = new Map<string, vscode.WebviewPanel>();
  context.subscriptions.push({ dispose: () => [...previews.values()].forEach((p) => p.dispose()) });
  command('twk.tape.preview', (file) => preview(previews, file));
  return { tapes, diagnostics };
}

/** The panel of [file]'s preview: the files its Screenshots and SVG Outputs wrote, in the order of the tape. */
async function preview(previews: Map<string, vscode.WebviewPanel>, file: string): Promise<vscode.WebviewPanel> {
  const text = fs.readFileSync(file, 'utf8');
  const cwd = projectOf(file) ?? path.dirname(file);
  const outputs = tapeOutputs(text).filter((o) => o.file.endsWith('.svg'));
  // the stills in order, and the end: the animated SVG after them
  const ordered = [...outputs.filter((o) => o.kind === 'Screenshot'), ...outputs.filter((o) => o.kind === 'Output')];
  let panel = previews.get(file);
  if (!panel) {
    panel = vscode.window.createWebviewPanel('twk.tapePreview', `${path.basename(file)} · preview`, { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true }, {
      enableScripts: true,
      localResourceRoots: [vscode.Uri.file(cwd)],
    });
    const mine = panel;
    previews.set(file, mine);
    mine.onDidDispose(() => previews.delete(file));
    mine.webview.onDidReceiveMessage(async (m: unknown) => {
      const click = previewClick(m);
      if (click) {
        const editor = await vscode.window.showTextDocument(vscode.Uri.file(file), { viewColumn: vscode.ViewColumn.One });
        const at = new vscode.Position(click.line, 0);
        editor.selection = new vscode.Selection(at, at);
        editor.revealRange(new vscode.Range(at, at), vscode.TextEditorRevealType.InCenter);
      }
    });
  }
  const shown = panel;
  shown.reveal(undefined, true);
  const frames: PreviewFrame[] = ordered.map((o) => {
    const abs = path.resolve(cwd, o.file);
    if (!isInside(cwd, abs)) {
      return { title: o.file, line: o.line, src: undefined, note: 'outside the project: the preview shows files of the tape\'s project only' };
    }
    return { title: o.file, line: o.line, src: fs.existsSync(abs) ? `${shown.webview.asWebviewUri(vscode.Uri.file(abs))}?v=${fs.statSync(abs).mtimeMs}` : undefined };
  });
  shown.webview.html = previewHtml(path.basename(file), frames, shown.webview.cspSource, randomBytes(16).toString('hex'));
  return shown;
}
