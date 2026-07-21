import type { Dispatch, SetStateAction } from 'react'
import type { MutateRequest } from '@shared/mutate'
import type { PageFrontmatter } from '@shared/schemas'
import type { ViewRow } from '@shared/types'
import { TIER_LEVEL_BY_ID } from './Table/columnLabel'

type ValueOverride = Record<string, PageFrontmatter> | null

/**
 * The optimistic tier write both container views share (cards + table): patch the row's `tierN`
 * frontmatter array into the value-override layer — loadValues never re-reads mid-session, so the
 * pipeline only re-groups because this patch feeds it — then fire the setTier op. `base` is the
 * frontmatter to patch over, so each caller keeps its own resolved shape (the override entry vs the
 * loaded row's frontmatter).
 */
export function writeTierValue(
  row: Pick<ViewRow, 'id' | 'path'>,
  colId: string,
  ids: string[],
  base: PageFrontmatter,
  setValueOverride: Dispatch<SetStateAction<ValueOverride>>,
  mutate: (req: MutateRequest) => Promise<boolean>,
): void {
  const tier = TIER_LEVEL_BY_ID[colId]
  const patched = { ...base, [`tier${tier}`]: ids } as PageFrontmatter
  setValueOverride((prev) => ({ ...prev, [row.id]: patched }))
  void mutate({ op: 'setTier', path: row.path, tier, contextIds: ids })
}
