---
name: typescript
description: Load before designing or reviewing a TypeScript type — a public function's signature, a config or registry object, a union of states, a generic helper — or before writing `as`, `!`, `any` or `JSON.parse` in a `.ts` or `.tsx` file, or relying on what `strict` checks. Carries proving a type with one accepted and one rejected use, `as const satisfies` over an annotation, parsing instead of asserting, and the flags `strict` does not turn on.
trigger-keywords: typescript, satisfies, as const, tsconfig, strict, generic, type assertion
---

# TypeScript types that reject wrong code

A type earns its place by rejecting a program that would break. Imports and
branching have rules of their own (ts-imports, ts-pattern); this is the type
itself.

## Prove it with a rejected use

Before choosing a technique, write the call it must accept and the one it must
refuse, and keep both as a check. `// @ts-expect-error` fails the build when
the error it expects goes away, so a type that quietly widened is caught:

```ts
const ok: '/save' = routes.save.path;
// @ts-expect-error a command the registry does not have
routes.delete;
```

Run the project's type check, not the editor's opinion of it. A type that
accepts everything passes every accepted use.

## Keep what inference already knows

An annotation on a value replaces what TypeScript inferred with what was
written, and the literals are gone. `satisfies` (TS 4.9+) checks the shape and
keeps them:

```ts
type Command = 'save' | 'load';

const broad: Record<Command, Route> = { save: { path: '/save' }, load: { path: '/load' } };
broad.save.path; // string

const routes = {
  save: { path: '/save' },
  load: { path: '/load' },
} as const satisfies Record<Command, Route>;
routes.save.path; // '/save' — and a missing command is still an error
```

- **Annotate a public boundary** whose contract must outlive the
  implementation; infer inside it.
- **Derive a type from the value that owns it** — `keyof typeof registry`, not
  a second union kept in step by hand. Keep two types apart when two parties
  own them (a domain type and an API payload), even while their fields match.
- Neither `satisfies` nor `as const` does anything at runtime.

## An assertion is a claim

`as`, `!` and `any` tell the compiler to stop checking. Each is a gap to
justify, not a fix.

- **External data is `unknown` until a parser says otherwise.**
  `JSON.parse(text) as Settings` checks nothing; parse it through the schema the
  project already uses (zod, valibot, a hand-written guard) and test a malformed
  input too.
- **A type guard that does not check is an assertion with a nicer name.**
  `(x): x is User => true` is worse than `as`, because it looks safe.
- **Keep an assertion the compiler cannot express** — an invariant really
  holding — local, with a comment saying why, and a test that the invariant
  holds.

## What `strict` does not check

Read the effective `tsconfig` before relying on a guarantee. `strict` leaves two
flags off:

- **`noUncheckedIndexedAccess`** — without it `xs[0]` on a `number[]` is a
  `number`, even on an empty array, and so is `record[key]`.
- **`exactOptionalPropertyTypes`** — without it `{ a?: string }` accepts
  `{ a: undefined }`, so "absent" and "set to undefined" are the same value.

Where the code depends on either difference, handle it explicitly — a check for
`undefined`, `Partial` against an explicit `| undefined`. Turning a flag on
for the whole project is its own change, with every caller it breaks in view,
not a side effect of one fix.
