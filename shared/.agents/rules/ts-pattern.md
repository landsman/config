---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# Branching in TypeScript: ts-pattern

**A branch on the shape of one value is a
[ts-pattern](https://github.com/gvergnaud/ts-pattern) `match`, not a `switch`,
an `if`/`else` chain or a nested ternary.** The cases sit in one column, each
handler gets the value already narrowed, and `.exhaustive()` turns a variant
someone adds to the union later into a compile error at every place that does
not handle it yet.

Where it applies:

- a discriminated union: `type`, `kind`, `status`, an action in a reducer;
- what a component renders for a fetch state (loading, error, empty, data);
- a dispatch on a string: a route, a command, a file extension;
- several fields at once, as a tuple or an object pattern: `match([a, b])`.

```ts
return match(state)
  .with({ status: "loading" }, () => <Spinner />)
  .with({ status: "error" }, ({ error }) => <ErrorLine error={error} />)
  .with({ status: "done", items: [] }, () => <Empty />)
  .with({ status: "done" }, ({ items }) => <List items={items} />)
  .exhaustive();
```

- **A closed union ends in `.exhaustive()`.** `.otherwise()` there switches
  off the very check that is the reason to use it. `.otherwise()` is for an
  open input, such as a string from a URL. The router in `homelab/ip-service`
  (`src/handler.ts`) is that case.
- **Reach for the patterns before a handler that tests by hand:**
  `P.select()` to pass a nested field in, `P.union(…)` for several values in
  one branch, `P.nullish`, `P.string.startsWith(…)`, `P.when(fn)` as a last
  resort.
- **`.returnType<T>()`** when every branch has to produce one type, as a
  reducer does.
- **`isMatching(pattern)`** as a type guard for a shape inside the app. Input
  from outside, such as a request body or an API response, still goes through
  the project's validator (zod, valibot), because that one says what is wrong
  and `isMatching` only says no.

**Not for** a guard clause with an early return, a single boolean `if`, or a
hot loop over thousands of items, where a `switch` costs nothing and a `match`
builds a chain on every call. `.exhaustive()` costs some compile time, as the
README itself says. On a union of a few dozen variants, check that `tsc`
stays fast.

**A project without it:** in my own repos, add it (`bun add ts-pattern`, or
the repo's package manager) together with the first `match`. In a repo someone
else owns, propose it and wait. Do not add it as a side effect of a fix. Do not
rewrite working `switch` statements in a file you came to change for something
else. Convert the branch you touch.
