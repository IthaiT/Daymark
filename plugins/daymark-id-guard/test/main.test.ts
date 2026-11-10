import { Compartment, EditorState, type Extension } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { afterEach, describe, expect, it, vi } from "vitest";

const sdk = vi.hoisted(() => ({
  load: vi.fn(async (): Promise<unknown> => ({ folder: "Daymark" })),
  save: vi.fn(async (_value: unknown) => {}),
  notice: vi.fn(),
}));

// Obsidian supplies this module at runtime. Editor extensions below are real CM6.
vi.mock("obsidian", async () => {
  const { StateField } = await import("@codemirror/state");
  class Plugin {
    extensions: Extension[] = [];
    commands: { id: string; callback?: () => void }[] = [];
    tabs: unknown[] = [];
    constructor(readonly app: unknown) {}
    loadData = sdk.load;
    saveData = sdk.save;
    registerEditorExtension(extension: Extension) { this.extensions.push(extension); }
    addCommand(command: { id: string }) { this.commands.push(command); }
    addSettingTab(tab: unknown) { this.tabs.push(tab); }
  }
  return {
    Plugin,
    editorInfoField: StateField.define({ create: () => ({ file: null, editor: null }), update: (value) => value }),
    Notice: class { constructor(message: string) { sdk.notice(message); } },
    PluginSettingTab: class { constructor(_app: unknown, _plugin: unknown) {} },
    Setting: class {},
    TFile: class {},
    MarkdownView: class {},
  };
});

import { editorInfoField } from "obsidian";
import DaymarkIdGuard from "../src/main";

const id = "^daymark-obsidian-00000000-0000-4000-8000-000000000001";
const views: EditorView[] = [];
interface HostPlugin {
  extensions: Extension[];
  commands: { id: string; callback?: () => void }[];
}

async function host() {
  const editors: { view: EditorView; compartment: Compartment }[] = [];
  let registered: HostPlugin;
  const app = {
    workspace: {
      updateOptions: () => {
        for (const { view, compartment } of editors) {
          view.dispatch({ effects: compartment.reconfigure([...registered.extensions]) });
        }
      },
      iterateAllLeaves: () => {},
    },
    vault: { getAbstractFileByPath: () => null },
  };
  const plugin = new DaymarkIdGuard(app as never, {} as never);
  registered = plugin as unknown as HostPlugin;
  await plugin.onload();
  function editor(path: string) {
    const compartment = new Compartment();
    const view = new EditorView({
      parent: document.body,
      state: EditorState.create({
        doc: `- [ ] 计划 ${id}`,
        extensions: [
          editorInfoField.init(() => ({ file: { path }, editor: {} }) as never),
          compartment.of([...registered.extensions]),
        ],
      }),
    });
    views.push(view);
    editors.push({ view, compartment });
    return view;
  }
  return { plugin, registered, editor };
}

afterEach(() => {
  for (const view of views.splice(0)) view.destroy();
  sdk.load.mockReset().mockResolvedValue({ folder: "Daymark" });
  sdk.save.mockReset().mockResolvedValue(undefined);
  sdk.notice.mockClear();
});

describe("Obsidian plugin lifecycle", () => {
  it("loads stored scope, registers commands and protects only the configured folder", async () => {
    const { editor, registered } = await host();
    expect(registered.commands.map((command) => command.id)).toEqual(["toggle-unlock"]);
    expect(editor("Daymark/A.md").contentDOM.textContent).not.toContain(id);
    expect(editor("Other/A.md").contentDOM.textContent).toContain(id);
    expect(editor("Daymark/Nested/A.md").contentDOM.textContent).toContain(id);
  });

  it("starts disabled without a configured folder and activates existing editors after saving", async () => {
    sdk.load.mockResolvedValue(null);
    const { plugin, editor } = await host();
    const view = editor("Daymark/A.md");
    expect(view.contentDOM.textContent).toContain(id);
    await plugin.setFolder("Daymark");
    expect(sdk.save).toHaveBeenCalledWith({ folder: "Daymark" });
    expect(view.contentDOM.textContent).not.toContain(id);
    view.dispatch({ changes: { from: 10, to: 11, insert: "z" } });
    expect(view.state.doc.toString()).toContain(id);
  });

  it("unlocks and relocks existing editors without changing their source", async () => {
    const { plugin, registered, editor } = await host();
    const view = editor("Daymark/A.md");
    const toggle = registered.commands.find((command) => command.id === "toggle-unlock")!.callback!;
    const source = view.state.doc.toString();
    toggle();
    expect(plugin.unlocked).toBe(true);
    expect(view.contentDOM.textContent).toContain(id);
    toggle();
    expect(view.contentDOM.textContent).not.toContain(id);
    expect(view.state.doc.toString()).toBe(source);
  });

  it("keeps the original scope active when a settings write fails", async () => {
    const { plugin, editor } = await host();
    const view = editor("Daymark/A.md");
    sdk.save.mockRejectedValue(new Error("write failed"));
    await plugin.setFolder("Other");
    expect(plugin.settings.folder).toBe("Daymark");
    expect(view.contentDOM.textContent).not.toContain(id);
    expect(sdk.notice).toHaveBeenCalledWith("设置保存失败，已保留原设置。");
  });

  it("does not change the active scope while a settings write is still pending", async () => {
    const { plugin, editor } = await host();
    const view = editor("Daymark/A.md");
    let resolve!: () => void;
    sdk.save.mockImplementation(() => new Promise<void>((done) => { resolve = done; }));
    const saving = plugin.setFolder("Other");
    expect(plugin.settings.folder).toBe("Daymark");
    view.dispatch({ changes: { from: 10, to: 11, insert: "z" } });
    expect(view.state.doc.toString()).toContain(id);
    resolve();
    await saving;
    expect(view.contentDOM.textContent).toContain(id);
  });

  it("rejects absolute folder paths without writing settings", async () => {
    const { plugin } = await host();
    await plugin.setFolder("D:\\Vault\\Daymark");
    expect(sdk.save).not.toHaveBeenCalled();
    expect(plugin.settings.folder).toBe("Daymark");
  });
});
