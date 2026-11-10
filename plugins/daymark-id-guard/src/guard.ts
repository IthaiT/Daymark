import {
  Annotation,
  ChangeSet,
  EditorSelection,
  EditorState,
  Prec,
  StateField,
  Transaction,
  type ChangeSpec,
  type Extension,
} from "@codemirror/state";
import { Decoration, EditorView, keymap, type DecorationSet } from "@codemirror/view";
import { newIdentity, scanIdentities, taskPrefix, type Identity } from "./identity";

// Only commands in this plugin receive this annotation; normal typing is filtered.
export const structuralEdit = Annotation.define<boolean>();

export interface GuardOptions {
  enabled(state: EditorState): boolean;
  blocked(): void;
  nextId?: () => string;
}

function safeSelection(selection: EditorSelection, spans: readonly Identity[]): EditorSelection {
  return EditorSelection.create(
    selection.ranges.map((range) => {
      if (!range.empty) return range;
      const span = spans.find((item) => range.head > item.from && range.head <= item.to);
      return span ? EditorSelection.cursor(span.from) : range;
    }),
    selection.mainIndex,
  );
}

function selectedWholeLine(tr: Transaction, span: Identity): boolean {
  return tr.startState.selection.ranges.some(
    (range) => !range.empty && range.from <= span.lineFrom && range.to >= span.lineTo,
  );
}

/** Reject identity loss before it enters the document or undo history. */
function protectsIdentities(tr: Transaction, before: readonly Identity[], after: readonly Identity[]): boolean {
  const beforeCounts = new Map<string, number>();
  const afterCounts = new Map<string, number>();
  for (const span of before) beforeCounts.set(span.id, (beforeCounts.get(span.id) ?? 0) + 1);
  for (const span of after) afterCounts.set(span.id, (afterCounts.get(span.id) ?? 0) + 1);
  for (const [id, count] of afterCounts) {
    if (count > Math.max(1, beforeCounts.get(id) ?? 0)) return false;
  }
  for (const span of before) {
    if (afterCounts.get(span.id) === beforeCounts.get(span.id)) continue;
    let wholeLineRemoved = false;
    tr.changes.iterChanges((from, to, _newFrom, _newTo, inserted) => {
      if (from <= span.lineFrom && to >= span.lineTo &&
          (selectedWholeLine(tr, span) || (tr.isUserEvent("delete.line") && !inserted.length))) {
        wholeLineRemoved = true;
      }
    });
    if (!wholeLineRemoved) return false;
  }
  return true;
}

export function splitTask(view: EditorView, options: GuardOptions): boolean {
  if (!options.enabled(view.state) || view.state.readOnly || view.composing ||
      view.state.selection.ranges.length !== 1) return false;
  const selection = view.state.selection.main;
  const span = scanIdentities(view.state.doc).find(
    (item) => selection.from >= item.bodyFrom && selection.to <= item.from,
  );
  if (!span) return false;
  const line = view.state.doc.lineAt(span.lineFrom);
  const prefix = taskPrefix.exec(line.text)!;
  const body = view.state.doc.sliceString(span.bodyFrom, span.from);
  if (!body.trim()) {
    view.dispatch({
      changes: { from: line.from, to: line.to, insert: prefix[1]! },
      selection: { anchor: line.from + prefix[1]!.length },
      annotations: [structuralEdit.of(true), Transaction.userEvent.of("input")],
    });
    return true;
  }
  const left = view.state.doc.sliceString(span.bodyFrom, selection.from).trimEnd();
  const right = view.state.doc.sliceString(selection.to, span.from).trimStart();
  const nextId = (options.nextId ?? newIdentity)();
  const marker = /^\d/.test(prefix[2]!)
    ? `${Number.parseInt(prefix[2]!, 10) + 1}${prefix[2]!.slice(-1)}` : prefix[2]!;
  // Enter at the beginning inserts a new task before the original task.
  const originalOnRight = !left && !!right && selection.from === span.bodyFrom;
  const nextPrefix = `${prefix[1]}${marker} [${originalOnRight ? prefix[3] : " "}] `;
  const firstPrefix = originalOnRight ? prefix[0].replace(/\[[ /xX-]\]/, "[ ]") : prefix[0];
  const first = `${firstPrefix}${left} ${originalOnRight ? nextId : span.id}`;
  const insert = `${first}\n${nextPrefix}${right} ${originalOnRight ? span.id : nextId}`;
  view.dispatch({
    changes: { from: line.from, to: line.to, insert },
    selection: { anchor: line.from + first.length + 1 + nextPrefix.length },
    annotations: [structuralEdit.of(true), Transaction.userEvent.of("input")],
  });
  return true;
}

export function createIdGuard(options: GuardOptions): Extension {
  const identities = StateField.define<readonly Identity[]>({
    create: (state) => scanIdentities(state.doc),
    update: (value, tr) => tr.docChanged ? scanIdentities(tr.newDoc) : value,
  });
  const hidden = StateField.define<DecorationSet>({
    create: (state) => decorations(state),
    update: (_value, tr) => decorations(tr.state),
    provide: (field) => [
      EditorView.decorations.from(field),
      EditorView.atomicRanges.of((view) => view.state.field(field)),
    ],
  });
  function decorations(state: EditorState): DecorationSet {
    if (!options.enabled(state)) return Decoration.none;
    return Decoration.set(state.field(identities).map(
      (span) => Decoration.replace({}).range(span.from, span.to),
    ));
  }
  return [
    identities,
    hidden,
    EditorState.transactionFilter.of((tr) => {
      if (!options.enabled(tr.startState)) return tr;
      const before = tr.startState.field(identities);
      // History must restore exact source text, including IDs generated on paste.
      const trusted = tr.annotation(structuralEdit) || tr.isUserEvent("undo") || tr.isUserEvent("redo");
      // A manually written empty task may have only the checkbox separator.
      // Typing before its ID needs a new separator, in the same undo transaction.
      const padding: ChangeSpec[] = [];
      tr.changes.iterChanges((from, to, _newFrom, newTo, inserted) => {
        if (!trusted && from === to && inserted.length && !inserted.toString().includes("\n") &&
            before.some((span) => span.from === from && span.bodyFrom === from &&
              tr.startState.doc.sliceString(from, from + 1) === "^")) {
          padding.push({ from: newTo, insert: " " });
        }
      });
      const correction = ChangeSet.of(padding, tr.newDoc.length);
      const correctedDoc = correction.empty ? tr.newDoc : correction.apply(tr.newDoc);
      const after = tr.docChanged ? scanIdentities(correctedDoc) : before;
      if (tr.docChanged && !trusted && !protectsIdentities(tr, before, after)) {
        options.blocked();
        return [];
      }
      const selection = safeSelection(tr.newSelection.map(correction, -1), after);
      return correction.empty && selection.eq(tr.newSelection)
        ? tr : [tr, { changes: correction, selection, sequential: true }];
    }),
    Prec.highest(keymap.of([
      { key: "Enter", run: (view) => splitTask(view, options) },
      {
        key: "ArrowRight",
        run(view) {
          if (!options.enabled(view.state) || !view.state.selection.main.empty ||
              view.state.selection.ranges.length !== 1) return false;
          const span = view.state.field(identities).find((item) => item.from === view.state.selection.main.head);
          if (!span) return false;
          view.dispatch({ selection: { anchor: Math.min(view.state.doc.length, span.to + 1) } });
          return true;
        },
      },
    ])),
  ];
}
