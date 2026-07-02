import { isInsideCode, isInsideWikilink } from "../parser";
import {
  parseListMarker,
  MAX_NESTING_LEVEL,
  blockquotePrefixRe,
  lineInCallout,
  calloutHeadPrefixLen,
  isBlockquoteLine,
} from "../detect";

export interface Edit {
  from: number;
  to: number;
  insert: string;
  selection: number;
}

export const lineStartAt = (doc: string, pos: number): number => doc.lastIndexOf("\n", pos - 1) + 1;
export const lineEndAt = (doc: string, pos: number): number => {
  const i = doc.indexOf("\n", pos);
  return i === -1 ? doc.length : i;
};

const lineMarkerRe = /^(\s*)(?:\d+\.|[-*+•→]|>|#{1,6})(?:[ \t]*\[[ xX]?\])?[ \t]+/;
const shorthandCheckboxRe = /^([ \t]*)([-*+])\[([ xX]?)\]$/;

// The leading `>`/callout prefix on a line (empty for top-level lines). A list continues / indents inside a
// callout because every list op reads the marker from after this prefix and re-emits the prefix on the new line.
// Only a REAL blockquote (whitespace after the `>`, per isBlockquoteLine) carries a prefix — so `>x` isn't
// mistaken for a quoted line by input ops while the renderer shows it as plain text (cross-layer agreement).
const blockPrefix = (line: string): string =>
  isBlockquoteLine(line) ? (blockquotePrefixRe.exec(line)?.[0] ?? "") : "";

export function continueListOnEnter(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null;
  const ls = lineStartAt(doc, selStart);
  const lineEnd = lineEndAt(doc, selStart);
  const line = doc.slice(ls, lineEnd);
  const pfx = blockPrefix(line);
  const lm = parseListMarker(line.slice(pfx.length));
  if (lm === null) return null;
  if (selStart < ls + pfx.length + lm.contentStart) return null; // caret in/before the marker zone

  // Enter on an EMPTY item exits the list (the universal convention) — strip the marker instead of
  // breeding another. Inside a quote/callout the `> ` stays: the exit is out of the LIST, not the box.
  if (line.slice(pfx.length + lm.contentStart).trim() === "") {
    return { from: ls + pfx.length, to: lineEnd, insert: "", selection: ls + pfx.length };
  }

  const indent = line.slice(pfx.length, pfx.length + lm.markerStart);
  // A line that's part of the item's subtree — deeper-indented (nested list or a wrapped item's
  // continuation body) — is skipped by the sibling renumber walk, never a run terminator.
  const isNested = (inner: string): boolean =>
    inner.trim() !== "" && inner.startsWith(indent) && /^[ \t]/.test(inner.slice(indent.length));

  // Renumber following same-level siblings so the run stays sequential (insert between 1 and 2 → 1, 2, 3).
  if (lm.kind === "ordered") {
    const restOfLine = doc.slice(selStart, lineEnd);
    let counter = parseInt(lm.digits ?? "0", 10) + 1;
    const newPrefix = `\n${pfx}${indent}${counter}. `;
    const caret = selStart + newPrefix.length;
    let insert = `${newPrefix}${restOfLine}`;
    let to = lineEnd;
    let pendingSkipped = "";
    counter++;
    for (let p = lineEnd; p < doc.length; ) {
      const fs = p + 1;
      const fe = lineEndAt(doc, fs);
      const fline = doc.slice(fs, fe);
      const fpfx = blockPrefix(fline);
      const finner = fline.slice(fpfx.length);
      const flm = parseListMarker(finner);
      const sameLevel =
        flm !== null &&
        flm.kind === "ordered" &&
        fpfx === pfx &&
        fline.slice(fpfx.length, fpfx.length + flm.markerStart) === indent;
      if (!sameLevel) {
        // Deeper lines (nested sublists, continuations) ride along untouched; anything else ends the run.
        if (fpfx === pfx && isNested(finner)) {
          pendingSkipped += `\n${fline}`;
          p = fe;
          continue;
        }
        break;
      }
      insert += `${pendingSkipped}\n${pfx}${indent}${counter}. ${finner.slice(flm.contentStart)}`;
      pendingSkipped = "";
      counter++;
      to = fe;
      p = fe;
    }
    return { from: selStart, to, insert, selection: caret };
  }

  const next = lm.kind === "checkbox" ? `${lm.bullet ?? "-"} [ ] ` : `${lm.bullet ?? "-"} `;
  const insert = `\n${pfx}${indent}${next}`;
  return { from: selStart, to: selStart, insert, selection: selStart + insert.length };
}

export function continueBlockquoteOnEnter(
  doc: string,
  selStart: number,
  selEnd: number,
): Edit | null {
  if (selStart !== selEnd) return null;
  const ls = lineStartAt(doc, selStart);
  // Ungated on purpose: continues a `>x` (no-space) line too, which blockPrefix's isBlockquoteLine gate would drop.
  const m = blockquotePrefixRe.exec(doc.slice(ls, lineEndAt(doc, selStart)));
  if (m === null || selStart < ls + m[0].length) return null;
  const lineEnd = lineEndAt(doc, selStart);
  // Enter on an EMPTY quote line exits the quote (the universal convention). Callouts keep continuing —
  // their documented exit is caret placement below the box, and stripping a body `> ` would split it.
  if (doc.slice(ls + m[0].length, lineEnd).trim() === "" && !lineInCallout(doc, selStart)) {
    return { from: ls, to: lineEnd, insert: "", selection: ls };
  }
  const insert = `\n${m[0].replace(/[ \t]+$/, "")} `; // normalize to a single trailing space
  return { from: selStart, to: selStart, insert, selection: selStart + insert.length };
}

// `||` at line start → the callout head `> [!callout] `. Fires on the second `|` (already-typed first `|`
// sits at c-1). Line-start only, so a `|` inside a table row can't trigger it. When the callout would be the
// last block in the doc, a trailing empty line is added so the caret has somewhere to land to exit the box.
export function calloutShorthand(
  doc: string,
  selStart: number,
  selEnd: number,
  inserted: string,
): Edit | null {
  if (inserted !== "|" || selStart !== selEnd) return null;
  const c = selStart;
  const ls = lineStartAt(doc, c);
  if (ls !== c - 1 || doc[c - 1] !== "|") return null; // only a bare `|` at line start
  const lineEnd = lineEndAt(doc, c);
  const head = "> [!callout] ";
  // Consume just the `||` (replace the first `|`; the second is suppressed) so any content already on the line
  // is preserved as the callout's first-line body. Separate the new callout from an adjacent blockquote/callout
  // with a blank line so they read as two boxes, not one touching pair. Add a trailing exit line when the
  // callout is alone on its line and there's nothing below to land on (or a quote it must separate from).
  const onlyOnLine = c === lineEnd;
  const prevIsQuote = ls > 0 && isBlockquoteLine(doc.slice(lineStartAt(doc, ls - 1), ls - 1));
  const nextStart = lineEnd + 1;
  const nextIsQuote =
    nextStart <= doc.length && isBlockquoteLine(doc.slice(nextStart, lineEndAt(doc, nextStart)));
  const lead = prevIsQuote ? "\n" : "";
  const trailing = onlyOnLine && (lineEnd === doc.length || nextIsQuote) ? "\n" : "";
  const insert = lead + head + trailing;
  return { from: ls, to: c, insert, selection: ls + lead.length + head.length };
}

// Shift+Enter normally exits a construct (plain newline). Inside a callout it instead stays in the box —
// continuing the `> ` prefix — so multi-line content and lists can be built without escaping; exit is by
// caret placement on the empty line below.
export function shiftEnterEdit(doc: string, selStart: number, selEnd: number): Edit {
  // Inside a callout the new line keeps the box prefix (works with a selection too — a plain `\n` there would
  // drop an un-prefixed line into the middle of the run and split the callout). Require BOTH ends in the
  // callout: a selection straddling the box edge falls back to a plain `\n` so outside text isn't pulled in.
  if (lineInCallout(doc, selStart) && lineInCallout(doc, selEnd)) {
    const ls = lineStartAt(doc, selStart);
    const pfx = (
      blockquotePrefixRe.exec(doc.slice(ls, lineEndAt(doc, selStart)))?.[0] ?? "> "
    ).replace(/[ \t]+$/, "");
    const insert = `\n${pfx} `;
    return { from: selStart, to: selEnd, insert, selection: selStart + insert.length };
  }
  return { from: selStart, to: selEnd, insert: "\n", selection: selStart + 1 };
}

export function indentListOnTab(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null;
  const ls = lineStartAt(doc, selStart);
  const line = doc.slice(ls, lineEndAt(doc, selStart));
  const pfx = blockPrefix(line);
  const lm = parseListMarker(line.slice(pfx.length));
  if (lm === null || lm.level >= MAX_NESTING_LEVEL) return null;
  // Indent after the `>` prefix so a list inside a callout nests without breaking the blockquote.
  return { from: ls + pfx.length, to: ls + pfx.length, insert: "\t", selection: selStart + 1 };
}

// Shift-Tab removes one list-indent level — the inverse Tab's indent never had. Without it the browser's
// focus-move fires and the caret leaves the editor entirely.
export function outdentListOnShiftTab(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null;
  const ls = lineStartAt(doc, selStart);
  const line = doc.slice(ls, lineEndAt(doc, selStart));
  const pfx = blockPrefix(line);
  const inner = line.slice(pfx.length);
  if (parseListMarker(inner) === null || !/^[ \t]/.test(inner)) return null;
  return {
    from: ls + pfx.length,
    to: ls + pfx.length + 1,
    insert: "",
    selection: Math.max(ls + pfx.length, selStart - 1),
  };
}

// Backspace at a marker's content-start deletes the whole marker in one step (no nibbling `- [ ] ` into broken
// syntax). Prefix-aware: inside a quote/callout it deletes the INNER marker (stay in the box), joins to the
// previous box line when there's no inner marker, and removes the whole `> [!type] ` head cleanly.
export function smartBackspace(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null;
  const ls = lineStartAt(doc, selStart);
  const line = doc.slice(ls, lineEndAt(doc, selStart));

  // Inside a callout, never strip a lone `>` (that drops the line out of the box / splits the callout into a
  // stray quote). Delete an inner list marker, strip the whole `> [!type] ` head, or join to the line above.
  if (lineInCallout(doc, selStart)) {
    const pfx = blockPrefix(line);
    const headLen = calloutHeadPrefixLen(line);
    if (headLen !== null) {
      // Backspace anywhere inside the hidden `> [!type] ` head removes the whole callout in one step, so a
      // caret that wandered into the tag can't corrupt it char-by-char and silently demote the box to a quote.
      if (selStart > ls && selStart <= ls + headLen)
        return { from: ls, to: ls + headLen, insert: "", selection: ls };
      return null;
    }
    const lm = parseListMarker(line.slice(pfx.length));
    if (lm) {
      const innerContentStart = ls + pfx.length + lm.contentStart;
      if (selStart !== innerContentStart) return null;
      return {
        from: ls + pfx.length,
        to: innerContentStart,
        insert: "",
        selection: ls + pfx.length,
      };
    }
    if (selStart === ls + pfx.length && ls > 0)
      return { from: ls - 1, to: ls + pfx.length, insert: "", selection: ls - 1 };
    return null;
  }

  // Top-level (incl. plain quotes): delete the whole marker prefix in one step.
  const m = lineMarkerRe.exec(line);
  if (m === null) return null;
  const contentStart = ls + m[0].length;
  if (selStart !== contentStart) return null;
  return { from: ls, to: contentStart, insert: "", selection: ls };
}

export function canonicalizeCheckbox(
  doc: string,
  selStart: number,
  selEnd: number,
  inserted: string,
): Edit | null {
  if (inserted !== " " || selStart !== selEnd) return null;
  const ls = lineStartAt(doc, selStart);
  const before = doc.slice(ls, selStart);
  const pfx = blockPrefix(before);
  const m = shorthandCheckboxRe.exec(before.slice(pfx.length));
  if (m === null) return null;
  const [, ws, marker, inner] = m;
  const gfm = `${ws}${marker} [${inner.toLowerCase() === "x" ? "x" : " "}] `;
  return {
    from: ls + pfx.length,
    to: selStart,
    insert: gfm,
    selection: ls + pfx.length + gfm.length,
  };
}

interface PairSpec {
  close: string;
  multi?: string;
}
const PAIRS: Record<string, PairSpec> = {
  "*": { close: "*", multi: "**" },
  _: { close: "_", multi: "__" },
  "`": { close: "`", multi: "``" },
  "(": { close: ")", multi: "))" },
  "[": { close: "]", multi: "]]" },
  '"': { close: '"' },
  "'": { close: "'" },
};

// `" ' * _ \`` pair only when NOT right after a word char (so contractions, units `5"`, `2 * 3`, snake_case
// and prose backticks stay literal) and type over their own closer on the way out. Their doubled emphasis
// forms (`**` `__` `` `` ``) are handled by the multi branch.
const GATED_PAIRS = new Set(['"', "'", "*", "_", "`"]);

// Single `[` only pairs at line start / after whitespace (so `-[` flows).
export function autoPair(
  doc: string,
  selStart: number,
  selEnd: number,
  inserted: string,
): Edit | null {
  if (selStart !== selEnd) return null;
  const c = selStart;
  if (isInsideCode(c, doc)) return null;
  const prev = doc[c - 1];
  const pair = PAIRS[inserted];
  if (!pair) return null;

  if (pair.multi && prev === inserted) {
    // Consume an already-paired closer so `[|]` + `[` → `[[|]]`, not a stray `[[|]]]`.
    if (doc[c] === pair.close)
      return { from: c, to: c, insert: inserted + pair.close, selection: c + 1 };
    // A doubled marker only pairs as a fresh OPENER: not glued to a word (`snake__` stays literal), and
    // not completing an earlier unmatched double (`**word*` + `*` closes the bold — pairing here would
    // stack `**word****`). Line-local, minus the prev char the user just typed.
    const beforeRun = doc.slice(lineStartAt(doc, c), c - 1);
    const openDoubles = beforeRun.split(inserted + inserted).length - 1;
    const glued = doc[c - 2] !== undefined && /\w/.test(doc[c - 2]);
    if (glued || openDoubles % 2 === 1) return null;
    return { from: c, to: c, insert: inserted + pair.multi, selection: c + 1 };
  }
  if (inserted === "[") {
    const atLineStart = c === lineStartAt(doc, c);
    if (atLineStart || prev === " " || prev === "\t" || prev === "\n") {
      return { from: c, to: c, insert: inserted + pair.close, selection: c + 1 };
    }
    return null;
  }
  if (inserted === "(") {
    return { from: c, to: c, insert: inserted + pair.close, selection: c + 1 };
  }
  if (GATED_PAIRS.has(inserted)) {
    // Type over the closer on the way out (so `'hello|'` + `'` → `'hello'|`, no stray) — see GATED_PAIRS.
    if (doc[c] === inserted) return { from: c, to: c, insert: "", selection: c + 1 };
    if (prev === undefined || !/\w/.test(prev)) {
      return { from: c, to: c, insert: inserted + pair.close, selection: c + 1 };
    }
    return null;
  }
  return null;
}

export function autoDelete(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd || selStart === 0 || isInsideCode(selStart, doc)) return null;
  const close = PAIRS[doc[selStart - 1]]?.close;
  if (close === undefined || doc[selStart] !== close) return null;
  return { from: selStart - 1, to: selStart + 1, insert: "", selection: selStart - 1 };
}

// Closers (longest first, so `]]` beats `]` and `**` beats `*`) + the opener that must appear earlier on the
// line for the caret to count as "inside" that construct.
const CLOSERS: readonly { close: string; open: string }[] = [
  { close: "]]", open: "[[" },
  { close: "**", open: "**" },
  { close: "__", open: "__" },
  { close: "``", open: "``" },
  { close: "]", open: "[" },
  { close: ")", open: "(" },
  { close: '"', open: '"' },
  { close: "'", open: "'" },
  { close: "*", open: "*" },
  { close: "_", open: "_" },
  { close: "`", open: "`" },
];

// If the caret sits just before the closer of an open construct (a matching opener earlier on the line),
// returns the offset just past that closer; else null. The shared core of close-on-Enter / -Shift+Enter.
const isWordCh = (ch: string | undefined): boolean => ch !== undefined && /\w/.test(ch);

function closerEndAt(doc: string, c: number): number | null {
  if (isInsideCode(c, doc)) return null;
  const before = doc.slice(lineStartAt(doc, c), c);
  // A single-char symmetric marker flanked by word chars is prose, not a delimiter — contractions
  // (`don't`) and possessives would otherwise poison the parity and make Enter teleport the caret.
  const count = (s: string): number => {
    if (s.length > 1) return before.split(s).length - 1;
    let n = 0;
    for (let i = before.indexOf(s); i !== -1; i = before.indexOf(s, i + 1)) {
      if (!(isWordCh(before[i - 1]) && isWordCh(before[i + 1] ?? doc[c]))) n++;
    }
    return n;
  };
  for (const { close, open } of CLOSERS) {
    if (!doc.startsWith(close, c)) continue;
    // The closer AT the caret gets the same prose test: `don|'t` must not read `'` as a closer.
    if (close.length === 1 && open === close && isWordCh(doc[c - 1]) && isWordCh(doc[c + 1]))
      continue;
    // Inside an OPEN construct? Symmetric markers (`open === close`): an odd count before the caret means one
    // is still open. Asymmetric pairs: more opens than closes before. A plain `includes` would false-positive
    // when an earlier instance is already closed (`**a**|**b**`).
    const inside = open === close ? count(open) % 2 === 1 : count(open) > count(close);
    if (inside) return c + close.length;
  }
  return null;
}

// Enter inside an open pair / quote / emphasis / connection closes it — the caret steps past the closer (no
// newline). Generalizes the old empty-pair skip to constructs with content (`[[word|]]` → `[[word]]|`).
export function closeConstructOnEnter(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null;
  const end = closerEndAt(doc, selStart);
  return end === null ? null : { from: selStart, to: selStart, insert: "", selection: end };
}

// Shift+Enter inside an open construct closes it FIRST, then breaks the line — so the newline never lands
// inside the pair. The break reuses shiftEnterEdit (callout-aware) from just past the closer.
export function closeConstructOnShiftEnter(
  doc: string,
  selStart: number,
  selEnd: number,
): Edit | null {
  if (selStart !== selEnd) return null;
  const end = closerEndAt(doc, selStart);
  return end === null ? null : shiftEnterEdit(doc, end, end);
}

// The dashes at `c` are link content, not prose — leave them literal. Covers a URL-shaped run (scheme://…)
// AND any markdown-link target `](…` still open before the caret (relative paths, anchors, mailto: — none
// carry a scheme), where converting `--`→`—` would corrupt the path.
const urlRunRe = /(?:^|[\s([{<"'])[a-z][a-z0-9+.-]*:\/\/\S*$/i;
const inLinkTarget = (doc: string, c: number): boolean => {
  const line = doc.slice(lineStartAt(doc, c), c);
  const open = line.lastIndexOf("](");
  return open !== -1 && !line.slice(open).includes(")");
};
const inUrlRun = (doc: string, c: number): boolean =>
  urlRunRe.test(doc.slice(lineStartAt(doc, c), c)) || inLinkTarget(doc, c);

// Fires on the NEXT char so collisions resolve first.
export function dashArrow(
  doc: string,
  selStart: number,
  selEnd: number,
  inserted: string,
): Edit | null {
  if (selStart !== selEnd || inserted.length !== 1) return null;
  const c = selStart;
  if (isInsideCode(c, doc)) return null;

  // em-dash: "--" then a non-dash char (the 3-back check preserves --- HR). Guarded like the en-dash
  // branch below: a `--` inside a [[title]] or a URL is content — converting it silently retargets the
  // connection / corrupts the link.
  if (
    inserted !== "-" &&
    c >= 2 &&
    doc[c - 1] === "-" &&
    doc[c - 2] === "-" &&
    doc[c - 3] !== "-"
  ) {
    if (isInsideWikilink(c, doc) || inUrlRun(doc, c)) return null;
    return { from: c - 2, to: c, insert: `—${inserted}`, selection: c };
  }
  if (inserted === "-" && doc[c - 1] === "–")
    return { from: c - 1, to: c, insert: "—", selection: c };
  if (inserted === ">") {
    if (doc[c - 1] === "←") return { from: c - 1, to: c, insert: "↔", selection: c };
    if (doc[c - 1] === "-") return { from: c - 1, to: c, insert: "→", selection: c };
  }
  if (inserted === "-" && doc[c - 1] === "<")
    return { from: c - 1, to: c, insert: "←", selection: c };
  if (inserted === " " && c >= 2 && doc[c - 1] === "-" && doc[c - 2] === " ") {
    const ls = lineStartAt(doc, c);
    // Measure "is there prose before the dash" AFTER the blockquote prefix — otherwise the `> ` on a callout /
    // quote line counts as content and a `- ` bullet there gets eaten into an en-dash.
    const pfx = blockPrefix(doc.slice(ls, lineEndAt(doc, c)));
    const before = doc.slice(ls + pfx.length, c - 2);
    if (/\S/.test(before) && !isInsideWikilink(c, doc)) {
      return { from: c - 1, to: c, insert: "– ", selection: c + 1 };
    }
  }
  return null;
}
