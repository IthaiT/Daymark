import {
  Annotation,
  ChangeSet,
  EditorSelection,
  EditorState,
  MapMode,
  Prec,
  StateField,
  Transaction,
  type ChangeSpec,
  type Extension,
  type TransactionSpec,
} from "@codemirror/state";
import { Decoration, EditorView, keymap, type DecorationSet } from "@codemirror/view";
import { indentation, newIdentity, scanIdentities, taskPrefix, type Identity } from "./identity";

// Only structural edits in this plugin receive this annotation.
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
  const removedCounts = new Map<string, number>();
  for (const span of before) {
    if ((afterCounts.get(span.id) ?? 0) >= beforeCounts.get(span.id)!) continue;
    let wholeLineRemoved = false;
    tr.changes.iterChanges((from, to, _newFrom, _newTo, inserted) => {
      if (from <= span.lineFrom && to >= span.lineTo &&
          (selectedWholeLine(tr, span) || (tr.isUserEvent("delete.line") && !inserted.length))) {
        wholeLineRemoved = true;
      }
    });
    if (wholeLineRemoved) removedCounts.set(span.id, (removedCounts.get(span.id) ?? 0) + 1);
  }
  for (const [id, count] of beforeCounts) {
    if ((afterCounts.get(id) ?? 0) + (removedCounts.get(id) ?? 0) < count) return false;
  }
  return true;
}

function taskSplit(state: EditorState, options: GuardOptions): TransactionSpec | undefined {
  if (!options.enabled(state) || state.readOnly || state.selection.ranges.length !== 1) return undefined;
  const selection = state.selection.main;
  const span = scanIdentities(state.doc).find(
    (item) => selection.from >= item.bodyFrom && selection.to <= item.from,
  );
  if (!span) return undefined;
  const line = state.doc.lineAt(span.lineFrom);
  const prefix = taskPrefix.exec(line.text)!;
  const body = state.doc.sliceString(span.bodyFrom, span.from);
  if (!body.trim()) {
    return {
      changes: { from: line.from, to: line.to, insert: prefix[1]! },
      selection: { anchor: line.from + prefix[1]!.length },
      annotations: [structuralEdit.of(true), Transaction.userEvent.of("input")],
    };
  }
  const left = state.doc.sliceString(span.bodyFrom, selection.from).trimEnd();
  const right = state.doc.sliceString(selection.to, span.from).trimStart();
  const nextId = (options.nextId ?? newIdentity)();
  const marker = /^\d/.test(prefix[2]!)
    ? `${Number.parseInt(prefix[2]!, 10) + 1}${prefix[2]!.slice(-1)}` : prefix[2]!;
  // Enter at the beginning inserts a new task before the original task.
  const originalOnRight = !left && !!right && selection.from === span.bodyFrom;
  const nextPrefix = `${prefix[1]}${marker} [${originalOnRight ? prefix[3] : " "}] `;
  const firstPrefix = originalOnRight ? prefix[0].replace(/\[[ /xX-]\]/, "[ ]") : prefix[0];
  const first = `${firstPrefix}${left} ${originalOnRight ? nextId : span.id}`;
  const second = `${nextPrefix}${right} ${originalOnRight ? span.id : nextId}`;
  let subtreeTo = line.to;
  if (!originalOnRight) {
    const level = indentation(line.text);
    for (let n = line.number + 1; n <= state.doc.lines; n++) {
      const child = state.doc.line(n);
      if (child.text.trim() && indentation(child.text) <= level) break;
      if (child.text.trim()) subtreeTo = child.to;
    }
  }
  // A new sibling belongs after the existing subtree, or the old children would
  // silently become children of the newly inserted task on the next sync.
  const changes = subtreeTo === line.to
    ? [{ from: line.from, to: line.to, insert: `${first}\n${second}` }]
    : [
        { from: line.from, to: line.to, insert: first },
        { from: subtreeTo, insert: `\n${second}` },
      ];
  return {
    changes,
    selection: { anchor: subtreeTo + first.length - line.length + 1 + nextPrefix.length },
    annotations: [structuralEdit.of(true), Transaction.userEvent.of("input")],
  };
}

export function splitTask(view: EditorView, options: GuardOptions): boolean {
  if (view.composing) return false;
  const split = taskSplit(view.state, options);
  if (!split) return false;
  view.dispatch(split);
  return true;
}

/** Recognize an Enter result even when the host replaces a complete row. */
function isSimpleTaskBreak(tr: Transaction, before: readonly Identity[]): boolean {
  if (!tr.docChanged || tr.startState.selection.ranges.length !== 1 ||
      tr.isUserEvent("input.paste") || tr.isUserEvent("input.drop") ||
      tr.isUserEvent("input.type.compose") || tr.isUserEvent("move") || tr.isUserEvent("delete")) return false;
  const range = tr.startState.selection.main;
  if (!before.some((span) => range.from >= span.bodyFrom && range.to <= span.from)) return false;
  const suffixLength = tr.startState.doc.length - range.to;
  const end = tr.newDoc.length - suffixLength;
  if (end <= range.from ||
      !tr.startState.doc.slice(0, range.from).eq(tr.newDoc.slice(0, range.from)) ||
      !tr.startState.doc.slice(range.to).eq(tr.newDoc.slice(end))) return false;
  const inserted = tr.newDoc.sliceString(range.from, end);
  return /^[ \t]*\n[ \t]*(?:(?:[-+*]|\d+[.)])[ \t]+(?:\[[ /xX-]\][ \t]*)?)?$/.test(inserted);
}

type IdentityEdit = Pick<Transaction, "startState" | "changes" | "newDoc">;

/** A coarse rewrite is safe in place only if it preserves the row boundaries. */
function sameRewrittenRow(tr: IdentityEdit, span: Identity, candidate: Identity): boolean {
  let line = tr.startState.doc.lineAt(span.lineFrom).number;
  let safe = true;
  tr.changes.iterChanges((from, to, _newFrom, _newTo, inserted) => {
    const delta = inserted.lines - tr.startState.doc.slice(from, to).lines;
    if (to <= span.lineFrom) line += delta;
    else if (from <= span.lineTo && delta !== 0) safe = false;
  });
  return safe && tr.newDoc.lineAt(candidate.lineFrom).number === line;
}

/** Every old occurrence needs its own proof of ownership, including coarse rewrites. */
function detachedIdentity(
  tr: Transaction, before: readonly Identity[], after: readonly Identity[], edit: IdentityEdit,
): boolean {
  const gaps: { from: number; mapped: number; length: number }[] = [];
  edit.changes.iterGaps((from, mapped, length) => { gaps.push({ from, mapped, length }); });
  const claimed = new Set<Identity>();
  const retained = new Map<Identity, Identity>();
  // Reserve retained tokens first. Another occurrence with the same ID must
  // never borrow this occurrence as proof that its own body is still attached.
  for (const span of before) {
    const tokenFrom = span.from + tr.startState.doc.sliceString(span.from, span.to).indexOf(span.id);
    const token = edit.changes.mapPos(tokenFrom, 1, MapMode.TrackAfter);
    const candidate = token === null ? undefined : after.find((candidate) => candidate.id === span.id &&
      candidate.from + edit.newDoc.sliceString(candidate.from, candidate.to).indexOf(candidate.id) === token);
    if (candidate) {
      retained.set(span, candidate);
      claimed.add(candidate);
    }
  }
  for (const span of before) {
    const rows = new Set<number>();
    // Check all retained visible fragments, including the checkbox. Looking at
    // only bodyFrom loses the proof as soon as its first character is replaced.
    for (const gap of gaps) {
      const from = Math.max(span.lineFrom, gap.from);
      if (from < Math.min(span.from, gap.from + gap.length)) {
        rows.add(edit.newDoc.lineAt(gap.mapped + from - gap.from).from);
      }
    }
    const candidates = retained.has(span) ? [retained.get(span)!]
      : after.filter((candidate) => candidate.id === span.id && !claimed.has(candidate));
    const owner = candidates.find((candidate) => {
      if (rows.size) return rows.size === 1 && rows.has(candidate.lineFrom);
      // With all anchors replaced, accept an unchanged complete row (native
      // moves), or a rewrite that keeps the same row and newline boundaries.
      return tr.startState.doc.sliceString(span.lineFrom, span.lineTo) ===
        edit.newDoc.sliceString(candidate.lineFrom, candidate.lineTo) || sameRewrittenRow(edit, span, candidate);
    });
    if (owner) {
      claimed.add(owner);
      continue;
    }
    let deleted = false;
    const fewerOccurrences = after.filter((item) => item.id === span.id).length <
      before.filter((item) => item.id === span.id).length;
    tr.changes.iterChanges((from, to, _newFrom, _newTo, inserted) => {
      if (from <= span.lineFrom && to >= span.lineTo &&
          ((selectedWholeLine(tr, span) && (!inserted.length || fewerOccurrences)) ||
            (tr.isUserEvent("delete.line") && !inserted.length))) deleted = true;
    });
    if (!deleted) return true;
  }
  return false;
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
    Prec.highest(EditorState.transactionFilter.of((tr) => {
      if (!options.enabled(tr.startState)) return tr;
      const before = tr.startState.field(identities);
      // History must restore exact source text and identities.
      const trusted = tr.annotation(structuralEdit) || tr.isUserEvent("undo") || tr.isUserEvent("redo");
      if (!trusted && isSimpleTaskBreak(tr, before)) {
        const split = taskSplit(tr.startState, options);
        if (split) {
          // Compose a correction before the transaction reaches the document.
          // Keep host annotations/effects and make Enter one undoable change.
          const safeChanges = tr.startState.changes(split.changes);
          const correction = tr.changes.invert(tr.startState.doc).compose(safeChanges);
          return [tr, {
            changes: correction,
            selection: split.selection,
            annotations: split.annotations,
            sequential: true,
          }];
        }
      }
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
      if (tr.docChanged && !trusted && (!protectsIdentities(tr, before, after) ||
          detachedIdentity(tr, before, after, {
            startState: tr.startState, changes: tr.changes.compose(correction), newDoc: correctedDoc,
          }))) {
        options.blocked();
        return [];
      }
      const selection = safeSelection(tr.newSelection.map(correction, -1), after);
      return correction.empty && selection.eq(tr.newSelection)
        ? tr : [tr, { changes: correction, selection, sequential: true }];
    })),
    // Keymap priority alone cannot win against another host keymap. Handle
    // ordinary Enter before CM's keymap dispatcher, using its public DOM API.
    Prec.highest(EditorView.domEventHandlers({
      keydown(event, view) {
        if (event.key !== "Enter" || event.shiftKey || event.ctrlKey || event.altKey || event.metaKey ||
            event.isComposing || event.keyCode === 229) return false;
        return splitTask(view, options);
      },
    })),
    Prec.highest(keymap.of([
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
