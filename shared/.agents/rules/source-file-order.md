---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.kt"
---

# Order inside a source file

**A file opens with the thing it exists for, and reads downwards into the
details.** The main export, the component, the service's business method comes
right after the imports; what it calls follows, in the order it calls it; each
type sits next to the code that uses it.

The layout this forbids is the common default: a wall of interfaces, types and
constants, then helpers, and the logic last. The reader scrolls past the
vocabulary to learn what the file does, then scrolls back up to understand it.
Nobody has proved one order best, but code laid out linearly gets read linearly
(an eye-tracking study, Peitek et al., ICPC 2020), and Kotlin's own conventions
ask for a class read "from top to bottom" that "can follow the logic".

- **Never sort by kind, visibility or alphabet.** Related things stay together:
  public operation A, its private helper, then operation B and its helper. A
  helper shared by several goes once, after the last of them.
- **A type lives next to its owner** — a props type right after its component,
  a helper-only type next to the helper. No `types.ts` for types used in one
  file, no types block at the top.
- **Initialisation order wins over reading order.** Never move an eager call, an
  initialiser, a decorator, a registration or a Kotlin `init` block just to fit
  this; split the file instead.
- **A file that cannot be ordered this way does two things.** Split it by
  responsibility, not into one file per function — a helper with one owner
  stays with it.

## TypeScript and TSX

1. Imports.
2. The main export — `export function`, not an arrow in a `const`, so it can call
   what is declared below it — with its signature or props type beside it.
3. Its local sub-components, hooks and helpers, in first-use order, each with
   its own types and constants.

Components stay at module scope, never defined inside another one. The order of
hook *calls* inside a component is not layout; never reshuffle it. A `const`
read during module load (not inside a function body) still has to come before
its reader.

Do not enable a linter that undoes this: `perfectionist/sort-modules` and
`sort-classes` default to alphabetical and types-first, and
`@typescript-eslint/member-ordering` to visibility blocks. With
`no-use-before-define`, set `functions: false`, `variables: false`,
`ignoreTypeReferences: true`.

## Kotlin

1. Package and imports.
2. The main class or top-level function, before the data classes, sealed types
   and extensions it uses.
3. In a class: properties and `init` blocks in their existing order, secondary
   constructors, then methods — the business operation first, each followed by
   its private helpers, overloads adjacent — and the companion object last.
4. Nested classes next to their user; private top-level helpers after the main
   declaration. No catch-all `Utils.kt` or `Extensions.kt`.

detekt's `ClassOrdering` checks that skeleton and nothing more; ktlint has no
order rule.

The research and the rejected alternatives are in the brain's *Source file
reading order* page.
