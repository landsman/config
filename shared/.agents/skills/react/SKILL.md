---
name: react
description: Load before writing or changing a React component or hook — before an event handler, a gesture, a timer, a keyboard shortcut, a fetch or any other behaviour goes into a component body or its JSX. Carries where the logic goes (a hook, with its decision as a pure function), what gets which test, and when an inline handler is enough.
---

# React components and their logic

A component wires state to markup. Behaviour that decides something lives
outside it, where a test can call it without rendering anything.

## The split

1. **The decision is a pure function**, exported: `swipeStep(from, to)`,
   `nextIndex(at, by, length)`. Plain values in, a plain value out — no event,
   no ref, no DOM.
2. **The hook holds the state and the events**, and calls the decision:
   `useSwipe(onStep)` keeps where the finger started and returns the handlers.
   It names what it does, not where it is used.
3. **The component spreads the hook** — `<figure {...swipe}>` — and keeps the
   one line that is its own business (`if (!single) onStep(by)`).

The test for whether to split: **does the handler compare, threshold, wrap or
branch?** A threshold, a direction, a modulo, a debounce — split it, even with a
single caller, because that is the line that breaks silently. A handler that
only calls `setOpen(true)` stays inline; a hook for it is ceremony.

## Before writing one

- **Look for a hooks folder and reuse what is there.** A second hook for the
  same gesture or shortcut splits the vocabulary. No folder yet: `src/app/hooks/`
  or wherever the project keeps its shared code, file named `use-<thing>.ts`
  in the repo's file-name case.
- **Prefer the platform.** A CSS `:hover`, a `<dialog>`, `scroll-snap`, an
  `<input type>` before a hook re-implements it.

## Tests

- **The pure function gets a unit test** (vitest, or whatever the repo runs) —
  the happy path, the boundary on each side of a threshold, and the case that
  must *not* fire. Milliseconds, and it names the function that broke.
- **The behaviour gets whatever the repo already asks for end to end** —
  Playwright, Cucumber. A gesture is driven by dispatching the events
  (`locator.dispatchEvent("touchstart", { touches: [...] })`), so say in the
  report that a real device has not tried it.
- **Run the new end-to-end test once without the change** and see it fail. A
  test that passes either way tests nothing.

## Out of scope

Rendering performance (`memo`, `useCallback`) only when a measurement says so,
and state libraries only when the project already has one.
