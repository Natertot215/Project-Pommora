import { contextBridge, ipcRenderer } from 'electron'
import type { OpenResult } from '@shared/types'

// The ONLY API the renderer can see. Narrow read surface; no fs, no Node.
const api = {
  open: (): Promise<OpenResult> => ipcRenderer.invoke('nexus:open')
}

contextBridge.exposeInMainWorld('nexus', api)

export type NexusApi = typeof api
