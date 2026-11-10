import { EditorState, Prec, Text, Transaction, type Extension } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { structuralEdit } from "./guard";
import { freshenIdentities, indentation, newIdentity, scanIdentities, taskPrefix } from "./identity";

const clipboardType = "application/x-daymark-id-guard";

interface ClipboardPlan {
  from: number;
  to: number;
  text: string;
  linewise: boolean;
}

interface Receipt {
  text: string;
  linewise: boolean;
  source: string;
  cut: boolean;
  consumed: boolean;
}

export interface ClipboardOptions {
  enabled(state: EditorState): boolean;
  path(state: EditorState): string;
  readSource(path: string): Promise<string | null>;
  notify(message: string): void;
  nextId?: () => string;
}

/** Expand complete visible rows to include their hidden source suffixes. */
export function clipboardPlan(state: EditorState, subtree = false): ClipboardPlan | null {
  if (state.selection.ranges.length !== 1) return null;
  const range = state.selection.main;
  const doc = state.doc;
  const line = doc.lineAt(range.from);
  let from = range.from;
  let to = range.to;
  let linewise = false;
  if (subtree || range.empty) {
    if (subtree && !taskPrefix.test(line.text)) return null;
    from = line.from;
    to = line.to;
    if (subtree) {
      const level = indentation(line.text);
      for (let n = line.number + 1; n <= doc.lines; n++) {
        const next = doc.line(n);
        if (next.text.trim() && indentation(next.text) <= level) break;
        to = next.to;
      }
    }
    if (to < doc.length) to++;
    linewise = true;
  } else {
    for (const span of scanIdentities(doc)) {
      if (from <= span.lineFrom && to >= span.from && to <= span.to) to = span.to;
    }
    const end = doc.lineAt(to);
    linewise = from === line.from && (to === end.to || to === end.from);
  }
  let text = doc.sliceString(from, to);
  if (linewise && !text.endsWith("\n")) text += "\n";
  // Cutting the final row also removes its preceding separator.
  if (linewise && to === doc.length && from > 0 && !doc.sliceString(from, to).endsWith("\n")) {
    from--;
  }
  return { from, to, text, linewise };
}

export class GuardClipboard {
  private receipt: Receipt | undefined;

  constructor(private readonly options: ClipboardOptions) {}

  extension(): Extension {
    return Prec.highest(EditorView.domEventHandlers({
      copy: (event, view) => this.handleCopy(event, view, false),
      cut: (event, view) => this.handleCopy(event, view, true),
      paste: (event, view) => {
        if (!this.options.enabled(view.state) || !event.clipboardData ||
            !event.clipboardData.types.includes("text/plain")) return false;
        const text = event.clipboardData.getData("text/plain");
        if (!text.includes("^daymark-obsidian-") &&
            this.receipt?.text !== text.replace(/\r\n?/g, "\n")) return false;
        const linewise = event.clipboardData.getData(clipboardType) === "lines-v1";
        event.preventDefault();
        void this.paste(view, text, linewise).catch(() => {
          this.options.notify("粘贴失败，原内容和剪贴板已保留，请重试。");
        });
        return true;
      },
      // Native text drag can silently duplicate an identity outside this editor.
      // Explicit row/subtree cut and paste has unambiguous move semantics.
      dragstart: (event, view) => {
        if (!this.options.enabled(view.state)) return false;
        const range = view.state.selection.main;
        if (!scanIdentities(view.state.doc).some((span) =>
          (range.from < span.to && range.to > span.from) ||
          (range.from <= span.lineFrom && range.to >= span.from))) {
          return false;
        }
        event.preventDefault();
        this.options.notify("移动事项请使用整行或子树剪切、粘贴，以保留事项关联。");
        return true;
      },
      drop: (event, view) => {
        if (!this.options.enabled(view.state) ||
            !event.dataTransfer?.getData("text/plain").includes("^daymark-obsidian-")) return false;
        event.preventDefault();
        this.options.notify("含事项 ID 的内容请使用粘贴，以区分复制和移动。");
        return true;
      },
    }));
  }

  private prepare(view: EditorView, cut: boolean, subtree: boolean): ClipboardPlan | null {
    if (!this.options.enabled(view.state)) return null;
    if (cut && view.state.readOnly) {
      this.options.notify("当前编辑器为只读，未执行剪切。");
      return null;
    }
    const plan = clipboardPlan(view.state, subtree);
    if (!plan) {
      this.options.notify("请使用单个选区，或将光标放在一个事项行内。");
      return null;
    }
    const spans = scanIdentities(view.state.doc);
    if (cut && spans.some((span) => plan.from < span.to && plan.to > span.from &&
        !(plan.from <= span.lineFrom && plan.to >= span.lineTo))) {
      this.options.notify("选区涉及隐藏 ID，请选择完整事项行或使用子树剪切。");
      return null;
    }
    if (!cut && !plan.linewise) {
      // Text-only selections never expose fragments of a hidden ID.
      let text = "";
      let position = plan.from;
      for (const span of spans) {
        if (span.to <= position || span.from >= plan.to) continue;
        text += view.state.doc.sliceString(position, Math.max(position, span.from));
        position = Math.min(plan.to, span.to);
      }
      plan.text = text + view.state.doc.sliceString(position, plan.to);
    } else if (!cut) {
      plan.text = freshenIdentities(plan.text, this.options.nextId ?? newIdentity);
    }
    return plan;
  }

  private finish(view: EditorView, plan: ClipboardPlan, cut: boolean): void {
    const source = this.options.path(view.state);
    if (cut) {
      view.dispatch({
        changes: { from: plan.from, to: plan.to },
        selection: { anchor: plan.from },
        annotations: [structuralEdit.of(true), Transaction.userEvent.of("delete.cut")],
      });
    }
    this.receipt = { text: plan.text, linewise: plan.linewise, source, cut, consumed: false };
  }

  private handleCopy(event: ClipboardEvent, view: EditorView, cut: boolean): boolean {
    if (!this.options.enabled(view.state) || !event.clipboardData) return false;
    event.preventDefault();
    const plan = this.prepare(view, cut, false);
    if (!plan) return true;
    try {
      event.clipboardData.setData("text/plain", plan.text);
      if (plan.linewise) event.clipboardData.setData(clipboardType, "lines-v1");
    } catch {
      this.options.notify("无法写入剪贴板，原事项已保留。");
      return true;
    }
    this.finish(view, plan, cut);
    return true;
  }

  /** Commands use the system clipboard; deletion happens only after a successful write. */
  async copySubtree(view: EditorView, cut: boolean, write: (text: string) => Promise<void>): Promise<void> {
    const state = view.state;
    const plan = this.prepare(view, cut, true);
    if (!plan) return;
    try {
      await write(plan.text);
      if (view.state.doc !== state.doc || !view.state.selection.eq(state.selection) ||
          this.options.path(view.state) !== this.options.path(state) || !this.options.enabled(view.state) ||
          (cut && view.state.readOnly)) {
        this.options.notify("复制期间内容或选区已变化，未执行剪切，请重试。");
        return;
      }
      this.finish(view, plan, cut);
    } catch {
      this.options.notify("无法写入剪贴板，原事项已保留。");
    }
  }

  deleteSubtree(view: EditorView): void {
    if (!this.options.enabled(view.state) || view.state.readOnly) return;
    const plan = clipboardPlan(view.state, true);
    if (!plan) return;
    view.dispatch({
      changes: { from: plan.from, to: plan.to },
      selection: { anchor: plan.from },
      annotations: [structuralEdit.of(true), Transaction.userEvent.of("delete")],
    });
  }

  /** A cut may reuse IDs once, and only if they are still absent from its source. */
  async paste(view: EditorView, input: string, linewiseHint = false): Promise<void> {
    if (!this.options.enabled(view.state) || view.state.readOnly) return;
    if (view.state.selection.ranges.length !== 1) {
      this.options.notify("事项粘贴暂不支持多个光标，请保留一个选区后重试。");
      return;
    }
    const state = view.state;
    const path = this.options.path(state);
    const text = input.replace(/\r\n?/g, "\n");
    const receipt = this.receipt?.text === text ? this.receipt : undefined;
    const ids = scanIdentities(Text.of(text.split("\n"))).map((span) => span.id);
    let moving = false;
    if (receipt?.cut && !receipt.consumed && ids.length) {
      const source = await this.options.readSource(receipt.source);
      const sourceIds = new Set(scanIdentities(Text.of((source ?? "").replace(/\r\n?/g, "\n").split("\n"))).map((span) => span.id));
      const targetIds = new Set(scanIdentities(view.state.doc).map((span) => span.id));
      moving = !receipt.consumed && this.receipt === receipt &&
        ids.every((id) => !sourceIds.has(id) && !targetIds.has(id));
    }
    if (view.state.doc !== state.doc || !view.state.selection.eq(state.selection) ||
        this.options.path(view.state) !== path || !this.options.enabled(view.state) || view.state.readOnly) {
      this.options.notify("粘贴期间内容或选区已变化，未写入，请重试。");
      return;
    }
    const inserted = moving ? text : freshenIdentities(text, this.options.nextId ?? newIdentity);
    const range = state.selection.main;
    const linewise = receipt?.linewise || linewiseHint;
    const from = range.empty && linewise ? state.doc.lineAt(range.from).from : range.from;
    const to = range.empty ? from : range.to;
    // Use the regular guard here: a paste must not erase an existing partial ID.
    view.dispatch({
      changes: { from, to, insert: inserted },
      selection: { anchor: from + inserted.length },
      annotations: Transaction.userEvent.of("input.paste"),
    });
    if (view.state.doc !== state.doc && receipt?.cut) receipt.consumed = true;
  }
}
