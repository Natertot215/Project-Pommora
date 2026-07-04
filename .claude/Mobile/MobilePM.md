## Mobile — MobilePM (the touch editor)

The mobile face of MarkdownPM: the same CodeMirror editor, adapted to touch. Nothing about the editor is rebuilt for the phone — MarkdownPM's whole behavior layer, its constructs, tables, callouts, and block drag are the same web code running in the WebView. The work is the touch surface around it: the keyboard, an accessory toolbar, input behavior, and selection.

### Same Engine, Touch Surface

MarkdownPM already separates a framework-free behavior layer (detection, tokens, decoration intents, input transforms) from its CodeMirror adapter, and that whole stack runs unchanged in the WebView. The mobile editor is the desktop editor in a different input environment, not a fork. The editor's architecture is `Features/MarkdownPM.md`; this doc covers only what touch adds.

### The Keyboard-Accessory Toolbar

The iOS keyboard carries none of the markdown actions a writer needs, so the editor gains a **toolbar that rides above the keyboard** — heading, list, indent and outdent, link, undo, and a dismiss. It is positioned by tracking the visual viewport (the keyboard shifts the layout viewport up, and only the visual-viewport API sees that), not pinned to the bottom where the keyboard would cover it. The OS's own accessory strip is hidden so only ours shows.

### Keyboard and Caret Behavior

The WebView is told **not to resize** under the keyboard, so the editor owns its layout response rather than fighting a native reflow. A WebView does not auto-scroll a contenteditable caret out from under the keyboard, so the editor scrolls the caret into view itself on focus and when the keyboard appears.

### Input Tuning and Selection

The editor switches autocapitalize, autocorrect, and spellcheck on at its editable surface — it defaults them off, and natural writing on iOS needs them on. The honest caveat: because the editor rewrites the DOM for its live styling, iOS text assistance is only partly reliable inside it; the attributes help but don't reach Notes-app fidelity. Selection is the other touch-sensitive area — the build targets a recent CodeMirror line for the accumulated iOS selection and keyboard fixes, and audits that no style rule suppresses native selection, since a stray `user-select` rule silently breaks iOS's selection handles.

### Advanced Gestures Are Polish, Not v1

MarkdownPM's pointer-driven gestures — block drag by the gutter handle, list drag by the glyph, the table grips — are designed for a mouse. On touch they need a long-press-to-arm model or are deferred; they are a polish workstream, not part of the first touch pass. The v1 bar is basic editing: type, select, and format through the toolbar.

### Reference

An open-source inline-preview CodeMirror editor hardened for iOS (Atomic Editor) is the closest thing to mirror for the scroll, selection, and decoration-freeze guards that touch inside a WebView needs. No open-source CodeMirror-inside-Capacitor project exists; the WebView wiring is assembled from the keyboard plugin plus the viewport-tracking toolbar. Tooling specifics live in `MobileResources.md`.
