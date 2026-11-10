import { EditorSelection, EditorState } from "@codemirror/state";
import { history, redo, undo } from "@codemirror/commands";
import { EditorView } from "@codemirror/view";
import { afterEach, describe, expect, it, vi } from "vitest";
import { clipboardPlan, GuardClipboard } from "../src/clipboard";
import { createIdGuard } from "../src/guard";
import { scanIdentities } from "../src/identity";

const id = (n: number) => `^daymark-obsidian-00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const views: EditorView[] = [];
const notices = vi.fn();
const blocked = vi.fn();
function fixture() {
  const clipboard = new GuardClipboard({ enabled: () => true, notify: notices });
  function editor(doc: string, readOnly = false) {
    const view = new EditorView({
      parent: document.body,
      state: EditorState.create({
        doc,
        extensions: [EditorState.readOnly.of(readOnly), history(),
          createIdGuard({ enabled: () => true, blocked }), clipboard.extension()],
      }),
    });
    views.push(view);
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
});

describe("clipboard row boundaries", () => {
  it("includes the hidden suffix when selecting to the visible end", () => {
    const state = EditorState.create({ doc: `- [ ] 计划 ${id(1)}`, selection: EditorSelection.single(0, 8) });
    const plan = clipboardPlan(state)!;
    expect(plan.text).toBe(`- [ ] 计划 ${id(1)}\n`);
    expect(plan.to).toBe(state.doc.length);
    expect(plan.linewise).toBe(true);
  });

  it("does not copy a preceding row's separator when cutting the final row", () => {
    const state = EditorState.create({ doc: `正文\n- [ ] 最后 ${id(1)}`, selection: { anchor: 5 } });
    const plan = clipboardPlan(state)!;
    expect(plan.text).toBe(`- [ ] 最后 ${id(1)}\n`);
    expect(plan.from).toBe(2);
  });

  it.each(["cut", "copy"] as const)("%s carries every hidden ID in a multiline visible selection", (action) => {
    const { editor } = fixture();
    const rows = `- [ ] 准备面试 ${id(1)}\n  - [ ] 修改简历 ${id(2)}\n  - [ ] 练习面试 ${id(3)}\n    - [ ] 准备自我介绍 ${id(4)}`;
    const source = editor(`${rows}\n- [ ] 买菜 ${id(5)}`);
    const target = editor("目标正文");
    const last = scanIdentities(source.state.doc)[3]!;
    source.dispatch({ selection: EditorSelection.single(0, last.from) });
    const result = clipboardEvent(source, action);
    expect(result.prevented).toBe(true);
    expect(result.values.get("text/plain")).toBe(`${rows}\n`);
    clipboardEvent(target, "paste", result.values);
    expect(target.state.doc.toString()).toBe(`${rows}\n目标正文`);
    expect(scanIdentities(target.state.doc).map((span) => span.id)).toEqual([id(1), id(2), id(3), id(4)]);
    expect(source.state.doc.toString()).toBe(action === "cut" ? `\n- [ ] 买菜 ${id(5)}` : `${rows}\n- [ ] 买菜 ${id(5)}`);
    expect(blocked).not.toHaveBeenCalled();
  });

  it.each([false, true])("preserves nested IDs with reverse=%s selection ending at the next line start", (reverse) => {
    const { editor } = fixture();
    const rows = `  - [ ] 子事项 ${id(1)}\n\t- [ ] 下一条 ${id(2)}\n`;
    const source = editor(`前文\n${rows}后文`);
    const start = source.state.doc.line(2).from;
    const end = source.state.doc.line(4).from;
    source.dispatch({ selection: EditorSelection.single(reverse ? end : start, reverse ? start : end) });
    const cut = clipboardEvent(source, "cut");
    expect(cut.values.get("text/plain")).toBe(rows);
    expect(source.state.doc.toString()).toBe("前文\n后文");
  });

  it("cuts all selected final rows, without a trailing source newline, carrying their suffixes", () => {
    const { editor } = fixture();
    const rows = `- [ ] 一 ${id(1)}\n  - [ ] 二 ${id(2)}`;
    const source = editor(`前文\n${rows}`);
    source.dispatch({ selection: EditorSelection.single(source.state.doc.line(2).from, scanIdentities(source.state.doc)[1]!.from) });
    const cut = clipboardEvent(source, "cut");
    expect(cut.values.get("text/plain")).toBe(`${rows}\n`);
    expect(source.state.doc.toString()).toBe("前文");
  });
});

describe("clipboard identity preservation", () => {
  it.each(["cut", "copy"] as const)("unselected whole-row %s and paste preserve the exact ID", (action) => {
    const { editor } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const source = editor(original);
    const target = editor("");
    const copied = clipboardEvent(source, action);
    expect(copied.values.get("text/plain")).toBe(`${original}\n`);
    clipboardEvent(target, "paste", copied.values);
    expect(target.state.doc.toString()).toBe(`${original}\n`);
    expect(source.state.doc.toString()).toBe(action === "cut" ? "" : original);
  });

  it("keeps IDs on repeated and same-file paste; duplicate validation belongs to Daymark", () => {
    const { editor } = fixture();
    const view = editor(`- [ ] 计划 ${id(1)}`);
    const copy = clipboardEvent(view, "copy");
    clipboardEvent(view, "paste", copy.values);
    clipboardEvent(view, "paste", copy.values);
    expect(scanIdentities(view.state.doc).map((span) => span.id)).toEqual([id(1), id(1), id(1)]);
    expect(blocked).not.toHaveBeenCalled();
  });

  it("keeps a copied ID after the clipboard handler is recreated, even without custom MIME", () => {
    const sourceSession = fixture();
    const source = sourceSession.editor(`- [ ] 计划 ${id(1)}`);
    const copy = clipboardEvent(source, "copy");
    const targetSession = fixture();
    const target = targetSession.editor("");
    clipboardEvent(target, "paste", new Map([["text/plain", copy.values.get("text/plain")!]]));
    expect(scanIdentities(target.state.doc)[0]!.id).toBe(id(1));
  });

  it("keeps IDs when source cut is undone before pasting", () => {
    const { editor } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const source = editor(original);
    const target = editor("");
    const cut = clipboardEvent(source, "cut");
    undo(source);
    clipboardEvent(target, "paste", cut.values);
    expect(source.state.doc.toString()).toBe(original);
    expect(scanIdentities(target.state.doc)[0]!.id).toBe(id(1));
  });

  it("keeps IDs from external text and restores the exact paste on undo/redo", () => {
    const { editor, clipboard } = fixture();
    const target = editor("");
    clipboard.paste(target, `- [ ] 外部复制 ${id(1)}\r\n`);
    const pasted = `- [ ] 外部复制 ${id(1)}\n`;
    expect(target.state.doc.toString()).toBe(pasted);
    undo(target);
    expect(target.state.doc.length).toBe(0);
    redo(target);
    expect(target.state.doc.toString()).toBe(pasted);
  });

  it("does not add an ID to copied text which never had one", () => {
    const { editor, clipboard } = fixture();
    const view = editor("");
    clipboard.paste(view, "- [ ] 新事项\n");
    expect(view.state.doc.toString()).toBe("- [ ] 新事项\n");
    expect(scanIdentities(view.state.doc)).toHaveLength(0);
  });

  it("allows removing a same-file duplicate row without changing its surviving twin", () => {
    const { editor } = fixture();
    const row = `- [ ] 计划 ${id(1)}`;
    const view = editor(`${row}\n${row}`);
    const span = scanIdentities(view.state.doc)[0]!;
    view.dispatch({ selection: EditorSelection.single(span.lineFrom, span.lineTo) });
    view.dispatch({ changes: { from: span.lineFrom, to: span.lineTo + 1 }, userEvent: "delete.selection" });
    expect(view.state.doc.toString()).toBe(row);
    expect(blocked).not.toHaveBeenCalled();
    view.dispatch({ changes: { from: 10, to: 11, insert: "z" } });
    expect(view.state.doc.toString()).toBe(row);
    expect(blocked).toHaveBeenCalled();
  });
});

describe("partial selections and failure safety", () => {
  it("copies selected body text without exposing a hidden ID fragment", () => {
    const { editor } = fixture();
    const view = editor(`- [ ] 计划 ${id(1)}`);
    view.dispatch({ selection: EditorSelection.single(6, view.state.doc.length) });
    expect(clipboardEvent(view, "copy").values.get("text/plain")).toBe("计划");
  });

  it.each(["cut", "copy"] as const)("refuses a partial first task in multiline %s instead of silently dropping IDs", (action) => {
    const { editor } = fixture();
    const original = `- [ ] 计划 ${id(1)}\n- [ ] 第二条 ${id(2)}`;
    const view = editor(original);
    view.dispatch({ selection: EditorSelection.single(7, scanIdentities(view.state.doc)[1]!.from) });
    const result = clipboardEvent(view, action);
    expect(result.values.size).toBe(0);
    expect(view.state.doc.toString()).toBe(original);
    expect(notices).toHaveBeenCalled();
  });

  it("refuses a partial single-row cut through an ID", () => {
    const { editor } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const view = editor(original);
    view.dispatch({ selection: EditorSelection.single(7, view.state.doc.length) });
    expect(clipboardEvent(view, "cut").values.size).toBe(0);
    expect(view.state.doc.toString()).toBe(original);
  });

  it("does not erase a partially selected existing ID on paste", () => {
    const { editor, clipboard } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const target = editor(original);
    target.dispatch({ selection: EditorSelection.single(7, target.state.doc.length) });
    clipboard.paste(target, "替换");
    expect(target.state.doc.toString()).toBe(original);
    expect(blocked).toHaveBeenCalled();
  });

  it("keeps the source and selection if writing the clipboard fails", () => {
    const { editor } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const view = editor(original);
    const selection = view.state.selection;
    const event = new Event("cut", { bubbles: true, cancelable: true });
    Object.defineProperty(event, "clipboardData", { value: { setData() { throw new Error("clipboard unavailable"); } } });
    view.contentDOM.dispatchEvent(event);
    expect(view.state.doc.toString()).toBe(original);
    expect(view.state.selection.eq(selection)).toBe(true);
    expect(notices).toHaveBeenCalled();
  });

  it("allows copying from a read-only editor but never cuts or pastes into it", () => {
    const { editor, clipboard } = fixture();
    const original = `- [ ] 计划 ${id(1)}`;
    const view = editor(original, true);
    expect(clipboardEvent(view, "cut").values.size).toBe(0);
    clipboard.paste(view, `- [ ] 新 ${id(2)}`);
    expect(view.state.doc.toString()).toBe(original);
    expect(clipboardEvent(view, "copy").values.get("text/plain")).toBe(`${original}\n`);
  });

  it("rejects multiple cursor clipboard operations without editing content", () => {
    const { clipboard } = fixture();
    const view = new EditorView({ state: EditorState.create({
      doc: "正文", selection: EditorSelection.create([EditorSelection.cursor(0), EditorSelection.cursor(2)]),
      extensions: [EditorState.allowMultipleSelections.of(true), clipboard.extension()],
    }) });
    views.push(view);
    clipboard.paste(view, `- [ ] 新 ${id(1)}`);
    expect(clipboardEvent(view, "cut").values.size).toBe(0);
    expect(view.state.doc.toString()).toBe("正文");
    expect(notices).toHaveBeenCalled();
  });
});
