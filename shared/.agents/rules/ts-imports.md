---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/package.json"
---

# Imports in TypeScript

**An import that leaves its own folder goes through an alias, never `../`.**
`../../../lib/money` says nothing about where it lands, breaks when the file
moves, and differs for the same module from one file to the next. `#lib/money`
reads the same everywhere. A sibling in the same folder stays `./`, since a
test beside its code gains nothing from an alias.

The alias is the `imports` field of `package.json`, one entry per top-level
folder under `src/`:

```json
"imports": {
  "#lib/*": "./src/lib/*",
  "#components/*": "./src/components/*"
}
```

```ts
import { formatMoney } from "#lib/money";
```

Why this and not the alternatives, checked on 2026-10-20 by running each one:

| Alias | Bun 1.4 | Node 26 | tsc 7 (`bundler`) | Vite 8 |
|---|---|---|---|---|
| `"#lib/*"` in `package.json` | yes | yes | yes | yes |
| `"#/*"` in `package.json` | **no** | yes (Node 24.14+) | yes | not tried |
| `"@/*"` in tsconfig `paths` | yes | **no** | yes | needs a plugin or `resolve.alias` |

`paths` is only a hint to the type checker, so every runtime and bundler has to
be taught it again. `imports` is Node's own standard, and each tool reads it
from one place. Keep `#/*` out until Bun resolves it, so a script still runs
under `bun`. TypeScript reads `imports` with `moduleResolution` set to
`bundler`, `node16` or `nodenext`, but not under the legacy `node`.

**In a repo that already uses `paths` with `@/`, keep it.** Do not migrate as a
side effect. Add new folders the way the repo already does.

To enforce it, ESLint's `no-restricted-imports` with
`patterns: [{ group: ["../*"], message: "import through a #alias" }]` is enough.
