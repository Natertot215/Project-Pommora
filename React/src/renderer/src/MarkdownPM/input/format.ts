import { tokenize, type TokenKind } from "../tokens";
import {
  blockquotePrefixRe,
  calloutHeadPrefixLen,
  isBlockquoteLine,
  isCalloutHead,
  parseListMarker,
  stripQuotePrefix,
  type ListMarker,
} from "../detect";
import { lineStartAt, lineEndAt } from "./index";
import { emptyTable } from "../Tables/model";
import { serialize } from "../Tables/codec";

/** A set of source edits + an optional resulting caret, applied as one CM transaction. */
export interface FormatEdit {
  changes: { from: number; to: number; insert: string }[];
  selection?: number;
}

export type InlineFormat =
  | "bold"
  | "italic"
  | "strikethrough"
  | "inlineCode"
  | "link"
  | "connection";
export type HeadingLevel = 0 | 1 | 2 | 3 | 4 | 5 | 6;
export type ListFormat = "bullet" | "ordered" | "task";
export type BlockFormat = "quote" | "code" | "hr" | "callout" | "table";

/** The menu/toggle list-format a parsed marker represents (null for arrow / no marker). One source for both
 *  the format menu's active state and the list toggle. */
export function listFormatOf(lm: ListMarker | null): ListFormat | null {
  switch (lm?.kind) {
    case "checkbox":
      return "task";
    case "ordered":
      return "ordered";
    case "bullet":
      return "bullet";
    default:
      return null;
  }
}

/** A line carries a plain-quote prefix the quote toggle should strip — true for a real blockquote, but NOT a
 *  callout head (whose `>` is box chrome, stripping it orphans the `[!type]`). */
export function isQuoteToggleable(line: string): boolean {
  return isBlockquoteLine(line) && !isCalloutHead(line);
}

const WRAP: Record<Exclude<InlineFormat, "link" | "connection">, string> = {
  bold: "**",
  italic: "*",
  strikethrough: "~~",
  inlineCode: "`",
};

/** Toggle an inline mark over the selection: unwrap if it already wraps, else wrap (caret sits inside when empty). */
export function toggleInline(doc: string, from: number, to: number, fmt: InlineFormat): FormatEdit {
  if (fmt === "link") return toggleLink(doc, from, to);
  if (fmt === "connection") return toggleConnection(doc, from, to);
  const kind = fmt as Exclude<InlineFormat, "link" | "connection"> & TokenKind;
  const existing = tokenize(doc).find(
    (tk) => tk.kind === kind && tk.contentRange[0] <= from && to <= tk.contentRange[1],
  );
  if (existing) {
    const [m0, m1] = existing.markerRanges;
    return {
      changes: [
        { from: m0[0], to: m0[1], insert: "" },
        { from: m1[0], to: m1[1], insert: "" },
      ],
      selection: from - (m0[1] - m0[0]),
    };
  }
  const w = WRAP[kind];
  return {
    changes: [
      { from, to: from, insert: w },
      { from: to, to, insert: w },
    ],
    selection: from === to ? from + w.length : to + w.length,
  };
}

function toggleLink(doc: string, from: number, to: number): FormatEdit {
  const existing = tokenize(doc).find(
    (tk) => tk.kind === "link" && tk.range[0] <= from && to <= tk.range[1],
  );
  if (existing) {
    return {
      changes: [
        {
          from: existing.range[0],
          to: existing.range[1],
          insert: doc.slice(...existing.contentRange),
        },
      ],
    };
  }
  return {
    changes: [
      { from, to: from, insert: "[" },
      { from: to, to, insert: "]()" },
    ],
    selection: to + 3, // inside the empty ()
  };
}

function toggleConnection(doc: string, from: number, to: number): FormatEdit {
  const existing = tokenize(doc).find(
    (tk) => tk.kind === "wikiLink" && tk.range[0] <= from && to <= tk.range[1],
  );
  if (existing) {
    return {
      changes: [
        {
          from: existing.range[0],
          to: existing.range[1],
          insert: doc.slice(...existing.contentRange),
        },
      ],
    };
  }
  return {
    changes: [
      { from, to: from, insert: "[[" },
      { from: to, to, insert: "]]" },
    ],
    selection: from === to ? from + 2 : to + 2,
  };
}

const HEADING_PREFIX = /^(\s{0,3})#{1,6}[ \t]+/;
const LIST_PREFIXES: Record<ListFormat, string> = { bullet: "- ", ordered: "1. ", task: "- [ ] " };

/** Split a line into its quote/callout chrome and the inner body the block transforms operate on. For a
 *  callout HEAD the chrome includes the hidden `[!type] ` tag, so a transform can never expose or demote it.
 *  Block transforms edit from AFTER the chrome — the prefix is never touched, which both preserves the box
 *  and keeps the change out of the callout guard's window. */
export function splitPrefix(line: string): { prefix: string; body: string } {
  const headLen = calloutHeadPrefixLen(line);
  if (headLen !== null) return { prefix: line.slice(0, headLen), body: line.slice(headLen) };
  if (isBlockquoteLine(line)) {
    const p = blockquotePrefixRe.exec(line)?.[0] ?? "";
    return { prefix: p, body: line.slice(p.length) };
  }
  return { prefix: "", body: line };
}

/** Set the caret line's heading level (0 = paragraph); replaces any existing heading or list marker.
 *  Prefix-aware: `> - item` becomes `> ## item`, never `## - item` popped out of its quote. */
export function setHeading(doc: string, pos: number, level: HeadingLevel): FormatEdit {
  const ls = lineStartAt(doc, pos);
  const le = lineEndAt(doc, pos);
  const { prefix, body } = splitPrefix(doc.slice(ls, le));
  const inner = stripInnerMarkers(body);
  const next = level === 0 ? inner : `${"#".repeat(level)} ${inner}`;
  return {
    changes: [{ from: ls + prefix.length, to: le, insert: next }],
    selection: ls + prefix.length + next.length,
  };
}

/** Toggle the caret line into/out of a list kind (re-applying the same kind clears it). Prefix-aware like
 *  setHeading — the list marker lands inside the quote/callout, not in place of its chrome. */
export function setList(doc: string, pos: number, fmt: ListFormat): FormatEdit {
  const ls = lineStartAt(doc, pos);
  const le = lineEndAt(doc, pos);
  const { prefix, body } = splitPrefix(doc.slice(ls, le));
  const current = listFormatOf(parseListMarker(body));
  const inner = stripInnerMarkers(body);
  const next = current === fmt ? inner : `${LIST_PREFIXES[fmt]}${inner}`;
  return {
    changes: [{ from: ls + prefix.length, to: le, insert: next }],
    selection: ls + prefix.length + next.length,
  };
}

/** Apply a block construct to the caret line. */
export function setBlock(doc: string, pos: number, fmt: BlockFormat): FormatEdit {
  const ls = lineStartAt(doc, pos);
  const le = lineEndAt(doc, pos);
  const line = doc.slice(ls, le);
  switch (fmt) {
    case "quote": {
      // Strip a plain quote; a callout's `>` is box chrome, so toggle-quote on a callout head wraps instead of
      // demoting it (stripping would orphan the `[!type]`).
      const next = isQuoteToggleable(line) ? stripQuotePrefix(line) : `> ${line}`;
      return { changes: [{ from: ls, to: le, insert: next }], selection: ls + next.length };
    }
    case "callout": {
      if (isCalloutHead(line)) return { changes: [] }; // already a callout — nothing to convert
      const next = `> [!callout] ${stripBlockMarkers(line)}`;
      return { changes: [{ from: ls, to: le, insert: next }], selection: ls + next.length };
    }
    case "code": {
      const next = `\`\`\`\n${line}\n\`\`\``;
      return { changes: [{ from: ls, to: le, insert: next }], selection: ls + 4 + line.length };
    }
    case "hr": {
      const insert = line.length === 0 ? "---" : `${line}\n\n---\n`;
      return { changes: [{ from: ls, to: le, insert }], selection: ls + insert.length };
    }
    case "table": {
      // A GFM table parses as its own block ONLY when blank lines fence it; without one it merges with an
      // adjacent table below (the first delimiter wins and every other row — including the second table's
      // header + delimiter — becomes a body row). Guarantee a blank line BEFORE and AFTER the 3×3 table.
      // The caret lands just after; the user clicks a cell to edit it.
      const table = serialize(emptyTable(3, 3));
      const before = doc.slice(0, ls);
      const after = doc.slice(le); // begins with the caret line's newline (or empty at EOF)
      const lead =
        line.length > 0 ? `${line}\n\n` : ls === 0 || before.endsWith("\n\n") ? "" : "\n";
      const trail =
        after.startsWith("\n") && !after.startsWith("\n\n") && after.length > 1 ? "\n" : "";
      const insert = `${lead}${table}${trail}`;
      return { changes: [{ from: ls, to: le, insert }], selection: ls + insert.length };
    }
  }
}

/** Strip a leading heading or list marker from the INNER line — quote/callout chrome is splitPrefix's job. */
function stripInnerMarkers(body: string): string {
  const lm = parseListMarker(body);
  if (lm) return body.slice(lm.contentStart);
  return body.replace(HEADING_PREFIX, "$1");
}

/** Strip a leading heading, list, or quote marker — the "reset the line to plain body" step for transforms
 *  that replace the whole line (callout conversion), where consuming the chrome is the point. */
function stripBlockMarkers(line: string): string {
  const lm = parseListMarker(line);
  if (lm) return line.slice(lm.contentStart);
  return stripQuotePrefix(line.replace(HEADING_PREFIX, "$1"));
}
