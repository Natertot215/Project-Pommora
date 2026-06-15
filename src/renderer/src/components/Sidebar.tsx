import { useState } from 'react'
import type { ComponentType } from 'react'
import {
  House,
  CalendarBlank,
  Clock,
  Stack,
  Folder,
  FolderSimple,
  FileText,
  SquaresFour,
  type IconProps
} from '@phosphor-icons/react'
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
import { useSession } from '../store'

type IconCmp = ComponentType<IconProps>

const savedIcon: Record<SavedNode['key'], IconCmp> = {
  homepage: House,
  calendar: CalendarBlank,
  recents: Clock
}

// --- selection helpers ----------------------------------------------------

function isVaultSelected(sel: SelectionState, id: string): boolean {
  return sel.kind === 'vault' && sel.id === id
}

function isPageSelected(sel: SelectionState, id: string): boolean {
  return sel.kind === 'page' && sel.id === id
}

// --- primitive rows -------------------------------------------------------

function Leaf({
  Icon,
  title,
  depth,
  swatch,
  selected = false,
  onSelect
}: {
  Icon: IconCmp
  title: string
  depth: number
  swatch?: string
  selected?: boolean
  onSelect?: () => void
}): React.JSX.Element {
  return (
    <div
      className={`row${selected ? ' selected' : ''}`}
      style={{ paddingLeft: 10 + depth * 14 }}
      onClick={onSelect}
    >
      <span className="twisty-spacer" />
      {swatch ? (
        <span className="swatch" data-color={swatch} />
      ) : (
        <Icon size={15} weight="regular" className="row-icon" />
      )}
      <span className="row-title">{title}</span>
    </div>
  )
}

function Disclosure({
  Icon,
  title,
  depth,
  swatch,
  defaultOpen = true,
  selected = false,
  onSelect,
  children
}: {
  Icon: IconCmp
  title: string
  depth: number
  swatch?: string
  defaultOpen?: boolean
  selected?: boolean
  onSelect?: () => void
  children: React.ReactNode
}): React.JSX.Element {
  const [open, setOpen] = useState(defaultOpen)
  return (
    <>
      <div
        className={`row${selected ? ' selected' : ''}`}
        style={{ paddingLeft: 10 + depth * 14 }}
        onClick={() => {
          setOpen((o) => !o)
          onSelect?.()
        }}
      >
        <span className={`twisty ${open ? 'open' : ''}`}>▸</span>
        {swatch ? (
          <span className="swatch" data-color={swatch} />
        ) : (
          <Icon size={15} weight="regular" className="row-icon" />
        )}
        <span className="row-title">{title}</span>
      </div>
      {open && <div className="children">{children}</div>}
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
  return (
    <Leaf
      Icon={FileText}
      title={page.title}
      depth={depth}
      selected={isPageSelected(selection, page.id)}
      onSelect={() => onSelectPage(page)}
    />
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
  return (
    <Disclosure Icon={FolderSimple} title={set.title} depth={depth} defaultOpen={false}>
      {set.pages.map((p) => (
        <PageRow key={p.id} page={p} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />
      ))}
    </Disclosure>
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
  return (
    <Disclosure Icon={Folder} title={col.title} depth={depth} defaultOpen={false}>
      {col.sets.map((s) => (
        <SetRow key={s.id} set={s} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />
      ))}
      {col.pages.map((p) => (
        <PageRow key={p.id} page={p} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />
      ))}
    </Disclosure>
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
  return (
    <Disclosure
      Icon={Stack}
      title={vault.title}
      depth={depth}
      defaultOpen={false}
      selected={isVaultSelected(selection, vault.id)}
      onSelect={() => onSelectVault(vault)}
    >
      {vault.collections.map((c) => (
        <CollectionRow key={c.id} col={c} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />
      ))}
      {vault.pages.map((p) => (
        <PageRow key={p.id} page={p} depth={depth + 1} selection={selection} onSelectPage={onSelectPage} />
      ))}
    </Disclosure>
  )
}

// --- sections -------------------------------------------------------------

function SectionHeader({ label }: { label: string }): React.JSX.Element {
  return <div className="section-header">{label}</div>
}

export function Sidebar({ tree }: { tree: NexusTree }): React.JSX.Element {
  const selection = useSession((s) => s.selection)
  const select = useSession((s) => s.select)

  const onSelectVault = (vault: PageTypeNode): void => {
    void select({ kind: 'vault', id: vault.id })
  }
  const onSelectPage = (page: PageNode): void => {
    void select({ kind: 'page', id: page.id, path: page.path })
  }

  const hasContexts =
    tree.contexts.projects.length + tree.contexts.topics.length + tree.contexts.areas.length > 0

  return (
    <nav className="sidebar">
      {/* Saved strip — inert in Phase 1 (proves section order) */}
      <div className="section">
        {tree.saved.map((s) => (
          <Leaf key={s.id} Icon={savedIcon[s.key]} title={s.title} depth={0} />
        ))}
      </div>

      {/* Contexts — render order Projects -> Topics -> Areas */}
      {hasContexts && (
        <div className="section">
          {tree.contexts.projects.map((p: ProjectNode) => (
            <Leaf key={p.id} Icon={SquaresFour} title={p.title} depth={0} />
          ))}
          {tree.contexts.topics.map((t: TopicNode) => (
            <Leaf key={t.id} Icon={SquaresFour} title={t.title} depth={0} />
          ))}
          {tree.contexts.areas.map((a: AreaNode) => (
            <Leaf key={a.id} Icon={SquaresFour} title={a.title} depth={0} swatch={a.color} />
          ))}
        </div>
      )}

      {/* Vaults */}
      <div className="section">
        <SectionHeader label={tree.labels.vaults} />
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

      {/* User sections */}
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
    </nav>
  )
}
