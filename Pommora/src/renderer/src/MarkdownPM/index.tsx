import { useEffect, useRef } from "react";
import { docString } from "./editor/docCache";
import { EditorView, keymap } from "@codemirror/view";
import { Compartment, EditorState, Prec } from "@codemirror/state";
import { history, historyField, historyKeymap, defaultKeymap } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { markdownDecorations } from "./editor/decorations";
import { markdownInput } from "./editor/input";
import { tableWidgetExtension, applySavedHeadingCols, type TableHeadingColsApi } from "./Tables";
import { listDragExtension } from "./editor/listDrag";
import { blockHandles, blockGripHover } from "./editor/blockHandles";
import {
  blockDragExtension,
  blockquoteDragExtension,
  calloutDragExtension,
} from "./editor/blockDrag";
import { calloutGripMenu } from "./editor/calloutGripMenu";
import { customCaret } from "./editor/caret";
import { calloutAtomic } from "./editor/calloutAtomic";
import { calloutGuard } from "./editor/calloutGuard";
import { connectionClicks } from "./editor/connections";
import { externalLinkClicks } from "./editor/links";
import { markdownFolding, applySavedFolds, type FoldsApi } from "./editor/folding";
import { applyEditorAction, type EditorMenuApi } from "./editor/menu";
import { formatKeymap } from "./editor/formatKeymap";
import { readFormatState } from "./editor/formatState";
import { AC_MAX } from "./autocomplete";
import { useConnectionAutocomplete, detectConnectionQuery } from "./useConnectionAutocomplete";
import { AutocompletePanel } from "./AutocompletePanel";
import type { ConnectionsApi } from "./connections";
import type { IconName } from "@renderer/design-system/symbols";
import { PageHeader } from "./PageHeader";
import { ZOOM_DEFAULT, zoomFontSize } from "./zoom";
import "./Styles.css";

/** The warm-tab seam (B-3): `restore` is read once at mount to seed the fresh EditorState (undo via
 *  the serialized historyField) + scroll; `capture` fires at unmount with the state to keep warm. The
 *  host binds both to a (tab, entity) identity at mount time — the mount-once effect freezes that
 *  binding, so a capture can never land under the NEXT tab's identity mid-switch. */
export interface WarmSeam {
  restore: () => { editorState?: unknown; scrollTop?: number } | undefined;
  capture: (state: { editorState: unknown; scrollTop: number }) => void;
}

interface Props {
  initialBody: string;
  onChange: (body: string) => void;
  title?: string;
  onRename?: (newName: string) => void | Promise<boolean>;
  /** Page identity + chrome for the header (banner cover + Edit Icon). */
  path?: string;
  cover?: string;
  onEditIcon?: () => void;
  zoom?: number;
  connections?: ConnectionsApi;
  folds?: FoldsApi;
  tableHeadingColumns?: TableHeadingColsApi;
  menu?: EditorMenuApi;
  /** Focus the editor on mount — for click-to-edit surfaces (block tiles). */
  autoFocus?: boolean;
  /** Read-only portal mode: the SAME view, editing gated by a live-reconfigured
   *  compartment — flipping it never remounts (embeds' jitter-free enter-edit). */
  readOnly?: boolean;
  /** Apply the shared scroll-edge fade to the editor's scroller — the embed treatment; the full page
   *  editor leaves it off. */
  edgeFade?: boolean;
  /** Warm-tab state seam — page editors only; embeds/blocks mount cold. */
  warm?: WarmSeam;
}

export function MarkdownEditor({
  initialBody,
  onChange,
  title,
  onRename,
  path,
  cover,
  onEditIcon,
  zoom = ZOOM_DEFAULT,
  connections,
  folds,
  tableHeadingColumns,
  menu,
  autoFocus = false,
  readOnly = false,
  edgeFade = false,
  warm,
}: Props): React.JSX.Element {
  const readOnlyGate = useRef(new Compartment());
  const readOnlyAtMount = useRef(readOnly);
  const host = useRef<HTMLDivElement>(null);
  const shellRef = useRef<HTMLDivElement>(null);
  const titleRef = useRef<HTMLDivElement>(null);
  const viewRef = useRef<EditorView | null>(null);
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;
  const connectionsRef = useRef(connections);
  connectionsRef.current = connections;
  const foldsRef = useRef(folds);
  foldsRef.current = folds;
  const tableHeadingColsRef = useRef(tableHeadingColumns);
  tableHeadingColsRef.current = tableHeadingColumns;
  const menuRef = useRef(menu);
  menuRef.current = menu;
  const lastFormatRef = useRef("");

  // CM6 extensions are built once at mount, so they read live state + actions through refs. The `[[…]]`
  // autocomplete state machine is shared with table cells; this editor's seams are the candidate source
  // (over-fetch one to drop the page's own title) and the inline panel placement (rendered below).
  const { ac, setAc, candidates, acIndex, acTop, commit, acCtl } = useConnectionAutocomplete(
    viewRef,
    (query) =>
      connectionsRef.current
        ? connectionsRef.current
            .candidates(query, AC_MAX + 1)
            .filter((p) => p.title !== title)
            .slice(0, AC_MAX)
        : [],
  );

  useEffect(() => {
    const parent = host.current;
    if (!parent) return;
    const extensions = [
        // Editable stays true even in the read-only portal: MarkdownPM renders selection natively (no
        // drawSelection layer), so the at-rest embed must remain a focusable contenteditable to be
        // selectable at all — never blocked by a non-editable DOM.
        EditorView.editable.of(true),
        readOnlyGate.current.of(EditorState.readOnly.of(readOnlyAtMount.current)),
        // EditorState.readOnly is ADVISORY — it stops the view's own input pipeline but NOT a
        // programmatic view.dispatch({changes}) (formatKeymap, the list/table/checkbox commands). With a
        // focusable read-only portal that would let Cmd+B edit + autosave a read-only surface, so drop
        // every doc-changing transaction while read-only at the one sink that catches them all.
        EditorState.changeFilter.of((tr) => !(tr.startState.readOnly && tr.docChanged)),
        history(),
        Prec.highest(
          keymap.of([
            {
              key: "ArrowDown",
              run: () => (acCtl.current.open ? (acCtl.current.move(1), true) : false),
            },
            {
              key: "ArrowUp",
              run: () => (acCtl.current.open ? (acCtl.current.move(-1), true) : false),
            },
            {
              key: "Enter",
              run: () => (acCtl.current.open ? (acCtl.current.pick(), true) : false),
            },
            {
              key: "Escape",
              run: () => (acCtl.current.open ? (acCtl.current.close(), true) : false),
            },
          ]),
        ),
        markdownInput,
        formatKeymap,
        keymap.of([...defaultKeymap, ...historyKeymap]),
        // Language/parse support ONLY — its default keymap and paste rewriting are Lezer-convention ghosts
        // this editor replaces: the keymap auto-continues constructs MarkdownPM renders as plain prose
        // (e.g. `1)` lists) whenever the custom handlers decline, and pasteURLAsLink rewrites a URL pasted
        // over a selection into [selection](url) against the paste-preserves-literal-text rule.
        markdown({ addKeymap: false, pasteURLAsLink: false, completeHTMLTags: false }),
        EditorView.lineWrapping,
        // iOS soft-keyboard hints — no-ops on desktop; keep the on-screen keyboard from
        // auto-capitalizing and "correcting" Markdown / [[wikilinks]]. Tune during the mobile editor pass.
        EditorView.contentAttributes.of({
          autocapitalize: "sentences",
          autocorrect: "off",
          spellcheck: "true",
          enterkeyhint: "enter",
        }),
        markdownDecorations(() => connectionsRef.current),
        // Interactive table widget — renders each Markdown table as an editable HTML table over the GFM
        // source; the connections getter lets `[[…]]` render + autocomplete inside cells.
        tableWidgetExtension(
          () => connectionsRef.current,
          (indices) => tableHeadingColsRef.current?.save(indices),
        ),
        // Grab a list glyph (•, number, or checkbox) to drag-reorder the item; click toggles/places caret.
        listDragExtension,
        // Block-drag rail handles: a hover grip on each draggable block's first line (paragraph/code/quote/list).
        blockHandles,
        // Reveal each grip only while the pointer is in its gutter strip (not over the line's text); the hot-line
        // callback flags a callout-grip hover to main so the generic editor menu stands down there.
        blockGripHover((line) =>
          window.nexus?.setCalloutGrip?.(!!line && line.classList.contains("md-callout-first")),
        ),
        // Press a block grip → drag the whole block → drop it at the nearest block boundary.
        blockDragExtension,
        // The callout's own gutter grip drags the whole callout box (same gesture, gated on the head line).
        calloutDragExtension,
        // The blockquote's widget grip drags the whole quote (same gesture, gated on its first line).
        blockquoteDragExtension,
        // Right-press the callout grip → native Delete Callout menu (the flag above suppresses the generic one).
        calloutGripMenu,
        // Drawn caret (rounded bar in text, I-beam on empty lines, smooth fade) — native caret hidden in CSS.
        customCaret,
        // The hidden `> [!type] ` callout head is atomic — caret can't enter it, so the tag can't be corrupted.
        calloutAtomic,
        // Reject any delete that would erode a callout body line's `>` prefix in place (drop it out of the box).
        calloutGuard,
        connectionClicks(() => connectionsRef.current),
        externalLinkClicks(),
        // Close the connection panel when focus leaves the editor (sidebar click, Cmd-Tab) — the cell
        // editor has the same handler; without it the glass panel floats over unrelated UI.
        EditorView.domEventHandlers({
          blur: () => {
            setAc(null);
            return false;
          },
        }),
        markdownFolding((keys) => foldsRef.current?.save(keys)),
        EditorView.updateListener.of((u) => {
          if (!(u.docChanged || u.selectionSet || u.focusChanged)) return; // skip scroll/geometry-only updates
          const doc = docString(u.state.doc);
          const sel = u.state.selection.main;
          if (u.docChanged) onChangeRef.current(doc);

          const fs = readFormatState(doc, sel.from, sel.to, u.view.hasFocus);
          const json = JSON.stringify(fs);
          if (json !== lastFormatRef.current) {
            lastFormatRef.current = json;
            menuRef.current?.pushState(fs);
          }

          if (u.docChanged || u.selectionSet) detectConnectionQuery(u.view, setAc);
        }),
    ];
    // Warm rehydration (B-3): seed the fresh mount from the cached serialized state — doc + selection +
    // undo history (historyField is the only serialized field; folds ride folds.json below). A corrupt
    // or cross-version payload falls back to a cold mount rather than throwing the editor away.
    const saved = warm?.restore();
    let warmState: EditorState | null = null;
    if (saved?.editorState !== undefined) {
      try {
        warmState = EditorState.fromJSON(saved.editorState, { extensions }, { history: historyField });
      } catch {
        warmState = null;
      }
    }
    const view = new EditorView(warmState ? { state: warmState, parent } : { doc: initialBody, parent, extensions });
    viewRef.current = view;
    // Track scroll continuously for the unmount capture — at cleanup time React may have already
    // detached the DOM, where reading scrollTop yields 0 and would wipe the saved position.
    let lastScrollTop = saved?.scrollTop ?? 0;
    const onWarmScroll = (): void => {
      lastScrollTop = view.scrollDOM.scrollTop;
    };
    if (warm) view.scrollDOM.addEventListener("scroll", onWarmScroll, { passive: true });
    // Embed treatment: the shared scroll-edge fade rides the CM scroller (the real scroll element), so
    // top/bottom content dissolves as it scrolls — same mask + scroll-timeline as every other faded box.
    // The top fade is gated to need a full fade-height of real scroll first (edge-fade-top-gated), so a
    // first line at rest — or CM's autofocus scroll offset — never blurs.
    if (edgeFade) view.scrollDOM.classList.add("scroll-edge-fade", "edge-fade-top-gated");
    // Click-to-edit surfaces (block tiles) mount THIS editor in response to a click
    // that landed on the at-rest render — without a focus the caret goes nowhere.
    if (autoFocus && !readOnlyAtMount.current) view.focus();
    // Restore this page's saved folds once the view's lines exist (the widget clones them). The warm
    // scroll restores AFTER folds settle — folding changes content height, so restoring first would
    // land on a pre-fold offset.
    const restoreScroll = (): void => {
      // != null, not truthy — a saved top-of-page (0) must still override CM's own restore scroll.
      if (saved?.scrollTop != null) view.scrollDOM.scrollTop = saved.scrollTop;
    };
    const foldsLoad = foldsRef.current?.load();
    if (foldsLoad)
      void foldsLoad.then((keys) => {
        applySavedFolds(view, keys);
        restoreScroll();
      });
    else requestAnimationFrame(restoreScroll);
    // Restore this page's heading-column tables (rebuilds the affected table widgets).
    void tableHeadingColsRef.current
      ?.load()
      .then((indices) => applySavedHeadingCols(view, indices));
    // The header parks on scroll via a CSS scroll-driven animation (Styles.css) — no JS scroll handler.
    const unsubMenu = menuRef.current?.onAction((action) => applyEditorAction(view, action));
    return () => {
      unsubMenu?.();
      if (warm) {
        view.scrollDOM.removeEventListener("scroll", onWarmScroll);
        // `warm` is the mount-render prop (deps []), so this capture lands under the identity this
        // editor mounted with — never the next tab's, even though the switch already updated the store.
        warm.capture({ editorState: view.state.toJSON({ history: historyField }), scrollTop: lastScrollTop });
      }
      view.destroy();
      viewRef.current = null;
    };
    // Mount once per page — the host keys on path; initialBody is the seed, not a live binding.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // The portal flip: reconfigure the read-only gate on the LIVE view — same doc, same
  // decorations, no remount (editable stays true throughout, see the mount comment). Entering
  // edit focuses when the surface asked for it.
  useEffect(() => {
    const view = viewRef.current;
    if (!view || readOnly === readOnlyAtMount.current) {
      readOnlyAtMount.current = readOnly;
      return;
    }
    readOnlyAtMount.current = readOnly;
    view.dispatch({
      effects: readOnlyGate.current.reconfigure(EditorState.readOnly.of(readOnly)),
    });
    if (!readOnly && autoFocus) view.focus();
  }, [readOnly, autoFocus]);

  // Body top-padding tracks the header height, so toggling the banner resizes the gutter automatically.
  useEffect(() => {
    const header = titleRef.current;
    const shell = shellRef.current;
    if (!header || !shell) return;
    // --header-zone lives on the shell so both the body's top padding and the header's scroll-park range read it.
    const apply = (): void => shell.style.setProperty("--header-zone", `${header.offsetHeight}px`);
    apply();
    const ro = new ResizeObserver(apply);
    ro.observe(header);
    return () => ro.disconnect();
  }, []);

  return (
    <div
      ref={shellRef}
      className="mdpm-shell"
      style={{ "--editor-font-size": `${zoomFontSize(zoom)}px` } as React.CSSProperties}
    >
      {title !== undefined && path !== undefined && (
        <PageHeader
          ref={titleRef}
          path={path}
          title={title}
          cover={cover}
          onRename={onRename ?? ((): void => {})}
          onEditIcon={onEditIcon ?? ((): void => {})}
        />
      )}
      <div ref={host} className="mdpm-editor" />
      <AutocompletePanel
        open={ac !== null}
        candidates={candidates}
        index={acIndex}
        left={ac?.left ?? 0}
        top={acTop}
        query={ac?.query ?? ""}
        onPick={commit}
      />
    </div>
  );
}
