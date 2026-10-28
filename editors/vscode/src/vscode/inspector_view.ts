// The twk inspector's tree view (`twk.inspector`, in Run and Debug) as the
// [InspectorView] of app/inspector.ts, the [SourceOpener] that opens a
// place of the code in an editor, and the pick mode's button
// ([PickingIndicator]: the context key `twk.inspector.picking`, which
// shows the pressed one in the view's title).
import * as vscode from 'vscode';

import { Emitter } from '../core/events';
import { InspectNode, InspectTree, describeNode, detailsOf, shownRoot } from '../core/inspect';
import { SourceSpot } from '../core/locator';
import { InspectorView, PickingIndicator, SourceOpener } from '../app/ports';

/** How many levels below the app's own element are shown expanded at first. */
const expandedLevels = 3;

export class VsCodeInspectorView implements InspectorView, vscode.TreeDataProvider<InspectNode>, vscode.Disposable {
  private root: InspectNode | null = null;
  private readonly parents = new Map<number, InspectNode>();
  private readonly nodes = new Map<number, InspectNode>();
  private readonly depths = new Map<number, number>();
  /** The nodes expanded or collapsed by the person, kept as the items' ids change ([clearSelection]). */
  private readonly expanded = new Map<number, boolean>();
  /**
   * What the items' ids begin with: a new one makes every item new, which
   * is the one way a TreeView selects none (its API has no unselect).
   */
  private generation = 0;
  private readonly changes = new vscode.EventEmitter<InspectNode | undefined>();
  readonly onDidChangeTreeData = this.changes.event;
  private readonly visibility = new Emitter<boolean>();
  readonly onVisible = this.visibility.event;
  private readonly selections = new Emitter<number | undefined>();
  readonly onSelect = this.selections.event;
  readonly treeView: vscode.TreeView<InspectNode>;
  private readonly listening: vscode.Disposable[];

  constructor() {
    this.treeView = vscode.window.createTreeView('twk.inspector', { treeDataProvider: this, showCollapseAll: true });
    this.listening = [
      this.treeView,
      this.changes,
      this.treeView.onDidChangeVisibility((e) => this.visibility.fire(e.visible)),
      this.treeView.onDidChangeSelection((e) => this.selections.fire(e.selection[0]?.id)),
      this.treeView.onDidExpandElement((e) => this.expanded.set(e.element.id, true)),
      this.treeView.onDidCollapseElement((e) => this.expanded.set(e.element.id, false)),
    ];
  }

  get visible(): boolean {
    return this.treeView.visible;
  }

  /** The node [id] names in the tree shown. */
  node(id: number): InspectNode | undefined {
    return this.nodes.get(id);
  }

  show(tree: InspectTree | undefined, message: string): void {
    this.treeView.message = message || undefined;
    this.root = tree ? shownRoot(tree) : null;
    this.parents.clear();
    this.nodes.clear();
    this.depths.clear();
    const index = (n: InspectNode, depth: number) => {
      this.nodes.set(n.id, n);
      this.depths.set(n.id, depth);
      for (const c of n.children) {
        this.parents.set(c.id, n);
        index(c, depth + 1);
      }
    };
    if (this.root) {
      index(this.root, 0);
    }
    this.changes.fire(undefined);
  }

  clearSelection(): void {
    if (this.treeView.selection.length === 0) {
      return;
    }
    this.generation++;
    this.changes.fire(undefined);
    // the TreeView tells no change of the selection it dropped
    this.selections.fire(undefined);
  }

  reveal(id: number): void {
    const n = this.nodes.get(id);
    if (n) {
      this.treeView.reveal(n, { select: true, focus: false, expand: true }).then(undefined, () => {});
    }
  }

  getTreeItem(n: InspectNode): vscode.TreeItem {
    const item = new vscode.TreeItem(
      n.name,
      n.children.length === 0
        ? vscode.TreeItemCollapsibleState.None
        : (this.expanded.get(n.id) ?? (this.depths.get(n.id) ?? 0) < expandedLevels)
          ? vscode.TreeItemCollapsibleState.Expanded
          : vscode.TreeItemCollapsibleState.Collapsed,
    );
    item.id = `${this.generation}:${n.id}`;
    item.description = describeNode(n);
    item.tooltip = detailsOf(n).join('\n');
    item.contextValue = n.build ? 'twkBuilds' : 'twkNode';
    return item;
  }

  getChildren(n?: InspectNode): InspectNode[] {
    return n ? [...n.children] : this.root ? [this.root] : [];
  }

  getParent(n: InspectNode): InspectNode | undefined {
    return this.parents.get(n.id);
  }

  dispose(): void {
    this.listening.forEach((d) => d.dispose());
    this.visibility.dispose();
    this.selections.dispose();
  }
}

/** Opens a place of the code in the first editor group, the twk terminal left beside it. */
export const vsCodeOpener: SourceOpener = {
  async open(spot: SourceSpot, options?: { readonly keepFocus?: boolean }): Promise<void> {
    const at = new vscode.Position(spot.line - 1, spot.column - 1);
    await vscode.window.showTextDocument(vscode.Uri.parse(spot.uri), {
      selection: new vscode.Range(at, at),
      viewColumn: vscode.ViewColumn.One,
      preview: true,
      preserveFocus: options?.keepFocus === true,
    });
  },
};

/** The pick mode's button: the context key its two commands' `when` reads (twk.inspector.pick, twk.inspector.stopPicking). */
export const vsCodePickingIndicator: PickingIndicator = {
  show(on: boolean): void {
    void vscode.commands.executeCommand('setContext', 'twk.inspector.picking', on);
  },
};
