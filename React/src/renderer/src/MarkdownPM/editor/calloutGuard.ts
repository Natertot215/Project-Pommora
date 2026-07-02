// Repairs deletes that touch a callout BODY line's hidden `> ` prefix, instead of cancelling them — a flat
// cancel made routine gestures (triple-click delete, Cmd+Backspace, drag-out) silently dead, since their
// changes legitimately start at the line start. Verdicts below encode which repair each case needs.
import { EditorState, Transaction, type Extension } from "@codemirror/state";
import { calloutLines } from "../detect";
import { calloutScan, docString } from "./docCache";

type Verdict =
  | { kind: "ok" }
  | { kind: "cancel" }
  | { kind: "clamp"; from: number }
  | { kind: "extend"; to: number };

export function calloutDeleteVerdict(
  doc: string,
  from: number,
  to: number,
  scan?: { lines: string[]; info: ReturnType<typeof calloutLines> },
): Verdict {
  if (to <= from) return { kind: "ok" };
  const { lines, info } =
    scan ??
    (() => {
      const ls = doc.split("\n");
      return { lines: ls, info: calloutLines(ls) };
    })();
  let off = 0;
  for (let i = 0; i < lines.length; i++) {
    const lineEnd = off + lines[i].length;
    const co = info[i];
    if (from >= off && from <= lineEnd) {
      // Body prefixes only — the head's whole-prefix delete (de-callout) is intentional, and the atomic
      // range already blocks partial head corruption.
      if (!co || co.first || co.prefixEnd === 0 || from >= off + co.prefixEnd) {
        // The delete starts cleanly but may JOIN a following body line up (forward-delete of the newline).
        // A join that leaves the body's `> ` intact splices a literal `>` into content — extend the join
        // to consume the whole prefix, like smartBackspace's join does.
        const ext = joinExtension(doc, lines, info, from, to);
        return ext === null ? { kind: "ok" } : { kind: "extend", to: ext };
      }
      // Removing the line WITH its newline (or through EOF) keeps the remaining box contiguous.
      if (to >= lineEnd + 1 || to >= doc.length) return { kind: "ok" };
      if (to >= off + co.prefixEnd) return { kind: "clamp", from: off + co.prefixEnd };
      return { kind: "cancel" };
    }
    off = lineEnd + 1;
  }
  return { kind: "ok" };
}

// When [from, to) removes the newline before a callout BODY line but stops inside (or at the start of) its
// `> ` prefix, return the position the delete must extend to (prefix end) so the join is clean; else null.
function joinExtension(
  doc: string,
  lines: string[],
  info: ReturnType<typeof calloutLines>,
  from: number,
  to: number,
): number | null {
  let off = 0;
  for (let i = 0; i < lines.length; i++) {
    const lineEnd = off + lines[i].length;
    const co = info[i];
    if (co && !co.first && co.prefixEnd > 0 && from < off && to >= off && to < off + co.prefixEnd) {
      return off + co.prefixEnd;
    }
    if (off > to) break;
    off = lineEnd + 1;
  }
  return null;
}

/** True when deleting [from, to) would erode a callout BODY line's `>` prefix in place — a clamped repair
 *  and a cancel both count as "strips". Pure + exported for tests. */
export function stripsCalloutPrefix(doc: string, from: number, to: number): boolean {
  return calloutDeleteVerdict(doc, from, to).kind !== "ok";
}

export const calloutGuard: Extension = EditorState.transactionFilter.of((tr) => {
  if (!tr.docChanged) return tr;
  const doc = docString(tr.startState.doc);
  const scan = calloutScan(tr.startState.doc); // shared per-version — not re-split per change
  let cancel = false;
  let repaired = false;
  const changes: { from: number; to: number; insert: string }[] = [];
  tr.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
    const v = calloutDeleteVerdict(doc, fromA, toA, scan);
    if (v.kind === "cancel") cancel = true;
    if (v.kind === "clamp" || v.kind === "extend") repaired = true;
    changes.push({
      from: v.kind === "clamp" ? v.from : fromA,
      to: v.kind === "extend" ? v.to : toA,
      insert: inserted.toString(),
    });
  });
  if (cancel) return []; // pure prefix erosion — nothing sane to repair it into
  if (!repaired) return tr;
  // Re-issue with the clamped changes. The selection is left to default mapping (the caret lands where the
  // clamped delete puts it, which is the repaired intent); the userEvent rides along for history grouping.
  const userEvent = tr.annotation(Transaction.userEvent);
  return [
    {
      changes,
      effects: tr.effects,
      scrollIntoView: tr.scrollIntoView,
      annotations: userEvent ? Transaction.userEvent.of(userEvent) : undefined,
    },
  ];
});
