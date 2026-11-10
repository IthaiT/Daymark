import { EditorSelection, EditorState, Facet } from "@codemirror/state";
import { history, redo, undo } from "@codemirror/commands";
import { EditorView } from "@codemirror/view";
import { afterEach, describe, expect, it, vi } from "vitest";
import { clipboardPlan, GuardClipboard } from "../src/clipboard";
import { createIdGuard } from "../src/guard";
import { scanIdentities } from "../src/identity";

const id = (n: number) => `^daymark-obsidian-00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const pathField = Facet.define<string, string>({ combine: (values) => values[0] ?? "" });
const views: EditorView[] = [];
const notices = vi.fn();
const blocked = vi.fn();
let next = 100;
const enabled = () => true;
function fixture(read?: (path: string) => Promise<string | null>) {
  const files = new Map<string, EditorView>();
  const clipboard = new GuardClipboard({
    enabled,
    path: (state) => state.facet(pathField),
    readSource: read ?? (async (path) => files.get(path)?.state.doc.toString() ?? null),
    notify: notices,
    nextId: () => id(next++),
  });
  function editor(path: string, doc: string) {
    const view = new EditorView({
      parent: document.body,
      state: EditorState.create({
        doc,
        extensions: [pathField.of(path), history(), createIdGuard({ enabled, blocked }), clipboard.extension()],
      }),
    });
    views.push(view);
    files.set(path, view);
    return view;
  }
  return { editor, clipboard };
}

function clipboardEvent(view: EditorView, kind: "copy" | "cut" | "paste", values = new Map<string, string>()) {
  const event = new Event(kind, { bubbles: true, cancelable: true });
  Object.defineProperty(event, "clipboardData", {
    value: {
      get types() { return [...values.keys()]; },
      getData: (type: string) => values.get(type) ?? "",
      setData: (type: string, value: string) => { values.set(type, value); },
    },
  });
  view.contentDOM.dispatchEvent(event);
  return { values, prevented: event.defaultPrevented };
}

afterEach(() => {
  for (const view of views.splice(0)) view.destroy();
  notices.mockClear();
  blocked.mockClear();
  next = 100;
});

describe("clipboard plans", () => {
  it("includes the hidden suffix when a complete visible row is selected", () => {
    const state = EditorState.create({ doc: `- [ ] 计划 ${id(1)}`, selection: EditorSelection.single(0, 8) });
    const plan = clipboardPlan(state)!;
    expect(plan.text).toBe(`- [ ] 计划 ${id(1)}\n`);
    expect(plan.to).toBe(state.doc.length);
    expect(plan.linewise).toBe(true);
  });

  it("includes tab-indented descendants and leaves the next sibling", () => {
    const state = EditorState.create({ doc: `- [ ] 父 ${id(1)}\n\t- [ ] 子 ${id(2)}\n    1. [ ] 孙 ${id(3)}\n- [ ] 同级 ${id(4)}` });
    const plan = clipboardPlan(state, true)!;
    expect(plan.text).toContain(id(3));
    expect(plan.text).not.toContain(id(4));
    expect(state.doc.sliceString(plan.to)).toBe(`- [ ] 同级 ${id(4)}`);
  });

  it("does not include a preceding row in a last-row clipboard payload", () => {
    const doc = `正文\n- [ ] 最后 ${id(1)}`;
    const state = EditorState.create({ doc, selection: { anchor: 5 } });
    const plan = clipboardPlan(state)!;
    expect(plan.text).toBe(`- [ ] 最后 ${id(1)}\n`);
    expect(plan.from).toBe(2);
  });
});

describe("native clipboard events", () => {
  it("moves a whole row across files with its original identity", async () => {
    const { editor } = fixture();
    const source = editor("Daymark/A.md", `- [ ] 计划 ${id(1)}\n- [ ] 保留 ${id(2)}`);
    const target = editor("Daymark/B.md", "目标正文");
    const cut = clipboardEvent(source, "cut");
    expect(cut.prevented).toBe(true);
    expect(cut.values.get("text/plain")).toBe(`- [ ] 计划 ${id(1)}\n`);
    expect(source.state.doc.toString()).toBe(`- [ ] 保留 ${id(2)}`);
    clipboardEvent(target, "paste", cut.values);
    await vi.waitFor(() => expect(target.state.doc.toString()).toBe(`- [ ] 计划 ${id(1)}\n目标正文`));
    expect(blocked).not.toHaveBeenCalled();
  });

  it("copies a row into an independent task while leaving the original unchanged", async () => {
    const { editor } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const source = editor("Daymark/A.md", original);
    const target = editor("Daymark/B.md", "");
    const copy = clipboardEvent(source, "copy");
    expect(copy.values.get("text/plain")).not.toContain(id(1));
    clipboardEvent(target, "paste", copy.values);
    await vi.waitFor(() => expect(scanIdentities(target.state.doc)).toHaveLength(1));
    expect(scanIdentities(target.state.doc)[0]!.id).not.toBe(id(1));
    expect(source.state.doc.toString()).toBe(original);
  });

  it("copies selected body text without exposing the hidden suffix", () => {
    const { editor } = fixture();
    const view = editor("Daymark/A.md", `- [ ] 计划 ${id(1)}`);
    view.dispatch({ selection: EditorSelection.single(6, view.state.doc.length) });
    const copy = clipboardEvent(view, "copy");
    expect(copy.values.get("text/plain")).toBe("计划");
  });

  it("refuses partial cuts through an identity without changing the source", () => {
    const { editor } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const view = editor("Daymark/A.md", original);
    view.dispatch({ selection: EditorSelection.single(7, view.state.doc.length) });
    const cut = clipboardEvent(view, "cut");
    expect(cut.values.size).toBe(0);
    expect(view.state.doc.toString()).toBe(original);
    expect(notices).toHaveBeenCalled();
  });

  it("keeps the source intact if clipboard writing fails", () => {
    const { editor } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const view = editor("Daymark/A.md", original);
    const event = new Event("cut", { bubbles: true, cancelable: true });
    Object.defineProperty(event, "clipboardData", { value: { setData() { throw new Error("clipboard unavailable"); } } });
    view.contentDOM.dispatchEvent(event);
    expect(view.state.doc.toString()).toBe(original);
    expect(notices).toHaveBeenCalled();
  });
});

describe("cut identity lifetime", () => {
  it("retains cut IDs on the first paste and generates new IDs on later pastes", async () => {
    const { editor, clipboard } = fixture();
    const source = editor("Daymark/A.md", `- [ ] 父 ${id(1)}\n  - [ ] 子 ${id(2)}`);
    const target = editor("Daymark/B.md", "");
    let content = "";
    await clipboard.copySubtree(source, true, async (text) => { content = text; });
    expect(source.state.doc.toString()).toBe("");
    await clipboard.paste(target, content);
    expect(scanIdentities(target.state.doc).map((span) => span.id)).toEqual([id(1), id(2)]);
    await clipboard.paste(target, content);
    const ids = scanIdentities(target.state.doc).map((span) => span.id);
    expect(ids).toHaveLength(4);
    expect(new Set(ids).size).toBe(4);
    expect(ids.filter((value) => value === id(1))).toHaveLength(1);
  });

  it("does not reuse cut identities after undo has restored the source", async () => {
    const { editor, clipboard } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const source = editor("Daymark/A.md", original);
    const target = editor("Daymark/B.md", "");
    let content = "";
    await clipboard.copySubtree(source, true, async (text) => { content = text; });
    undo(source);
    expect(source.state.doc.toString()).toBe(original);
    await clipboard.paste(target, content);
    expect(scanIdentities(target.state.doc)[0]!.id).not.toBe(id(1));
  });

  it("allows only one concurrent paste to claim a cut identity", async () => {
    let resolve!: (text: string) => void;
    const pendingRead = new Promise<string>((done) => { resolve = done; });
    const { editor, clipboard } = fixture(async () => pendingRead);
    const source = editor("Daymark/A.md", `- [ ] 计划 ${id(1)}`);
    const first = editor("Daymark/B.md", "");
    const second = editor("Daymark/C.md", "");
    let content = "";
    await clipboard.copySubtree(source, true, async (text) => { content = text; });
    const pastes = [clipboard.paste(first, content), clipboard.paste(second, content)];
    resolve("");
    await Promise.all(pastes);
    const ids = [...scanIdentities(first.state.doc), ...scanIdentities(second.state.doc)].map((span) => span.id);
    expect(ids).toContain(id(1));
    expect(new Set(ids).size).toBe(2);
  });

  it("checks a closed source file via the supplied vault reader", async () => {
    const read = vi.fn(async () => "原文件中已没有该事项");
    const { editor, clipboard } = fixture(read);
    const source = editor("Daymark/A.md", `- [ ] 计划 ${id(1)}`);
    const target = editor("Daymark/B.md", "");
    let content = "";
    await clipboard.copySubtree(source, true, async (text) => { content = text; });
    await clipboard.paste(target, content);
    expect(read).toHaveBeenCalledWith("Daymark/A.md");
    expect(scanIdentities(target.state.doc)[0]!.id).toBe(id(1));
  });

  it("preserves target content and clipboard receipt if source verification fails", async () => {
    const { editor, clipboard } = fixture(async () => { throw new Error("read failed"); });
    const source = editor("Daymark/A.md", `- [ ] 计划 ${id(1)}`);
    const target = editor("Daymark/B.md", "原文");
    let content = "";
    await clipboard.copySubtree(source, true, async (text) => { content = text; });
    await expect(clipboard.paste(target, content)).rejects.toThrow("read failed");
    expect(target.state.doc.toString()).toBe("原文");
    expect(content).toContain(id(1));
  });

  it("aborts a delayed paste if the target changes during verification", async () => {
    let resolve!: (text: string) => void;
    const read = new Promise<string>((done) => { resolve = done; });
    const { editor, clipboard } = fixture(async () => read);
    const source = editor("Daymark/A.md", `- [ ] 计划 ${id(1)}`);
    const target = editor("Daymark/B.md", "原文");
    let content = "";
    await clipboard.copySubtree(source, true, async (text) => { content = text; });
    const pending = clipboard.paste(target, content);
    target.dispatch({ changes: { from: 0, insert: "继续编辑" } });
    resolve("");
    await pending;
    expect(target.state.doc.toString()).toBe("继续编辑原文");
    expect(notices).toHaveBeenCalled();
  });

  it("does not cut if the subtree clipboard command fails", async () => {
    const { editor, clipboard } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const source = editor("Daymark/A.md", original);
    await clipboard.copySubtree(source, true, async () => { throw new Error("denied"); });
    expect(source.state.doc.toString()).toBe(original);
  });

  it("does not cut if editing continues during the asynchronous clipboard write", async () => {
    const { editor, clipboard } = fixture();
    const source = editor("Daymark/A.md", `- [ ] 计划 ${id(1)}`);
    await clipboard.copySubtree(source, true, async () => { source.dispatch({ changes: { from: 6, insert: "新" } }); });
    expect(source.state.doc.toString()).toBe(`- [ ] 新计划 ${id(1)}`);
    expect(notices).toHaveBeenCalled();
  });
});

describe("paste and subtree editing", () => {
  it("keeps read-only editors unchanged for cut, delete and paste", async () => {
    const { clipboard } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const view = new EditorView({ state: EditorState.create({
      doc: original, extensions: EditorState.readOnly.of(true),
    }) });
    views.push(view);
    const write = vi.fn(async () => {});
    await clipboard.copySubtree(view, true, write);
    clipboard.deleteSubtree(view);
    await clipboard.paste(view, `- [ ] 新事项 ${id(2)}`);
    expect(view.state.doc.toString()).toBe(original);
    expect(write).not.toHaveBeenCalled();
    await clipboard.copySubtree(view, false, write);
    expect(write).toHaveBeenCalled();
  });

  it("rekeys external task IDs and preserves the same generated IDs through undo/redo", async () => {
    const { editor, clipboard } = fixture();
    const target = editor("Daymark/B.md", "");
    await clipboard.paste(target, `- [ ] 外部复制 ${id(1)}\r\n`);
    const pasted = target.state.doc.toString();
    expect(pasted).not.toContain(id(1));
    expect(scanIdentities(target.state.doc)).toHaveLength(1);
    undo(target);
    expect(target.state.doc.length).toBe(0);
    redo(target);
    expect(target.state.doc.toString()).toBe(pasted);
  });

  it("blocks paste over a partially selected original ID", async () => {
    const { editor, clipboard } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const target = editor("Daymark/B.md", original);
    target.dispatch({ selection: EditorSelection.single(7, target.state.doc.length) });
    await clipboard.paste(target, "替换");
    expect(target.state.doc.toString()).toBe(original);
    expect(blocked).toHaveBeenCalled();
  });

  it("deletes a full subtree, preserves the next sibling and supports undo", () => {
    const { editor, clipboard } = fixture();
    const original = `- [ ] 父 ${id(1)}\n  - [ ] 子 ${id(2)}\n- [ ] 同级 ${id(3)}`;
    const source = editor("Daymark/A.md", original);
    clipboard.deleteSubtree(source);
    expect(source.state.doc.toString()).toBe(`- [ ] 同级 ${id(3)}`);
    undo(source);
    expect(source.state.doc.toString()).toBe(original);
  });

  it("rejects multiple cursor paste without losing the existing text", async () => {
    const { clipboard } = fixture();
    const view = new EditorView({ state: EditorState.create({
      doc: "正文",
      selection: EditorSelection.create([EditorSelection.cursor(0), EditorSelection.cursor(2)]),
      extensions: [EditorState.allowMultipleSelections.of(true)],
    }) });
    views.push(view);
    await clipboard.paste(view, `- [ ] 新 ${id(1)}`);
    expect(view.state.doc.toString()).toBe("正文");
    expect(notices).toHaveBeenCalled();
  });
});
