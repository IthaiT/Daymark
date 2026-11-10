import { EditorState, Prec, Transaction, type Extension } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { structuralEdit } from "./guard";
import { scanIdentities } from "./identity";

const clipboardType = "application/x-daymark-id-guard";

interface ClipboardPlan {
  from: number;
  to: number;
  text: string;
  linewise: boolean;
}

export interface ClipboardOptions {
  enabled(state: EditorState): boolean;
  notify(message: string): void;
}

/** Expand a complete visible last row to include its hidden suffix. */
export function clipboardPlan(state: EditorState): ClipboardPlan | null {
  if (state.selection.ranges.length !== 1) return null;
  const range = state.selection.main;
  const doc = state.doc;
  const line = doc.lineAt(range.from);
  let from = range.from;
  let to = range.to;
  let linewise = false;
  if (range.empty) {
    from = line.from;
    to = line.to < doc.length ? line.to + 1 : line.to;
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
  // The final row's preceding separator is removed, but not copied.
  if (linewise && to === doc.length && from > 0 && !doc.sliceString(from, to).endsWith("\n")) from--;
  return { from, to, text, linewise };
}

export class GuardClipboard {
  private lastCopy: { text: string; linewise: boolean } | undefined;

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
            this.lastCopy?.text !== text.replace(/\r\n?/g, "\n")) return false;
        event.preventDefault();
        this.paste(view, text, event.clipboardData.getData(clipboardType) === "lines-v1");
        return true;
      },
      dragstart: (event, view) => {
        if (!this.options.enabled(view.state)) return false;
        const range = view.state.selection.main;
        if (!scanIdentities(view.state.doc).some((span) =>
          (range.from < span.to && range.to > span.from) ||
          (range.from <= span.lineFrom && range.to >= span.from))) return false;
        event.preventDefault();
        this.options.notify("移动事项请选中完整行后剪切、粘贴，以完整携带隐藏 ID。");
        return true;
      },
      drop: (event, view) => {
        if (!this.options.enabled(view.state) ||
            !event.dataTransfer?.getData("text/plain").includes("^daymark-obsidian-")) return false;
        event.preventDefault();
        this.options.notify("含事项 ID 的内容请使用复制或剪切、粘贴。");
        return true;
      },
    }));
  }

  private handleCopy(event: ClipboardEvent, view: EditorView, cut: boolean): boolean {
    if (!this.options.enabled(view.state) || !event.clipboardData) return false;
    event.preventDefault();
    if (cut && view.state.readOnly) {
      this.options.notify("当前编辑器为只读，未执行剪切。");
      return true;
    }
    const plan = clipboardPlan(view.state);
    if (!plan) {
      this.options.notify("请保留一个连续选区后复制或剪切。");
      return true;
    }
    const partial = scanIdentities(view.state.doc).filter((span) =>
      plan.from < span.to && plan.to > span.from &&
      !(plan.from <= span.lineFrom && plan.to >= span.lineTo));
    if (partial.length && (cut || view.state.doc.lineAt(plan.from).number !== view.state.doc.lineAt(plan.to).number)) {
      this.options.notify("选区涉及部分隐藏 ID，请从第一行行首选到最后一行的可见行末后重试。");
      return true;
    }
    // Partial single-line selections are text copies; complete rows keep IDs.
    for (const span of partial.reverse()) {
      const start = Math.max(plan.from, span.from) - plan.from;
      const end = Math.min(plan.to, span.to) - plan.from;
      plan.text = plan.text.slice(0, start) + plan.text.slice(end);
    }
    try {
      event.clipboardData.setData("text/plain", plan.text);
      if (plan.linewise) event.clipboardData.setData(clipboardType, "lines-v1");
    } catch {
      this.options.notify("无法写入剪贴板，原事项已保留。");
      return true;
    }
    if (cut) {
      view.dispatch({
        changes: { from: plan.from, to: plan.to },
        selection: { anchor: plan.from },
        annotations: [structuralEdit.of(true), Transaction.userEvent.of("delete.cut")],
      });
    }
    this.lastCopy = { text: plan.text, linewise: plan.linewise };
    return true;
  }

  /** Clipboard operations preserve identity; Daymark validates shared nodes. */
  paste(view: EditorView, input: string, linewiseHint = false): void {
    if (!this.options.enabled(view.state) || view.state.readOnly) return;
    if (view.state.selection.ranges.length !== 1) {
      this.options.notify("事项粘贴暂不支持多个光标，请保留一个选区后重试。");
      return;
    }
    const text = input.replace(/\r\n?/g, "\n");
    const linewise = linewiseHint || (this.lastCopy?.text === text && this.lastCopy.linewise);
    const range = view.state.selection.main;
    const from = range.empty && linewise ? view.state.doc.lineAt(range.from).from : range.from;
    const to = range.empty ? from : range.to;
    // Existing partially selected IDs remain protected by the regular guard.
    view.dispatch({
      changes: { from, to, insert: text },
      selection: { anchor: from + text.length },
      annotations: Transaction.userEvent.of("input.paste"),
    });
  }
}
