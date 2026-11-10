import { Annotation, Compartment, EditorState, Prec, StateEffect } from "@codemirror/state";
import { history, redo, undo } from "@codemirror/commands";
import { EditorView, keymap } from "@codemirror/view";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createIdGuard } from "../src/guard";
import { scanIdentities } from "../src/identity";

const id = (n: number) => `^daymark-obsidian-00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const views: EditorView[] = [];
const blocked = vi.fn();

function fixture(hostFirst = true, sourceText?: string) {
  const compartment = new Compartment();
  const source = sourceText ?? `\t- [ ] 技术主管 ${id(1)}`;
  // A host DOM handler at the same highest precedence can still run first.
  // This forces the transaction backstop instead of only our Enter shortcut.
  const nativeEnter = Prec.highest(EditorView.domEventHandlers({
    keydown(event, view) {
      if (event.key !== "Enter") return false;
      const range = view.state.selection.main;
      view.dispatch({
        changes: { from: range.from, to: range.to, insert: "\n\t- [ ] " },
        selection: { anchor: range.from + "\n\t- [ ] ".length },
        userEvent: "input",
      });
      return true;
    },
  }));
  let next = 10;
  const guard = compartment.of(createIdGuard({ enabled: () => true, blocked, nextId: () => id(next++) }));
  const view = new EditorView({
    parent: document.body,
    state: EditorState.create({ doc: source, extensions: [history(), ...(hostFirst ? [nativeEnter, guard] : [guard, nativeEnter])] }),
  });
  views.push(view);
  view.dispatch({ selection: { anchor: scanIdentities(view.state.doc)[0]!.from } });
  return { view, compartment, source };
}

function pressEnter(view: EditorView): void {
  view.contentDOM.dispatchEvent(new KeyboardEvent("keydown", {
    key: "Enter", code: "Enter", keyCode: 13, bubbles: true, cancelable: true,
  }));
}

afterEach(() => {
  for (const view of views.splice(0)) view.destroy();
  blocked.mockClear();
});

describe("Enter dispatched by the host before the plugin shortcut", () => {
  it("handles Enter before even a highest-priority host keymap can bypass filters", () => {
    const { view, source } = fixture(false);
    const host = vi.fn(() => true);
    view.dispatch({ effects: StateEffect.appendConfig.of(Prec.highest(keymap.of([{ key: "Enter", run: host }]))) });
    pressEnter(view);
    expect(host).not.toHaveBeenCalled();
    expect(view.state.doc.line(1).text).toBe(source);
    expect(scanIdentities(view.state.doc)).toHaveLength(2);
  });

  it.each([false, true])("keeps the old ID on the original row after disable (host first: %s)", (hostFirst) => {
    const { view, compartment, source } = fixture(hostFirst);
    pressEnter(view);
    expect(view.state.doc.line(1).text).toBe(source);
    expect(scanIdentities(view.state.doc).map((span) => span.id)).toEqual([id(1), id(10)]);
    view.dispatch({ effects: compartment.reconfigure([]) });
    expect(view.state.doc.line(1).text).toBe(source);
    expect(view.contentDOM.textContent).toContain(id(1));
    expect(blocked).not.toHaveBeenCalled();
  });

  it("also protects an unannotated full-row replacement by a host command", () => {
    const { view, source } = fixture();
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: `\t- [ ] 技术主管\n\t- [ ]  ${id(1)}` },
    });
    expect(view.state.doc.line(1).text).toBe(source);
    expect(scanIdentities(view.state.doc)[1]!.id).toBe(id(10));
  });

  it.each(["", " ", "  ", "\t", " \t "])("handles repeated whole-row Enter rewrites with padding %j", (padding) => {
    const { view, compartment, source } = fixture();
    for (let n = 0; n < 30; n++) {
      // End may be the physical source end, beyond the invisible suffix.
      view.dispatch({ selection: { anchor: view.state.doc.line(1).to } });
      view.dispatch({ changes: {
        from: 0, to: view.state.doc.line(1).to,
        insert: `\t- [ ] 技术主管${padding}\n\t- [ ]  ${id(1)}`,
      }, userEvent: "input" });
      expect(view.state.doc.line(1).text).toBe(source);
      expect(scanIdentities(view.state.doc).filter((span) => span.id === id(1))).toHaveLength(1);
      expect(scanIdentities(view.state.doc)).toHaveLength(n + 2);
    }
    view.dispatch({ effects: compartment.reconfigure([]) });
    expect(view.state.doc.line(1).text).toBe(source);
    expect(blocked).not.toHaveBeenCalled();
  });

  it.each([false, true])("survives repeated End, typing and Enter key events (host first: %s)", (hostFirst) => {
    const { view, compartment, source } = fixture(hostFirst);
    for (let n = 0; n < 30; n++) {
      const last = scanIdentities(view.state.doc).at(-1)!;
      view.dispatch({ selection: { anchor: last.to } });
      const head = view.state.selection.main.head;
      view.dispatch({ changes: { from: head, insert: "补充" }, selection: { anchor: head + 2 }, userEvent: "input.type" });
      pressEnter(view);
      expect(view.state.doc.line(1).text).toBe(source.replace(` ${id(1)}`, `补充 ${id(1)}`));
      const spans = scanIdentities(view.state.doc);
      expect(spans).toHaveLength(n + 2);
      expect(new Set(spans.map((span) => span.id)).size).toBe(spans.length);
      expect(spans.slice(0, -1).every((span) => view.state.doc.sliceString(span.bodyFrom, span.from).trim())).toBe(true);
    }
    const result = view.state.doc.toString();
    undo(view);
    redo(view);
    expect(view.state.doc.toString()).toBe(result);
    view.dispatch({ effects: compartment.reconfigure([]) });
    expect(view.state.doc.line(1).text).toContain(`补充 ${id(1)}`);
    expect(blocked).not.toHaveBeenCalled();
  });

  it.each([false, true])("keeps the original task intact when Enter repeatedly exits empty tasks (host first: %s)", (hostFirst) => {
    const { view, source } = fixture(hostFirst);
    for (let n = 0; n < 30; n++) {
      pressEnter(view);
      expect(view.state.doc.line(1).text).toBe(source);
    }
    expect(scanIdentities(view.state.doc).map((span) => span.id)).toEqual([id(1)]);
    expect(blocked).not.toHaveBeenCalled();
  });

  it.each(["input", "input.type.compose", "input.paste", undefined])("rejects ambiguous complete rewrites with event %s", (userEvent) => {
    const { view, source } = fixture();
    view.dispatch({ changes: {
      from: 0, to: view.state.doc.length,
      insert: `\t- [ ] 技术主管\n\t- [ ]  ${id(1)}\n附带修改`,
    }, userEvent });
    expect(view.state.doc.toString()).toBe(source);
    expect(blocked).toHaveBeenCalledOnce();
  });

  it("rejects a deleted body anchor when the retained checkbox and title would lose their ID", () => {
    const { view, source } = fixture();
    const span = scanIdentities(view.state.doc)[0]!;
    view.dispatch({ changes: { from: span.bodyFrom, to: span.bodyFrom + 1, insert: "技\n\t- [ ] " }, userEvent: "input.paste" });
    expect(view.state.doc.toString()).toBe(source);
    expect(blocked).toHaveBeenCalledOnce();
  });

  it("does not use an unchanged shared occurrence as proof for a detached occurrence", () => {
    const row = `\t- [ ] 技术主管 ${id(1)}`;
    const { view } = fixture(true, `${row}\n${row}`);
    view.dispatch({ changes: { from: 0, to: row.length, insert: `\t- [ ] 技术主管\n\t- [ ]  ${id(1)}\n额外修改` } });
    expect(view.state.doc.toString()).toBe(`${row}\n${row}`);
    expect(blocked).toHaveBeenCalledOnce();
  });

  it("undoes and redoes the corrected host Enter without reallocating IDs", () => {
    const { view, source } = fixture();
    pressEnter(view);
    const split = view.state.doc.toString();
    undo(view);
    expect(view.state.doc.toString()).toBe(source);
    redo(view);
    expect(view.state.doc.toString()).toBe(split);
    expect(view.state.doc.line(1).text).toBe(source);
  });

  it("preserves the parent's children when native Enter would insert before them", () => {
    const first = `\t- [ ] 技术主管 ${id(1)}`;
    const child = `\t\t- [ ] 子事项 ${id(2)}`;
    const sibling = `\t- [ ] 下一条 ${id(3)}`;
    const { view } = fixture(true, `${first}\n${child}\n${sibling}`);
    pressEnter(view);
    expect(view.state.doc.toString()).toBe(`${first}\n${child}\n\t- [ ]  ${id(10)}\n${sibling}`);
    const head = view.state.selection.main.head;
    view.dispatch({ changes: { from: head, insert: "新事项" }, selection: { anchor: head + 3 } });
    expect(view.state.doc.line(3).text).toBe(`\t- [ ] 新事项 ${id(10)}`);
  });

  it("preserves the particular occurrence when a shared ID occurs more than once", () => {
    const row = `\t- [ ] 技术主管 ${id(1)}`;
    const { view } = fixture(true, `${row}\n${row}`);
    const second = scanIdentities(view.state.doc)[1]!;
    view.dispatch({ selection: { anchor: second.from } });
    pressEnter(view);
    expect(view.state.doc.line(1).text).toBe(row);
    expect(view.state.doc.line(2).text).toBe(row);
    expect(scanIdentities(view.state.doc).map((span) => span.id)).toEqual([id(1), id(1), id(10)]);
  });

  it("safely handles a bare native line break before the hidden suffix", () => {
    const { view, source } = fixture();
    const head = view.state.selection.main.head;
    view.dispatch({ changes: { from: head, insert: "\n" }, userEvent: "input" });
    expect(view.state.doc.line(1).text).toBe(source);
    expect(view.state.doc.line(2).text).toBe(`\t- [ ]  ${id(10)}`);
  });

  it("keeps a suffix attached when Enter replaces a selected title tail", () => {
    const { view } = fixture();
    const head = view.state.selection.main.head;
    view.dispatch({ selection: { anchor: head - 2, head } });
    pressEnter(view);
    expect(view.state.doc.line(1).text).toBe(`\t- [ ] 技术 ${id(1)}`);
    expect(view.state.doc.line(2).text).toBe(`\t- [ ]  ${id(10)}`);
  });

  it("handles a middle split with the same ownership rules as the plugin shortcut", () => {
    const { view } = fixture();
    view.dispatch({ selection: { anchor: view.state.selection.main.head - 2 } });
    pressEnter(view);
    expect(view.state.doc.line(1).text).toBe(`\t- [ ] 技术 ${id(1)}`);
    expect(view.state.doc.line(2).text).toBe(`\t- [ ] 主管 ${id(10)}`);
  });

  it("keeps the original title, status and ID together when Enter is at the beginning", () => {
    const original = `\t- [x] 技术主管 ${id(1)}`;
    const { view } = fixture(true, original);
    view.dispatch({ selection: { anchor: scanIdentities(view.state.doc)[0]!.bodyFrom } });
    pressEnter(view);
    expect(view.state.doc.line(1).text).toBe(`\t- [ ]  ${id(10)}`);
    expect(view.state.doc.line(2).text).toBe(original);
  });

  it("blocks multiline paste that would detach a retained ID instead of treating paste as Enter", () => {
    const { view, source } = fixture();
    const head = view.state.selection.main.head;
    view.dispatch({ changes: { from: head, insert: "\n\t- [ ] " }, userEvent: "input.paste" });
    expect(view.state.doc.toString()).toBe(source);
    expect(blocked).toHaveBeenCalledOnce();
  });

  it("rejects an ambiguous compound edit instead of moving the suffix to an unrelated task", () => {
    const original = `\t- [ ] 技术主管 ${id(1)}\n说明`;
    const { view } = fixture(true, original);
    const head = view.state.selection.main.head;
    view.dispatch({
      changes: [{ from: head, insert: "\n\t- [ ] " }, { from: view.state.doc.length, insert: "额外修改" }],
      userEvent: "input",
    });
    expect(view.state.doc.toString()).toBe(original);
    expect(blocked).toHaveBeenCalledOnce();
  });

  it("keeps host annotations and effects when correcting the line split", () => {
    const { view, source } = fixture();
    const marker = Annotation.define<string>();
    const effect = StateEffect.define<string>();
    let annotation: string | undefined;
    let effectValue: string | undefined;
    view.dispatch({ effects: StateEffect.appendConfig.of(EditorState.transactionExtender.of((tr) => {
      if (tr.docChanged) {
        annotation = tr.annotation(marker);
        effectValue = tr.effects.find((value) => value.is(effect))?.value;
      }
      return null;
    })) });
    const head = view.state.selection.main.head;
    view.dispatch({ changes: { from: head, insert: "\n\t- [ ] " }, annotations: marker.of("host"), effects: effect.of("metadata") });
    expect(view.state.doc.line(1).text).toBe(source);
    expect(annotation).toBe("host");
    expect(effectValue).toBe("metadata");
  });
});
