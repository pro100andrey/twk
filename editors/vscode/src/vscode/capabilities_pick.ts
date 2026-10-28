// The switch panel of twk: Choose twk Terminal Capabilities, in VS Code's
// quick picks: a preset, or each switch (the colours, the images, then the
// toggles at once), kept in the settings `twk.terminal.profile` and
// `twk.terminal.capabilities` (the switches changed from the preset).
// They reach the next app to connect; with apps running, a hot restart is
// offered, which takes them to those too. The items and what the picks
// make are core/capabilities.ts's.
import * as vscode from 'vscode';

import {
  Capabilities,
  Choice,
  changesFrom,
  changesSetting,
  colorDepths,
  describeChoice,
  graphicsKinds,
  presets,
  toggleItems,
  togglesPicked,
} from '../core/capabilities';

const eachSwitch = 'Each switch…';

/** Asks for the capabilities of the twk terminals; the choice made, kept in the settings, or undefined: none. */
export async function chooseCapabilities(current: Choice): Promise<Choice | undefined> {
  const now = describeChoice(current);
  const pick = await vscode.window.showQuickPick(
    [
      ...presets.map((p) => ({ label: p.name, description: p.description, detail: p.name === now ? 'now' : undefined })),
      { label: '', kind: vscode.QuickPickItemKind.Separator },
      { label: eachSwitch, description: `from ${current.preset.name}: colours, images, and each of the rest`, detail: now === current.preset.name ? undefined : `now: ${now}` },
    ],
    { title: 'What the twk terminal is for the next app to connect' },
  );
  if (!pick) {
    return undefined;
  }
  const preset = presets.find((p) => p.name === pick.label);
  const choice = preset ? { preset, capabilities: preset.capabilities } : await eachOf(current);
  if (!choice) {
    return undefined;
  }
  const c = vscode.workspace.getConfiguration('twk');
  await c.update('terminal.profile', choice.preset.name, vscode.ConfigurationTarget.Workspace);
  const changes = changesSetting(changesFrom(choice.preset, choice.capabilities));
  await c.update('terminal.capabilities', Object.keys(changes).length === 0 ? undefined : changes, vscode.ConfigurationTarget.Workspace);
  return choice;
}

/** The switches picked one after another, from [current]'s. */
async function eachOf(current: Choice): Promise<Choice | undefined> {
  const was = current.capabilities;
  const colors = await vscode.window.showQuickPick(
    colorDepths.map((d) => ({ label: d.label, description: d.description, picked: d.colors === was.colors, value: d.colors })),
    { title: 'twk terminal: colours (1 of 3)', placeHolder: colorDepths.find((d) => d.colors === was.colors)?.label },
  );
  if (!colors) {
    return undefined;
  }
  const graphics = await vscode.window.showQuickPick(
    graphicsKinds.map((g) => ({ label: g.label, description: g.description, value: g.graphics })),
    { title: 'twk terminal: images (2 of 3)', placeHolder: graphicsKinds.find((g) => g.graphics === was.graphics)?.label },
  );
  if (!graphics) {
    return undefined;
  }
  const toggles = await vscode.window.showQuickPick(toggleItems(was), {
    title: 'twk terminal: what it does (3 of 3)',
    canPickMany: true,
  });
  if (!toggles) {
    return undefined;
  }
  const capabilities: Capabilities = togglesPicked(
    { ...was, colors: colors.value, graphics: graphics.value },
    toggles.map((t) => t.label),
  );
  return { preset: current.preset, capabilities };
}
