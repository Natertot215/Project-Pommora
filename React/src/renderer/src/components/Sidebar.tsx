import { useState, useRef, useEffect } from 'react'
import { Icon, icons, type IconName } from '@renderer/design-system/symbols'
import { MenuItem } from '@renderer/design-system/components/menu'
import { Reveal } from '@renderer/design-system/components/Reveal'
import type {
  AreaNode,
  CollectionNode,
  NexusTree,
  PageNode,
  PageTypeNode,
  SavedNode,
  SelectionState,
  SetNode,
  TopicNode,
  ProjectNode
} from '@shared/types'
import { DEFAULT_NEW_NAME, type MutableKind } from '@shared/mutate'
import { TreeMove, useTreeDrag, useTreeDrop } from '@renderer/design-system/interactions/behaviors/useTreeMove'
import { useSession } from '../store'

const savedIcon: Record<SavedNode['key'], IconName> = {
  homepage: 'house',
  calendar: 'calendar',
  recents: 'clock'
}

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
  const renamingPath = useSession((s) => s.renamingPath)
  const cancelRename = useSession((s) => s.cancelRename)
  const submitRename = useSession((s) => s.submitRename)
  const editing = renamingPath === path
  const settled = useRef(false)
  useEffect(() => {
    if (editing) settled.current = false
  }, [editing])
  if (!editing) return <>{title}</>
  const finish = (raw: string): void => {
    if (settled.current) return
    settled.current = true
    const next = raw.trim()
    if (next && next !== title) void submitRename(path, kind, next)
    else cancelRename()
  }
  return (
    <input
      className="row-title-input"
      defaultValue={title}
      autoFocus
      onFocus={(e) => e.currentTarget.select()}
      onClick={(e) => e.stopPropagation()}
      onKeyDown={(e) => {
        if (e.key === 'Enter') e.currentTarget.blur()
        else if (e.key === 'Escape') {
          settled.current = true
          cancelRename()
        }
      }}
      onBlur={(e) => finish(e.currentTarget.value)}
    />
  )
}

// --- selection helpers ----------------------------------------------------

function isVaultSelected(sel: SelectionState, id: string): boolean {
  return sel.kind === 'vault' && sel.id === id
}

function isPageSelected(sel: SelectionState, id: string): boolean {
  return sel.kind === 'page' && sel.id === id
}

// --- icon helper ----------------------------------------------------------

// Resolve a row's icon, attaching the folder open/closed swap ONLY when the icon
// is the folder icon. A custom icon — or a non-folder default like the vault's
// stack — stays put when the row toggles. Falls back when the stored name isn't a
// known symbol.
function folderAwareIcons(
  custom: string | undefined,
  fallback: IconName
): { icon: IconName; openIcon?: IconName } {
  const icon = custom && custom in icons ? (custom as IconName) : fallback
  return { icon, openIcon: icon === 'folder-closed' ? 'folder-open' : undefined }
}

// --- primitive rows -------------------------------------------------------

function Leaf({
  icon,
  title,
  depth,
  swatch,
  selected = false,
  chevronSpace = true,
  onSelect,
  onContextMenu,
  rename
}: {
  icon: IconName
  title: string
  depth: number
  swatch?: string
  selected?: boolean
  // Reserve the disclosure-chevron column so the icon lines up under expandable
  // rows. Top-level shortcuts (the Saved strip) opt out and sit flush.
  chevronSpace?: boolean
  onSelect?: () => void
  onContextMenu?: () => void
  rename?: RenameTarget
}): React.JSX.Element {
  return (
    <MenuItem
      className="row"
      selected={selected}
      indent={depth}
      onClick={onSelect}
      onContextMenu={ctxHandler(onContextMenu)}
      leading={
        <>
          {chevronSpace && <span className="twisty-spacer" />}
          {swatch ? <span className="swatch" data-color={swatch} /> : <Icon name={icon} size={16} />}
        </>
      }
    >
      {rename ? <RowTitle path={rename.path} kind={rename.kind} title={title} /> : title}
    </MenuItem>
  )
}

function Disclosure({
  icon,
  openIcon,
  title,
  depth,
  swatch,
  defaultOpen = true,
  selected = false,
  onSelect,
  onContextMenu,
  rename,
  children
}: {
  icon: IconName
  openIcon?: IconName
  title: string
  depth: number
  swatch?: string
  defaultOpen?: boolean
  selected?: boolean
  onSelect?: () => void
  onContextMenu?: () => void
  rename?: RenameTarget
  children: React.ReactNode
}): React.JSX.Element {
  const [open, setOpen] = useState(defaultOpen)
  return (
    <>
      <MenuItem
        className="row"
        selected={selected}
        indent={depth}
        onClick={() => {
          setOpen((o) => !o)
          onSelect?.()
        }}
        onContextMenu={ctxHandler(onContextMenu)}
        leading={
          <>
            <Icon name="chevron-right" size={12} className={`twisty${open ? ' open' : ''}`} />
            {swatch ? (
              <span className="swatch" data-color={swatch} />
            ) : (
              <Icon name={open && openIcon ? openIcon : icon} size={16} />
            )}
          </>
        }
      >
        {rename ? <RowTitle path={rename.path} kind={rename.kind} title={title} /> : title}
      </MenuItem>
      <Reveal open={open}>
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
  const drag = useTreeDrag(page.id, page.path, page.title)
  return (
    <div ref={drag.setNodeRef} className={`tree-item${drag.isDragging ? ' dragging' : ''}`} {...drag.handle}>
      <Leaf
        icon="file-text"
        title={page.title}
        depth={depth}
        selected={isPageSelected(selection, page.id)}
        onSelect={() => onSelectPage(page)}
        onContextMenu={() => showContextFor(page)}
        rename={{ path: page.path, kind: page.kind }}
      />
    </div>
  )
}

function SetRow({
  set,
  depth,
  selection,
  onSelectPage
}: {
  set: SetNode
  depth: number
  selection: SelectionState
  onSelectPage: (page: PageNode) => void
}): React.JSX.Element {
  const { icon, openIcon } = folderAwareIcons(set.icon, 'folder-closed')
  const drop = useTreeDrop(set.id, set.path)
  return (
    <div ref={drop.setNodeRef} className={`tree-zone${drop.isOver ? ' tree-over' : ''}`}>
      <Disclosure
        icon={icon}
        openIcon={openIcon}
        title={set.title}
        depth={depth}
        defaultOpen={false}
        onContextMenu={() => showContextFor(set)}
        rename={{ path: set.path, kind: set.kind }}
      >
        {set.pages.map((p) => (
          <PageRow key={p.id} page={p} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />
        ))}
      </Disclosure>
    </div>
  )
}

function CollectionRow({
  col,
  depth,
  selection,
  onSelectPage
}: {
  col: CollectionNode
  depth: number
  selection: SelectionState
  onSelectPage: (page: PageNode) => void
}): React.JSX.Element {
  const { icon, openIcon } = folderAwareIcons(col.icon, 'folder-closed')
  const drop = useTreeDrop(col.id, col.path)
  return (
    <div ref={drop.setNodeRef} className={`tree-zone${drop.isOver ? ' tree-over' : ''}`}>
      <Disclosure
        icon={icon}
        openIcon={openIcon}
        title={col.title}
        depth={depth}
        defaultOpen={false}
        onContextMenu={() => showContextFor(col)}
        rename={{ path: col.path, kind: col.kind }}
      >
        {col.sets.map((s) => (
          <SetRow key={s.id} set={s} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />
        ))}
        {col.pages.map((p) => (
          <PageRow key={p.id} page={p} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />
        ))}
      </Disclosure>
    </div>
  )
}

function VaultRow({
  vault,
  depth,
  selection,
  onSelectVault,
  onSelectPage
}: {
  vault: PageTypeNode
  depth: number
  selection: SelectionState
  onSelectVault: (vault: PageTypeNode) => void
  onSelectPage: (page: PageNode) => void
}): React.JSX.Element {
  const { icon, openIcon } = folderAwareIcons(vault.icon, 'gallery-vertical-end')
  const drop = useTreeDrop(vault.id, vault.path)
  return (
    <div ref={drop.setNodeRef} className={`tree-zone${drop.isOver ? ' tree-over' : ''}`}>
      <Disclosure
        icon={icon}
        openIcon={openIcon}
        title={vault.title}
        depth={depth}
        defaultOpen={false}
        selected={isVaultSelected(selection, vault.id)}
        onSelect={() => onSelectVault(vault)}
        onContextMenu={() => showContextFor(vault)}
        rename={{ path: vault.path, kind: vault.kind }}
      >
        {vault.collections.map((c) => (
          <CollectionRow key={c.id} col={c} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />
        ))}
        {vault.pages.map((p) => (
          <PageRow key={p.id} page={p} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />
        ))}
      </Disclosure>
    </div>
  )
}

// --- sections -------------------------------------------------------------

function SectionHeader({ label, onAdd }: { label: string; onAdd?: () => void }): React.JSX.Element {
  return (
    <div className="section-header">
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
  const newVault = useSession((s) => s.newVault)
  const movePage = useSession((s) => s.movePage)

  const onSelectVault = (vault: PageTypeNode): void => {
    void select({ kind: 'vault', id: vault.id })
  }
  const onSelectPage = (page: PageNode): void => {
    void select({ kind: 'page', id: page.id, path: page.path })
  }

  // Contexts are three tiers; the header "+" pops a native picker → createContext(tier).
  const newContext = (): void => {
    void window.nexus.popCreateMenu([
      { label: 'New Area', req: { op: 'createContext', tier: 1, name: DEFAULT_NEW_NAME } },
      { label: 'New Topic', req: { op: 'createContext', tier: 2, name: DEFAULT_NEW_NAME } },
      { label: 'New Project', req: { op: 'createContext', tier: 3, name: DEFAULT_NEW_NAME } }
    ])
  }

  return (
    <nav className="sidebar">
      {/* Saved strip — inert in Phase 1 (proves section order) */}
      <div className="section">
        {tree.saved.map((s) => (
          <Leaf key={s.id} icon={savedIcon[s.key]} title={s.title} depth={0} chevronSpace={false} />
        ))}
      </div>

      {/* Contexts — always shown so the "+" can create the first; order Projects -> Topics -> Areas */}
      <div className="section">
        <SectionHeader label="Contexts" onAdd={newContext} />
        {tree.contexts.projects.map((p: ProjectNode) => (
          <Leaf key={p.id} icon="layout-grid" title={p.title} depth={0} onContextMenu={() => showContextFor(p)} rename={{ path: p.path, kind: p.kind }} />
        ))}
        {tree.contexts.topics.map((t: TopicNode) => (
          <Leaf key={t.id} icon="layout-grid" title={t.title} depth={0} onContextMenu={() => showContextFor(t)} rename={{ path: t.path, kind: t.kind }} />
        ))}
        {tree.contexts.areas.map((a: AreaNode) => (
          <Leaf key={a.id} icon="layout-grid" title={a.title} depth={0} swatch={a.color} onContextMenu={() => showContextFor(a)} rename={{ path: a.path, kind: a.kind }} />
        ))}
      </div>

      {/* Vaults + user sections — drag a page between containers (cross-set / cross-collection). */}
      <TreeMove onMove={(from, to) => void movePage(from, to)}>
        <div className="section">
          <SectionHeader label={tree.labels.vaults} onAdd={newVault} />
          {tree.vaults.map((v) => (
            <VaultRow
              key={v.id}
              vault={v}
              depth={0}
              selection={selection}
              onSelectVault={onSelectVault}
              onSelectPage={onSelectPage}
            />
          ))}
        </div>

        {tree.userSections.map((sec) => (
          <div className="section" key={sec.id}>
            <SectionHeader label={sec.label} />
            {sec.vaults.map((v) => (
              <VaultRow
                key={v.id}
                vault={v}
                depth={0}
                selection={selection}
                onSelectVault={onSelectVault}
                onSelectPage={onSelectPage}
              />
            ))}
          </div>
        ))}
      </TreeMove>
    </nav>
  )
}
