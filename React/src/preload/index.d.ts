import type { NexusApi } from './index'

declare global {
  interface Window {
    nexus: NexusApi
  }
}

export {}
