// Shared NexusTree fixture for the Navigation unit tests (search + resolve). One of each entity kind,
// with a nested Set so location-chain resolution is exercised. Not shipped — imported only by *.test.
import type { NexusTree } from '@shared/types'
import { DEFAULT_LABELS } from '@shared/types'

export function makeTree(): NexusTree {
  return {
    nexus: { id: 'nx', rootPath: '/x', name: 'TestNexus', profileImage: null, profileSubtitle: '' },
    homepage: { locked: false, headingIconHidden: false },
    navView: {},
    saved: [],
    contexts: {
      areas: [{ kind: 'area', id: 'a1', title: 'Work', path: 'Work' }],
      topics: [{ kind: 'topic', id: 't1', title: 'Reading', path: 'Reading' }],
      projects: [{ kind: 'project', id: 'pr1', title: 'Pommora', path: 'Pommora' }],
    },
    collections: [
      {
        kind: 'collection',
        id: 'c1',
        title: 'Notes',
        path: 'Notes',
        pages: [{ kind: 'page', id: 'p1', title: 'Alpha', path: 'Notes/Alpha.md' }],
        sets: [
          {
            kind: 'set',
            id: 's1',
            title: 'Ideas',
            path: 'Notes/Ideas',
            pages: [{ kind: 'page', id: 'p2', title: 'Nested Beta', path: 'Notes/Ideas/Beta.md' }],
            sets: [],
          },
        ],
      },
    ],
    userSections: [],
    labels: DEFAULT_LABELS,
    accent: 'lavender',
    timeFormat: 'twelveHour',
    personalization: {},
    commands: {},
    registry: [],
  }
}
