// The data layer's internal result contract. Mirrors the IPC envelope shape so a
// handler can return a Result straight across the boundary. No fs, no React.

/** A structured, serializable error. `scope` names the entity/operation domain. */
export interface PommoraError {
  code: string
  message: string
  scope?: string
}

export type Result<T, E = PommoraError> = { ok: true; value: T } | { ok: false; error: E }

export function ok<T>(value: T): Result<T, never> {
  return { ok: true, value }
}

export function err<E = PommoraError>(error: E): Result<never, E> {
  return { ok: false, error }
}

/** Terse failure constructor. */
export function fail(code: string, message: string, scope?: string): Result<never> {
  return { ok: false, error: scope === undefined ? { code, message } : { code, message, scope } }
}
