import { contextBridge, ipcRenderer } from 'electron'
import type { OpenResult, PageResult } from '@shared/types'

// The ONLY API the renderer can see. Narrow read surface; no fs, no Node.
const api = {
  open: (): Promise<OpenResult> => ipcRenderer.invoke('nexus:open'),
  openPage: (relPath: string): Promise<PageResult> => ipcRenderer.invoke('page:open', relPath),
  systemAccent: (): Promise<string | null> => ipcRenderer.invoke('theme:systemAccent')
}

contextBridge.exposeInMainWorld('nexus', api)

export type NexusApi = typeof api
