---
name: react
description: Load before writing or changing a React component or hook — before a handler, a gesture, a timer, a filter, a validation, a fetch or any other logic goes into a component body or its JSX. Carries where the logic goes — render, a handler, an Action or an Effect, by what causes it — then a hook with its decision as a pure function, what gets which test, and when inline is enough.
trigger-keywords: react, reactu, jsx, tsx, useEffect, useState, hydration, suppressHydrationWarning, localStorage, ssr
---

# React components and their logic

A component wires state to markup. Logic that decides something lives outside
it, where a unit test can call it without rendering anything.

## The split

1. **The decision is a pure function**, exported: `swipeStep(from, to)`,
   `nextIndex(at, by, length)`, `visibleItems(items, query)`. Plain values in, a
   plain value out — no event, no ref, no DOM.
2. **The hook holds the state and the events**, and calls the decision. It
   names what it does, not where it is used.
3. **The component spreads the hook** and keeps only the line that is its own
   business.

**Split when the code compares, thresholds, wraps, branches, filters, sorts,
formats or validates** — in a handler or in the render body alike, and even with
a single caller, because that is the line that breaks silently. A handler that
only sets state stays inline; a hook for it is ceremony:

```tsx
<button onClick={() => setOpen(true)}>  // stays as it is
```

## Where it runs, by what causes it

Ask what makes the code run before deciding where it goes. An Effect is for
staying in sync with something React does not own, not a second event system.

| Cause | Goes in |
|---|---|
| a value the render needs | the render body — computed, never stored |
| a click, an input, a submit, a drag | the event handler |
| a form or an async mutation in flight | an Action with `useActionState` (React 19+) |
| a subscription, a timer, a browser API, a third-party widget | an Effect, with its cleanup |

- **Derived is not state.** `useState` plus a `useEffect` that sets it from
  props renders once with the stale value, then again; `const fullName =
  first + " " + last` is right on the first render.
- **What a user did runs where they did it.** A `submitted` flag that an Effect
  watches to send the order sends it again on the next dependency change; the
  handler sends it once.
- **A key is a stable id.** An array index breaks a list that reorders or
  filters; a new `key` on purpose resets a subtree whose identity changed.
- **`use(promise)` needs a promise made outside the render** — a loader, a
  cache, a parent. One created in the component is a new promise every render.
- **Read the React version first.** Actions and `use` are React 19; on 18 the
  mutation goes in the handler with its own pending state.

## Examples

A gesture. Before, the threshold sat in the JSX where no test could reach it:

```tsx
<figure
  onTouchStart={(e) => (start.current = e.touches[0].clientX)}
  onTouchEnd={(e) => {
    const dx = e.changedTouches[0].clientX - start.current;
    if (Math.abs(dx) > 50) onStep(dx < 0 ? 1 : -1);
  }}
>
```

After — `use-swipe.ts`, then the component:

```tsx
export function swipeStep(from: Point, to: Point): -1 | 0 | 1 {
  const dx = to.x - from.x;
  if (Math.abs(dx) <= 50 || Math.abs(dx) <= Math.abs(to.y - from.y)) return 0;
  return dx < 0 ? 1 : -1;
}
export function useSwipe(onStep: (by: number) => void) { /* start ref, handlers */ }

const swipe = useSwipe((by) => { if (!single) onStep(by); });
<figure {...swipe}>
```

`use-swipe.test.ts` pins the boundary — 50 px stays put, 51 px steps — and a
vertical drag that must not fire.

Data shaping. `items.filter(...).sort(...)` in the render body becomes
`visibleItems(items, query)` beside the component, tested with an empty query, a
miss and the order. No hook needed: a pure function the component calls is
enough when there is no state of its own.

## Before writing one

- **Look for a hooks folder and reuse what is there.** A second hook for the
  same gesture or shortcut splits the vocabulary. No folder yet: put it where
  the project keeps shared code (`src/app/hooks/`, say), named `use-<thing>.ts`
  in the repo's file-name case.
- **Prefer the platform.** A CSS `:hover`, a `<dialog>`, `scroll-snap`, an
  `<input type>` before a hook re-implements it.

## Tests

- **The pure function gets a unit test** (vitest, or whatever the repo runs) —
  the happy path, each side of a boundary, and the case that must *not* fire.
  Named after the file it tests — `use-swipe.ts` → `use-swipe.test.ts` — in
  whatever folder the repo keeps its tests. Import it the way the app does
  (`@/app/hooks/use-swipe`), not by counting `../`.
- **`renderHook` only for the hook's own state.** Calling the function directly
  is the reason for the split.
- **The behaviour gets whatever the repo asks for end to end.** In Playwright a
  gesture is dispatched (`locator.dispatchEvent("touchstart", { touches: [...] })`),
  so say in the report that a real device has not tried it.
- **Run the new end-to-end test once without the change** and see it fail. A
  test that passes either way tests nothing.

## Browser-only state on a server-rendered page

**React's first client render must match the server's HTML.** Rendering from
`localStorage`, `window`, the theme or `Date` breaks that: a hydration
mismatch. What fixes it depends on what the state moves.

- **It moves the layout** (a sidebar open, a density, a collapsed panel): an
  inline script in the layout applies it to the DOM before hydration and leaves
  the value on `window`; `useState` starts from that value, so React renders
  the same classes the script set. SSR stays, nothing flickers.
- **A small leaf control** (a theme toggle): rendering nothing until mounted
  (`useIsClient`), or `use(browser())` with a `<Suspense>` fallback on React
  19.3+, is fine. Never on a layout: its whole subtree leaves SSR with it.
- **A visual that follows that state** (a backdrop behind the sidebar): always
  in the HTML, shown by CSS keyed off the class the script already sets
  (`group` on the sidebar, `hidden group-[.left-0]:block` on the backdrop). No
  second state to mismatch.

```tsx
function initSidebar() {
  const open = localStorage.getItem("sidebar") === "true";
  document.querySelector("[data-sidebar]")?.classList.toggle("left-0", open);
  window.__SIDEBAR__ = open;
}
<script dangerouslySetInnerHTML={{ __html: `(${initSidebar})()` }} />

const [open, setOpen] = useState(() => typeof window === "undefined" ? false : window.__SIDEBAR__);
```

Not these:

- **`localStorage` in the `useState` initializer** behind `typeof window`:
  still a mismatch, the server says `false` and the client `true`.
- **`localStorage` in `useEffect`**: no mismatch, a visible flicker after mount.
- **`suppressHydrationWarning`** hides the warning and fixes nothing, one
  level deep. Only where a script is known to edit that element: `<html>`
  under next-themes.

The production build stays silent on attribute mismatches; how a test catches
them is P13 in the `e2e-tests` skill. Worked through in
[this post](https://www.gmoniava.com/blog/hydration-mismatch-errors-and-how-to-fix-them).

## Out of scope

Class components and server components (no hooks there), `memo`/`useCallback`
until a measurement asks for it, and state libraries the project does not
already have.
