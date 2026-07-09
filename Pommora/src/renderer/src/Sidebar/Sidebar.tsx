import { useEffect, useRef, useState } from 'react'
import { Icon, icons, type IconName, defaultEntityIcon } from '@renderer/design-system/symbols'
import { lucideGlyph } from '@renderer/design-system/symbols/AllSymbols'
import { text } from '@renderer/design-system/tokens'
import { cx } from '@renderer/design-system/cx'
import { MenuItem } from '@renderer/design-system/components/menu'
import { Reveal } from '@renderer/design-system/components/Reveal'
import { slideScrollBack } from '@renderer/design-system/components/OverflowScroll'
import { EditableInput } from '../Components/EditableInput'
import type {
  AreaNode,
  CollectionNode,
  EntityIconKind,
  FolderPlacement,
  NexusTree,
  PageNode,
  SelectionState,
  SetNode,
  SidebarMode,
  TopicNode,
  ProjectNode
} from '@shared/types'
import { DEFAULT_NEW_NAME, type MutableKind, type MutateRequest } from '@shared/mutate'
import { SidebarDnd, useSidebarDrag } from './sidebarDnd'
import { AgendaMode } from './AgendaMode'
import { loadOpen, saveOpen } from './disclosureState'
import { useSession } from '../store'
import { RenamableTitle } from '../Components/RenamableTitle'

/** Right-click an entity → main pops the native context menu. Every PathNode (page +
 *  container + context) carries kind/path/title; the code-keyed saved rows don't, so they
 *  never wire this. */
function showContextFor(node: { kind: MutableKind; path: string; title: string }): void {
  void window.nexus.contextMenu({ kind: node.kind, path: node.path, title: node.title })
}

/** A row's onContextMenu handler — suppress the browser default, then run `cb`. */
function ctxHandler(cb?: () => void): ((e: React.MouseEvent) => void) | undefined {
  return cb
    ? (e) => {
        e.preventDefault()
        cb()
      }
    : undefined
}

/** Addresses a row for inline rename — its path + kind, handed to the mutate op on commit. */
type RenameTarget = { path: string; kind: MutableKind }

/** A row's title: a static label, or an inline `<input>` while this row is being renamed
 *  (store.renamingPath === path). Commit on Enter / blur (skipped when unchanged or empty);
 *  cancel on Escape. The mutate op runs through the store. */
function RowTitle({ path, kind, title }: { path: string; kind: MutableKind; title: string }): React.JSX.Element {
  return <RenamableTitle path={path} kind={kind} title={title} className="row-title-input" />
}

// --- selection helpers ----------------------------------------------------

function isCollectionSelected(sel: SelectionState, id: string): boolean {
  return sel.kind === 'collection' && sel.id === id
}

function isSetSelected(sel: SelectionState, id: string): boolean {
  return sel.kind === 'set' && sel.id === id
}

function isPageSelected(sel: SelectionState, id: string): boolean {
  return sel.kind === 'page' && sel.id === id
}

// --- icon helper ----------------------------------------------------------

// Resolve a row's icon, attaching the folder open/closed swap ONLY when the icon
// is the folder icon. A custom icon — or a non-folder default like the vault's
// stack — stays put when the row toggles. Falls back when the stored name isn't a
// known symbol.
function folderAwareIcons(custom: string | undefined, fallback: IconName): { icon: string; openIcon?: IconName } {
  // Keep any renderable Lucide id (curated OR the full set — a user's arbitrary pick), else the default.
  const icon = custom && (custom in icons || lucideGlyph(custom) !== undefined) ? custom : fallback
  return { icon, openIcon: icon === 'folder-closed' ? 'folder-open' : undefined }
}

// --- primitive rows -------------------------------------------------------

function Leaf({
  icon,
  title,
  depth,
  selected = false,
  chevronSpace = true,
  onSelect,
  onContextMenu,
  rename
}: {
  icon: string
  title: string
  depth: number
  selected?: boolean
  // Reserve the disclosure-chevron column so the icon lines up under expandable
  // rows. Top-level shortcuts (the Saved strip) opt out and sit flush.
  chevronSpace?: boolean
  onSelect?: () => void
  onContextMenu?: () => void
  rename?: RenameTarget
}): React.JSX.Element {
  // The row icon rides INSIDE the title's scroll box (not the fixed leading slot), so it ellipsizes and
  // hover-scrolls as one unit with the title; only the chevron/spacer stays fixed in the gutter.
  return (
    <MenuItem
      className="row"
      selected={selected}
      indent={depth}
      onClick={onSelect}
      onContextMenu={ctxHandler(onContextMenu)}
      leading={chevronSpace ? <span className="twisty-spacer" /> : null}
    >
      <Icon name={icon} size={16} className="row-icon" />
      {rename ? <RowTitle path={rename.path} kind={rename.kind} title={title} /> : title}
    </MenuItem>
  )
}

// The draggable wrapper every sidebar row shares: registers the row with the DnD engine,
// spreads the pointer handle, and mutes it while lifted. Its rect feeds the insertion-line
// hit-testing, so it must wrap ONLY the row itself — never a subtree (a Disclosure's body
// stays outside it).
function DragRow({ id, children }: { id: string; children: React.ReactNode }): React.JSX.Element {
  const drag = useSidebarDrag(id)
  return (
    <div
      ref={drag.ref}
      className={`tree-item${drag.isDragging ? ' dragging' : ''}`}
      {...drag.handle}
      onMouseLeave={(e) => {
        const sc = e.currentTarget.querySelector<HTMLElement>('[class*="titleText"]')
        if (sc) slideScrollBack(sc)
      }}
    >
      {children}
    </div>
  )
}

function Disclosure({
  icon,
  openIcon,
  title,
  depth,
  defaultOpen = true,
  persistKey,
  selected = false,
  onSelect,
  onContextMenu,
  rename,
  dragId,
  children
}: {
  icon: string
  openIcon?: IconName
  title: string
  depth: number
  defaultOpen?: boolean
  // Stable identity for persisting open/collapse across sessions (entity id, or a `tier:*` key for
  // the structural context tiers). Omitted → ephemeral (resets to `defaultOpen` each mount).
  persistKey?: string
  selected?: boolean
  onSelect?: () => void
  onContextMenu?: () => void
  rename?: RenameTarget
  // The header row's id when this disclosure is a real entity — its OWN rect (not the subtree's)
  // is what the engine hit-tests, so DragRow wraps only the header MenuItem; the <Reveal> body
  // stays outside it. Omitted for structural disclosures (the context tiers), which aren't
  // entities and so are never draggable or drop targets.
  dragId?: string
  children: React.ReactNode
}): React.JSX.Element {
  const [open, setOpen] = useState(() => (persistKey ? loadOpen(window.localStorage, persistKey, defaultOpen) : defaultOpen))
  const toggle = (): void =>
    setOpen((o) => {
      const next = !o
      if (persistKey) saveOpen(window.localStorage, persistKey, next)
      return next
    })
  // Storage containers (vault/collection) carry an onSelect: clicking the icon or title opens the
  // view, while the rest of the row (chevron, empty space) toggles. Rows with no onSelect (tiers,
  // sets) have no select zone, so a click anywhere toggles.
  const openView = onSelect
    ? (e: React.MouseEvent): void => {
        e.stopPropagation()
        onSelect()
      }
    : undefined
  const header = (
    <MenuItem
      className="row"
      selected={selected}
      indent={depth}
      onClick={toggle}
      onContextMenu={ctxHandler(onContextMenu)}
      leading={<Icon name="chevron-right" size={12} className={`twisty${open ? ' open' : ''}`} />}
    >
      <span onClick={openView}>
        <Icon name={open && openIcon ? openIcon : icon} size={16} className="row-icon" />
        {rename ? <RowTitle path={rename.path} kind={rename.kind} title={title} /> : title}
      </span>
    </MenuItem>
  )
  return (
    <>
      {dragId ? <DragRow id={dragId}>{header}</DragRow> : header}
      <Reveal open={open} fill>
        <div className="children">{children}</div>
      </Reveal>
    </>
  )
}

// --- node renderers (typed arrays -> structural order) --------------------

function PageRow({
  page,
  depth,
  selection,
  onSelectPage
}: {
  page: PageNode
  depth: number
  selection: SelectionState
  onSelectPage: (page: PageNode) => void
}): React.JSX.Element {
  const defaultIcons = useSession((s) => s.personalization.defaultIcons)
  return (
    <DragRow id={page.id}>
      <Leaf
        icon={defaultEntityIcon('page', defaultIcons)}
        title={page.title}
        depth={depth}
        selected={isPageSelected(selection, page.id)}
        onSelect={() => onSelectPage(page)}
        onContextMenu={() => showContextFor(page)}
        rename={{ path: page.path, kind: page.kind }}
      />
    </DragRow>
  )
}

// Shared container header — folder-aware icon + drop-target registration + the
// Disclosure shell. CollectionRow / SetRow differ only in default icon, children,
// and which selection they carry.
function ContainerRow({
  node,
  defaultIcon,
  depth,
  selected,
  onSelect,
  children
}: {
  node: { id: string; icon?: string; title: string; path: string; kind: MutableKind }
  defaultIcon: IconName
  depth: number
  selected?: boolean
  onSelect?: () => void
  children: React.ReactNode
}): React.JSX.Element {
  const { icon, openIcon } = folderAwareIcons(node.icon, defaultIcon)
  return (
    <Disclosure
      dragId={node.id}
      persistKey={node.id}
      icon={icon}
      openIcon={openIcon}
      title={node.title}
      depth={depth}
      defaultOpen={false}
      selected={selected}
      onSelect={onSelect}
      onContextMenu={() => showContextFor(node)}
      rename={{ path: node.path, kind: node.kind }}
    >
      {children}
    </Disclosure>
  )
}

// A container's folders form one contiguous block, placed above or below its loose pages by the
// nexus-wide placement knob. A full folder↔page interleave is the eventual model; this top/bottom
// flag is the interim — folders stay a block, just relocatable.
function placeChildren(folders: React.JSX.Element[], pages: React.JSX.Element[], placement: FolderPlacement): React.JSX.Element[] {
  return placement === 'bottom' ? [...pages, ...folders] : [...folders, ...pages]
}

// A Set row. Only depth-1 Sets (direct children of a Collection, `selectable`) open a view; deeper
// Sub-Sets are expand-only organizing folders. Renders its sub-sets and its pages, ordered by the
// subSetPlacement knob.
function SetRow({ set, depth, selectable, selection, onSelectSet, onSelectPage }: { set: SetNode; depth: number; selectable: boolean; selection: SelectionState; onSelectSet: (set: SetNode) => void; onSelectPage: (page: PageNode) => void }): React.JSX.Element {
  const setDefaultIcons = useSession((s) => s.personalization.defaultIcons)
  const subSetPlacement = useSession((s) => s.personalization.subSetPlacement ?? 'top')
  return (
    <ContainerRow
      node={set}
      defaultIcon={defaultEntityIcon('set', setDefaultIcons)}
      depth={depth}
      selected={selectable && isSetSelected(selection, set.id)}
      onSelect={selectable ? () => onSelectSet(set) : undefined}
    >
      {placeChildren(
        (set.sets ?? []).map((s) => (
          <SetRow key={s.id} set={s} depth={depth + 1} selectable={false} selection={selection} onSelectSet={onSelectSet} onSelectPage={onSelectPage} />
        )),
        set.pages.map((p) => <PageRow key={p.id} page={p} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />),
        subSetPlacement
      )}
    </ContainerRow>
  )
}

// A top-level Collection — the schema-bearing container (Swift: PageCollection). Its direct Sets
// render as selectable depth-1 rows, ordered against its loose pages by the setPlacement knob.
function CollectionRow({ col, depth, selection, onSelectCollection, onSelectSet, onSelectPage }: { col: CollectionNode; depth: number; selection: SelectionState; onSelectCollection: (col: CollectionNode) => void; onSelectSet: (set: SetNode) => void; onSelectPage: (page: PageNode) => void }): React.JSX.Element {
  const defaultIcons = useSession((s) => s.personalization.defaultIcons)
  const setPlacement = useSession((s) => s.personalization.setPlacement ?? 'top')
  return (
    <ContainerRow node={col} defaultIcon={defaultEntityIcon('collection', defaultIcons)} depth={depth} selected={isCollectionSelected(selection, col.id)} onSelect={() => onSelectCollection(col)}>
      {placeChildren(
        col.sets.map((s) => (
          <SetRow key={s.id} set={s} depth={depth + 1} selectable selection={selection} onSelectSet={onSelectSet} onSelectPage={onSelectPage} />
        )),
        col.pages.map((p) => <PageRow key={p.id} page={p} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />),
        setPlacement
      )}
    </ContainerRow>
  )
}

// A context leaf (Area / Topic / Project) — a draggable row reordered within its tier disclosure
// (depth 1, under the tier header). Every tier uses the grid icon.
function ContextRow({ node }: { node: { id: string; title: string; path: string; kind: MutableKind } }): React.JSX.Element {
  const select = useSession((s) => s.select)
  const selected = useSession((s) => s.selection.kind === 'context' && s.selection.id === node.id)
  const defaultIcons = useSession((s) => s.personalization.defaultIcons)
  return (
    <DragRow id={node.id}>
      <Leaf
        icon={defaultEntityIcon(node.kind as EntityIconKind, defaultIcons)}
        title={node.title}
        depth={1}
        selected={selected}
        onSelect={() => void select({ kind: 'context', id: node.id })}
        onContextMenu={() => showContextFor(node)}
        rename={{ path: node.path, kind: node.kind }}
      />
    </DragRow>
  )
}

// A context tier group (Areas / Topics / Projects) — a non-draggable disclosure under the
// Contexts heading holding that tier's leaves. Grid icon, open by default. The tiers are
// free-standing (no containment), so the header is a pure expand/collapse toggle.
const TIER_ICON_KIND: Record<'areas' | 'topics' | 'projects', EntityIconKind> = {
  areas: 'area',
  topics: 'topic',
  projects: 'project'
}
function TierDisclosure({ tierKey, label, children }: { tierKey: 'areas' | 'topics' | 'projects'; label: string; children: React.ReactNode }): React.JSX.Element {
  const defaultIcons = useSession((s) => s.personalization.defaultIcons)
  return (
    <Disclosure icon={defaultEntityIcon(TIER_ICON_KIND[tierKey], defaultIcons)} title={label} depth={0} defaultOpen persistKey={`tier:${tierKey}`}>
      {children}
    </Disclosure>
  )
}

// --- sections -------------------------------------------------------------

function SectionHeader({ label, onAdd }: { label: string; onAdd?: () => void }): React.JSX.Element {
  return (
    <div className={cx('section-header', text.control.semibold)}>
      <span>{label}</span>
      {onAdd && (
        <button className="section-add" title={`New ${label}`} aria-label={`New ${label}`} onClick={onAdd}>
          +
        </button>
      )}
    </div>
  )
}

export function Sidebar({ tree }: { tree: NexusTree }): React.JSX.Element {
  const selection = useSession((s) => s.selection)
  const select = useSession((s) => s.select)
  const mutate = useSession((s) => s.mutate)
  const setPlacement = useSession((s) => s.personalization.setPlacement ?? 'top')
  const subSetPlacement = useSession((s) => s.personalization.subSetPlacement ?? 'top')
  const mode: SidebarMode = useSession((s) => s.personalization.sidebarMode ?? 'collections')

  const onSelectCollection = (col: CollectionNode): void => {
    void select({ kind: 'collection', id: col.id })
  }
  const onSelectSet = (set: SetNode): void => {
    void select({ kind: 'set', id: set.id, path: set.path })
  }
  const onSelectPage = (page: PageNode): void => {
    void select({ kind: 'page', id: page.id, path: page.path })
  }

  // A drop resolves to a MutateRequest; the store's one write path applies it (refetch on ok).
  const onCommit = (req: MutateRequest): void => void mutate(req)

  // Right-click a mode's empty area → a native create menu (never auto-create). Contexts offers the
  // three tiers; Collections a single "New Collection" (Add Heading joins it with User Sections CRUD).
  const newContext = (): void => {
    void window.nexus.popCreateMenu([
      { label: 'New Area', req: { op: 'createContext', tier: 1, name: DEFAULT_NEW_NAME } },
      { label: 'New Topic', req: { op: 'createContext', tier: 2, name: DEFAULT_NEW_NAME } },
      { label: 'New Project', req: { op: 'createContext', tier: 3, name: DEFAULT_NEW_NAME } }
    ])
  }
  const newCollectionMenu = (): void => {
    void window.nexus.popCreateMenu([
      { label: 'New Collection', req: { op: 'createContainer', parentPath: '', kind: 'collection', name: DEFAULT_NEW_NAME } }
    ])
  }

  // One native capture-phase listener flags the row that's actually scrolled off its start, so the left-edge
  // eclipse only shows once content slides under it — never on a bare hover. React doesn't delegate `scroll`
  // (it binds onScroll straight to the node) and scroll doesn't bubble, so a prop on <nav> would never see a
  // descendant .titleText's scroll — capture DOES traverse down to it. slideTitleBack's rAF drives scrollLeft
  // to 0, re-firing this to clear the flag.
  const navRef = useRef<HTMLElement>(null)
  useEffect(() => {
    const nav = navRef.current
    if (!nav) return
    const onScroll = (e: Event): void => {
      const sc = e.target as HTMLElement
      if (sc?.matches?.('[class*="titleText"]')) sc.classList.toggle('title-scrolled', sc.scrollLeft > 0)
    }
    nav.addEventListener('scroll', onScroll, { capture: true })
    return () => nav.removeEventListener('scroll', onScroll, { capture: true })
  }, [])

  // Contexts mode — the three free-standing tiers (Areas → Topics → Projects), its own drag zone.
  const contextsLayer = (
    <SidebarDnd tree={tree} onCommit={onCommit} setPlacement={setPlacement} subSetPlacement={subSetPlacement}>
      <div className="section">
        <TierDisclosure tierKey="areas" label={tree.labels.area.plural}>
          {tree.contexts.areas.map((a: AreaNode) => (
            <ContextRow key={a.id} node={a} />
          ))}
        </TierDisclosure>
        <TierDisclosure tierKey="topics" label={tree.labels.topic.plural}>
          {tree.contexts.topics.map((t: TopicNode) => (
            <ContextRow key={t.id} node={t} />
          ))}
        </TierDisclosure>
        <TierDisclosure tierKey="projects" label={tree.labels.project.plural}>
          {tree.contexts.projects.map((p: ProjectNode) => (
            <ContextRow key={p.id} node={p} />
          ))}
        </TierDisclosure>
      </div>
    </SidebarDnd>
  )

  // Collections mode — top-level Collections plus user-named sections (their headings stay), own zone.
  const collectionsLayer = (
    <SidebarDnd tree={tree} onCommit={onCommit} setPlacement={setPlacement} subSetPlacement={subSetPlacement}>
      <div className="section">
        {(tree.collections ?? []).map((c) => (
          <CollectionRow
            key={c.id}
            col={c}
            depth={0}
            selection={selection}
            onSelectCollection={onSelectCollection}
            onSelectSet={onSelectSet}
            onSelectPage={onSelectPage}
          />
        ))}
      </div>
      {tree.userSections.map((sec) => (
        <div className="section" key={sec.id}>
          <SectionHeader label={sec.label} />
          {(sec.collections ?? []).map((c) => (
            <CollectionRow
              key={c.id}
              col={c}
              depth={0}
              selection={selection}
              onSelectCollection={onSelectCollection}
              onSelectSet={onSelectSet}
              onSelectPage={onSelectPage}
            />
          ))}
        </div>
      ))}
    </SidebarDnd>
  )

  // Right-click the empty mode area → its create menu (the section headers that once held the "+"
  // are gone). Fires only on the bare layer surface, so a row's own context menu still wins.
  const modeCtx =
    (cb?: () => void) =>
    (e: React.MouseEvent): void => {
      if (!cb || e.target !== e.currentTarget) return
      e.preventDefault()
      cb()
    }

  const active =
    mode === 'contexts'
      ? { node: contextsLayer, onCreate: newContext }
      : mode === 'agenda'
        ? { node: <AgendaMode />, onCreate: undefined }
        : { node: collectionsLayer, onCreate: newCollectionMenu }

  return (
    <nav ref={navRef} className="sidebar scroll-edge-fade">
      <div className="sidebar-mode" onContextMenu={modeCtx(active.onCreate)}>
        {active.node}
      </div>
    </nav>
  )
}
