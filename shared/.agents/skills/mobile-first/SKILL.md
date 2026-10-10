---
name: mobile-first
description: Load before writing or reviewing the layout of a web page or component — CSS, a media query, a viewport unit, anything pinned to an edge, a tap target, a form field, a dialog — and when something looks wrong on a phone. Carries the phone as the base case, the browser chrome that covers the page, viewport units, safe areas, touch and input, and how to test what an emulator cannot show.
trigger-keywords: mobile*, mobil*, phone*, telefon*, responsive, viewport, svh, dvh, safe-area, touch
---

# Mobile first

The phone is the design. A wider screen is the phone with room to spare, not
the reverse: a layout drawn on a desktop and squeezed down hides its failures
exactly where most visitors are.

## The list

1. **base** — unprefixed CSS is the phone; wider screens add.
2. **bottom-edge** — the bottom ~90px of a phone is not reliably the page's.
3. **viewport-units** — `100vh` is taller than the screen; know which `*vh` you mean.
4. **safe-area** — `env(safe-area-inset-*)` is zero unless you opt in.
5. **tap-targets** — 44px to aim at, never under 24px.
6. **no-hover** — nothing may exist only on `:hover`.
7. **inputs** — 16px text in a field, and the right keyboard.
8. **width** — no horizontal scroll at 320px.
9. **reach** — a gesture beside every small control a thumb has to hit.
10. **no-jump** — reserve room for what appears after the script runs.
11. **short-screen** — a landscape phone is 320px tall.
12. **dialogs** — lock the page behind, contain the scroll inside.
13. **testing** — an emulator has no browser chrome; assert distances.

Each item below stands alone.

## 1. base

Write the phone rules without a media query and widen with
`@media (min-width: …)`. One breakpoint is usually enough; add one when the
layout actually breaks, not per device. A project that already branches the
other way (`max-width`) keeps its convention — do not flip it as a side effect.

## 2. bottom-edge

Safari on iOS 26 floats its address bar over the bottom of the page, about 90px
on a phone, and draws the page underneath it. `100svh` counts that strip as
page. A menu pinned to the bottom of a `min-height: 100svh` body landed behind
the bar, out of reach — found on a real site, invisible in every test.

- Nothing that must be tapped sits in the bottom ~90px at rest: leave room under
  it (112px worked), or let it follow the content instead of the edge.
- The same goes for `position: fixed; bottom: 0` bars and cookie banners.
- Other browsers put their bar there too, as an option; design for the bar
  being there.

## 3. viewport-units

On mobile `100vh` is the *large* viewport — the screen with the toolbars
retracted — so a `100vh` section is taller than what is visible on load.

- `svh`: smallest viewport, stable. Right for `min-height`.
- `dvh`: follows the toolbar as it slides; anything sized by it moves on scroll.
- `lvh`: the old `vh`.

Write a fallback first, `min-height: 100vh; min-height: 100svh;`. None of these
subtracts an overlaid bar (item 2).

## 4. safe-area

The notch, the rounded corners and the home indicator. With the default
viewport the browser keeps the page out of them and the insets read 0. Add
`viewport-fit=cover` to the viewport meta only when the page should paint
edge to edge, and then pad what must stay visible:
`padding-bottom: max(var(--page-padding), env(safe-area-inset-bottom))`.

The viewport meta itself is `width=device-width, initial-scale=1`. Never
`maximum-scale=1` or `user-scalable=no`: it takes zoom from people who need it.

## 5. tap-targets

Aim for 44×44 CSS px (Apple; Material says 48dp); WCAG 2.5.8 AA sets 24×24 as
the floor. A small icon gets the size from padding, and a negative margin keeps
it from shifting the layout. Leave a gap between neighbours so a thumb does not
hit two.

## 6. no-hover

A tooltip, a menu or a control that appears only on `:hover` does not exist on
a phone, and a tap leaves iOS's hover state stuck. Gate hover-only effects with
`@media (hover: hover)`; whatever they reveal must be reachable by a tap or
already visible.

## 7. inputs

A field under 16px makes iOS Safari zoom in on focus, and it does not zoom back.
Set `font-size: max(16px, 1em)` on `input, select, textarea`. Pick the keyboard:
`type="email|tel|url|number"`, `inputmode`, `autocomplete`, `enterkeyhint`.

## 8. width

Test at 320px wide, the narrowest phone still sold. The usual culprits: a long
word or URL (`overflow-wrap: anywhere`), an image (`max-width: 100%`), a table
or a code block (scroll inside its own `overflow-x: auto` container, never the
page), a fixed `width` in px.

## 9. reach

Arrows at the edges of a gallery or a carousel are hard to hit one-handed. Add
the swipe, keep the arrows for a mouse and a keyboard. Primary actions belong in
the lower half — above the bar of item 2.

## 10. no-jump

An element that only appears once JavaScript runs (a theme switch, a consent
banner, a late image) shifts everything below it on a phone, where a few pixels
is a line. Render it hidden with `visibility: hidden` so it holds its place, and
give images `width`/`height` or `aspect-ratio`.

## 11. short-screen

Centring with `justify-content: center` clips the top of content taller than the
viewport, out of scroll reach. Centre with auto margins, which collapse to 0
when there is no room. A landscape phone is ~320px tall; check it.

## 12. dialogs

While a dialog is open the page behind should not scroll:
`html:has(dialog[open]) { overflow: hidden }`. Give the dialog's own scroller
`overscroll-behavior: contain` so reaching its end does not drag the page.

## 13. testing

A Playwright phone viewport — even `devices['iPhone 15']`, with its touch and
pixel ratio — has no address bar, no notch and no keyboard. The page looks
right there and wrong on the phone. So:

- **Assert distances, not screenshots**: "the menu ends more than 90px above the
  bottom", "the links share one row", "nothing is wider than the viewport"
  (`document.documentElement.scrollWidth <= innerWidth`).
- **Check on a real phone** or the iOS Simulator (Xcode) before calling a layout
  change done, and say when that did not happen.
- A screenshot from the user's phone is the best bug report there is; read the
  browser chrome in it, not just the page.
