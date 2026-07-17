/** The single class-name joiner for the design system — concatenates, dropping falsey parts. */
export const cx = (...parts: Array<string | false | undefined>): string =>
  parts.filter(Boolean).join(' ')
