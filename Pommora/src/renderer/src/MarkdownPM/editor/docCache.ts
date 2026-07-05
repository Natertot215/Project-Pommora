// One string materialization + one callout scan per doc VERSION, shared by every extension that runs per
// keystroke / caret move. CM's Text.toString() re-joins the rope on every call and calloutLines re-splits
// the result — with several extensions each doing both per transaction, this was the designated lag source
// under the project's "never do expensive work on every X" rule. Keyed on the immutable Text via WeakMap,
// so old versions collect with the history.
import type { Text } from "@codemirror/state";
import { calloutLines, type CalloutLine } from "../detect";

const strings = new WeakMap<Text, string>();
export function docString(doc: Text): string {
  let s = strings.get(doc);
  if (s === undefined) {
    s = doc.toString();
    strings.set(doc, s);
  }
  return s;
}

export interface CalloutScan {
  lines: string[];
  info: (CalloutLine | undefined)[];
}
const callouts = new WeakMap<Text, CalloutScan>();
export function calloutScan(doc: Text): CalloutScan {
  let c = callouts.get(doc);
  if (!c) {
    const lines = docString(doc).split("\n");
    c = { lines, info: calloutLines(lines) };
    callouts.set(doc, c);
  }
  return c;
}
