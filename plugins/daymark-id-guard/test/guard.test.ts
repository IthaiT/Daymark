import { EditorSelection, EditorState } from "@codemirror/state";
import { deleteCharBackward, deleteCharForward, deleteLine, history, indentMore, moveLineDown, redo, undo } from "@codemirror/commands";
import { EditorView } from "@codemirror/view";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createIdGuard, splitTask } from "../src/guard";
import { scanIdentities } from "../src/identity";

const id = (n: number) => `^daymark-obsidian-00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const views: EditorView[] = [];
const blocked = vi.fn();
const options = { enabled: () => true, blocked, nextId: () => id(10) };
function editor(doc: string, enabled = true): EditorView {
  const view = new EditorView({
    parent: document.body,
    state: EditorState.create({ doc, extensions: [history(), createIdGuard({ ...options, enabled: () => enabled })] }),
  });
  views.push(view);
  return view;
}
afterEach(() => { for (const view of views.splice(0)) view.destroy(); blocked.mockClear(); });

describe("editor identity protection", () => {
  it("replaces IDs in the DOM without changing source or exposing them on the active line", () => {
    const source = `- [ ] 计划 ${id(1)}`;
    const view = editor(source);
    view.dispatch({ selection: { anchor: 7 } });
    expect(view.contentDOM.textContent).toContain("计划");
    expect(view.contentDOM.textContent).not.toContain("daymark-obsidian");
    expect(view.state.doc.toString()).toBe(source);
  });

  it("leaves other folders/unlocked editors fully editable", () => {
    const view = editor(`- [ ] 计划 ${id(1)}`, false);
    expect(view.contentDOM.textContent).toContain(id(1));
    view.dispatch({ changes: { from: 8, to: view.state.doc.length } });
    expect(view.state.doc.toString()).toBe("- [ ] 计划");
  });

  it("allows Chinese composition, status, description and indentation edits", () => {
    const view = editor(`- [ ] 计划 ${id(1)}`);
    view.dispatch({ changes: { from: 6, to: 8, insert: "修改中文 | 描述 | 结果" }, userEvent: "input.type.compose" });
    view.dispatch({ changes: { from: 3, to: 4, insert: "x" } });
    indentMore(view);
    expect(view.state.doc.toString()).toContain(`- [x] 修改中文 | 描述 | 结果 ${id(1)}`);
    expect(blocked).not.toHaveBeenCalled();
  });

  it("blocks a single ID character edit, partial replacement and atomic deletion", () => {
    const source = `- [ ] 计划 ${id(1)}`;
    const view = editor(source);
    const span = scanIdentities(view.state.doc)[0]!;
    view.dispatch({ changes: { from: span.from + 4, to: span.from + 5, insert: "z" } });
    view.dispatch({ changes: { from: span.from - 1, to: span.to, insert: "新的文字" } });
    view.dispatch({ selection: { anchor: span.from } });
    deleteCharForward(view);
    expect(view.state.doc.toString()).toBe(source);
    expect(blocked).toHaveBeenCalledTimes(3);
  });

  it("normalizes physical End to the visible text end before typing", () => {
    const view = editor(`- [ ] 计划 ${id(1)}`);
    view.dispatch({ selection: { anchor: view.state.doc.length } });
    expect(view.state.selection.main.head).toBe(8);
    const head = view.state.selection.main.head;
    view.dispatch({ changes: { from: head, insert: "更新" } });
    expect(view.state.doc.toString()).toBe(`- [ ] 计划更新 ${id(1)}`);
  });

  it("Backspace at the visible end removes body text, not the ID", () => {
    const view = editor(`- [ ] 计划 ${id(1)}`);
    view.dispatch({ selection: { anchor: 8 } });
    deleteCharBackward(view);
    expect(view.state.doc.toString()).toBe(`- [ ] 计 ${id(1)}`);
  });

  it("preserves task syntax when composing in an empty task with a single separator", () => {
    const source = `- [ ] ${id(1)}`;
    const view = editor(source);
    view.dispatch({ selection: { anchor: 6 } });
    view.dispatch({ changes: { from: 6, insert: "中" }, selection: { anchor: 7 }, userEvent: "input.type.compose" });
    expect(view.state.doc.toString()).toBe(`- [ ] 中 ${id(1)}`);
    expect(view.state.selection.main.head).toBe(7);
    view.dispatch({ changes: { from: 6, to: 7, insert: "中文" }, userEvent: "input.type.compose" });
    expect(view.state.doc.toString()).toBe(`- [ ] 中文 ${id(1)}`);
    undo(view);
    expect(view.state.doc.toString()).toBe(source);
    redo(view);
    expect(view.state.doc.toString()).toBe(`- [ ] 中文 ${id(1)}`);
  });

  it("allows whole-row deletion, and history restores its original identity", () => {
    const source = `- [ ] 计划 ${id(1)}\n- [ ] 保留 ${id(2)}`;
    const view = editor(source);
    deleteLine(view);
    expect(view.state.doc.toString()).toBe(`- [ ] 保留 ${id(2)}`);
    expect(undo(view)).toBe(true);
    expect(view.state.doc.toString()).toBe(source);
    expect(redo(view)).toBe(true);
    expect(view.state.doc.toString()).toBe(`- [ ] 保留 ${id(2)}`);
  });

  it("allows selecting and deleting complete source rows", () => {
    const view = editor(`- [ ] 计划 ${id(1)}`);
    view.dispatch({ selection: EditorSelection.single(0, view.state.doc.length) });
    view.dispatch({ changes: { from: 0, to: view.state.doc.length }, userEvent: "delete.selection" });
    expect(view.state.doc.length).toBe(0);
  });

  it("blocks a multiline edit that would erase a partially selected identity", () => {
    const source = `- [ ] 计划 ${id(1)}\n- [ ] 第二条 ${id(2)}`;
    const view = editor(source);
    const end = view.state.doc.line(2).from + 7;
    view.dispatch({ selection: EditorSelection.single(7, end) });
    view.dispatch({ changes: { from: 7, to: end, insert: "替换" } });
    expect(view.state.doc.toString()).toBe(source);
  });

  it("allows native line moves and identity-preserving copies for Daymark to validate", () => {
    const view = editor(`- [ ] 一 ${id(1)}\n- [ ] 二 ${id(2)}`);
    moveLineDown(view);
    expect(scanIdentities(view.state.doc).map((span) => span.id)).toEqual([id(2), id(1)]);
    const before = view.state.doc.toString();
    view.dispatch({ changes: { from: 0, insert: `- [ ] 副本 ${id(1)}\n` } });
    expect(view.state.doc.toString()).toBe(`- [ ] 副本 ${id(1)}\n${before}`);
  });

  it("preserves the body and ID when a plugin replaces the complete document", () => {
    const view = editor(`- [ ] 计划 ${id(1)}`);
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: `- [x] 计划 ✅ 2026-11-10 ${id(1)}` } });
    expect(view.state.doc.toString()).toContain("[x]");
    expect(blocked).not.toHaveBeenCalled();
  });
});

describe("task Enter semantics", () => {
  it("creates a sibling at the visible end and supports exact undo/redo", () => {
    const source = `- [ ] 计划 ${id(1)}`;
    const view = editor(source);
    view.dispatch({ selection: { anchor: 8 } });
    expect(splitTask(view, options)).toBe(true);
    const result = `- [ ] 计划 ${id(1)}\n- [ ]  ${id(10)}`;
    expect(view.state.doc.toString()).toBe(result);
    expect(view.contentDOM.textContent).not.toContain("daymark-obsidian");
    undo(view);
    expect(view.state.doc.toString()).toBe(source);
    redo(view);
    expect(view.state.doc.toString()).toBe(result);
  });

  it("retains the original identity on the right when inserting before the title", () => {
    const view = editor(`- [x] 计划 ${id(1)}`);
    view.dispatch({ selection: { anchor: 6 } });
    splitTask(view, options);
    expect(view.state.doc.toString()).toBe(`- [ ]  ${id(10)}\n- [x] 计划 ${id(1)}`);
  });

  it("keeps a checkbox separator when typing into the newly created empty task", () => {
    const view = editor(`- [ ] 计划 ${id(1)}`);
    view.dispatch({ selection: { anchor: 8 } });
    splitTask(view, options);
    const head = view.state.selection.main.head;
    view.dispatch({ changes: { from: head, insert: "新事项" } });
    expect(view.state.doc.line(2).text).toBe(`- [ ] 新事项 ${id(10)}`);
  });

  it("splits body text and advances ordered list numbering", () => {
    const view = editor(`  9. [x] 计划正文 ${id(1)}`);
    view.dispatch({ selection: { anchor: 11 } });
    splitTask(view, options);
    expect(view.state.doc.toString()).toBe(`  9. [x] 计划 ${id(1)}\n  10. [ ] 正文 ${id(10)}`);
  });

  it("inserts a sibling after the original subtree so children retain their parent", () => {
    const original = `- [ ] 父事项 ${id(1)}\n  - [ ] 子事项 ${id(2)}\n- [ ] 同级 ${id(3)}`;
    const view = editor(original);
    view.dispatch({ selection: { anchor: 9 } });
    splitTask(view, options);
    expect(view.state.doc.toString()).toBe(
      `- [ ] 父事项 ${id(1)}\n  - [ ] 子事项 ${id(2)}\n- [ ]  ${id(10)}\n- [ ] 同级 ${id(3)}`,
    );
    view.dispatch({ changes: { from: view.state.selection.main.head, insert: "新同级" } });
    expect(view.state.doc.line(3).text).toBe(`- [ ] 新同级 ${id(10)}`);
    undo(view);
    undo(view);
    expect(view.state.doc.toString()).toBe(original);
  });

  it("exits an empty task without leaving an orphan ID", () => {
    const view = editor(`  - [ ]  ${id(1)}`);
    view.dispatch({ selection: { anchor: 8 } });
    splitTask(view, options);
    expect(view.state.doc.toString()).toBe("  ");
  });

  it("leaves IME Enter to the input method", () => {
    const view = editor(`- [ ] 计划 ${id(1)}`);
    vi.spyOn(view, "composing", "get").mockReturnValue(true);
    expect(splitTask(view, options)).toBe(false);
  });

  it("does not split a read-only editor", () => {
    const source = `- [ ] 计划 ${id(1)}`;
    const view = new EditorView({ state: EditorState.create({
      doc: source, selection: { anchor: 8 }, extensions: EditorState.readOnly.of(true),
    }) });
    views.push(view);
    expect(splitTask(view, options)).toBe(false);
    expect(view.state.doc.toString()).toBe(source);
  });
});
