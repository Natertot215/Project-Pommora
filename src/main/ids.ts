// The single owner of identity minting + recognition for the data layer.
// ULIDs for real entities (monotonic so rapid same-millisecond creates keep their
// order); `adopted-<sha256>` for entities read from a raw/un-adopted folder before
// a real id exists. Both the read engine and the write path import from here.

import { createHash } from 'node:crypto'
import { monotonicFactory, isValid } from 'ulidx'

const nextUlid = monotonicFactory()

/** Mint a fresh ULID. Monotonic within the process so same-ms creates stay ordered. */
export function newId(): string {
  return nextUlid()
}

/** True for a syntactically valid ULID (26 Crockford-base32 chars). */
export function isUlid(value: string): boolean {
  return isValid(value)
}

/** Mint a fresh user-defined property id (`prop_<ulid>`). Built-in property ids are the
 *  reserved `_`-prefixed constants in shared/properties.ts; this mints the user form. */
export function mintPropertyId(): string {
  return 'prop_' + newId()
}

/**
 * Stable synthetic id for an entity read from a raw/un-adopted folder with no
 * persisted id. Derived from the nexus-relative POSIX path, so the same file always
 * reads as the same id until adoption mints a real ULID for it.
 */
export function adoptedId(relPath: string): string {
  return 'adopted-' + createHash('sha256').update(relPath).digest('hex').slice(0, 16)
}
