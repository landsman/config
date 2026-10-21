# Modal dialogs — one section per item

Not to be read whole. `SKILL.md` lists the items; open the one you are working
on with the `awk` line it gives.

## 1. native

`showModal()` gives the backdrop, the top layer, a focus trap, an inert page
behind and Escape for free, and returns focus when it closes. A `<div>` has to
rebuild all of it and misses some. On a phone, the ui-mobile-first skill's item 12
applies on top.

## 2. template

One place owns the markup: a React `Modal` taking `header`/`footer` props and
children; a Latte `{embed 'modal.latte', id: …}` with `{block header}`,
`{block body}`, `{block footer}` (plus `{block hidden}` for tokens in a server
form); a Twig or Thymeleaf fragment the same way. The stylesheet is one file
keyed on the template's classes (`.modal`, `.modal-header`, `.modal-body`,
`.modal-footer`). A new dialog fills the slots and adds only its size and its
fields.

The template also owns the close `×`, top right in the header of every modal —
a form, a settings panel and a confirmation alike — so the way out is always in
the same place. The header is a grid, `grid-template-columns: 1fr auto`, the `×`
in row 1 of column 2 and everything else in column 1, so it centres on the
title and not on a header that also holds tabs. Space such a second row with
`row-gap`, never with the title's margin, which counts as part of the title's
row and drops the `×` below its middle.

The template names its own `×`: it calls the project's translator for "Close"
itself, so no dialog has to pass the label and none can forget it.

The icon is a file, `close.svg`, never SVG markup pasted into a template or a
component, whatever the stack. An icon with colours of its own, a logo, is an
`<img src>` on it. One in the text colour, like the `×`, is a CSS mask over the
same file: an empty `<span class="icon icon-close" aria-hidden="true">` with
`background: currentColor` and `mask: url(close.svg) center / contain no-repeat`,
so it follows the scheme and the hover like a glyph, and the file's own colour
does not matter. An `<img>` cannot: CSS does not reach into the file, and a
`filter` only approximates a colour. Forced colours replace the background and
the mask paints nothing, so set `forced-color-adjust: none; background:
CanvasText` there. A worked example:
[svg-icons](https://github.com/landsman/frontend-playground/tree/master/svg-icons).

Preload such an icon when it shows up without warning — the `×` of a closed
dialog, a spinner shown as the page navigates away: a mask is fetched only once
its element is displayed, so without it the icon appears after the dialog does,
or not at all. Native HTML in the `<head>`, never a script that fetches it, so
the browser finds it before any script runs:
`<link rel="preload" href="close.svg" as="image" crossorigin>`,
`crossorigin` because a mask is fetched in CORS mode, and a preload made another
way is not reused but fetched a second time. Only those icons: every preload
competes with what the page needs first.

## 3. bands

Header and footer: a tint a few percent of the text colour over the background
(`color-mix(in srgb, var(--fg) 4%, var(--bg))`) and a hairline to the body, so
they follow the theme and both schemes with no colour of their own. The dialog
has `padding: 0` and `overflow: hidden` (the bands' corners would poke out of
the radius); the sections carry the padding. The dialog is a flex column only
when open — `dialog[open] { display: flex }`; a bare `display: flex` overrides
the closed dialog's `display: none` and it never closes. The body gets
`flex: 1; min-height: 0; overflow: auto; overscroll-behavior: contain`.

The header's title resets everything the page gives its own headings — margin,
padding, border and `min-height` — at the specificity of the page's rule. A
page-title `min-height` once doubled the header of the one dialog printed
inside the content region, and of no other.

## 4. buttons

Not the site's general button style: a dialog follows the platform's dialog
convention. Every button quiet — a border and the background colour. The one
action that keeps the change is filled, last, in the bottom-right corner (green
when the project has a destructive pair, so the two cannot be confused).
A destructive action is outlined red, `margin-right: auto` to the left, away
from the button pressed without reading; it fills on hover.

The footer holds actions, not a way out: no Close or Cancel there, the `×` is
it (item 2). The one exception is a confirmation, where Cancel is an answer —
the safe one, with the focus (item 10). Either is the same close request as
Escape (item 7), so a form with changes asks first; `formmethod="dialog"` alone
would close it without asking.

## 5. motion

Inside `@media (prefers-reduced-motion: no-preference)`:

    .modal, .modal::backdrop {
      opacity: 0;
      transition: opacity 200ms ease-out, transform 200ms ease-out,
        overlay 200ms allow-discrete, display 200ms allow-discrete;
    }
    .modal { transform: translateY(8px); }
    .modal[open], .modal[open]::backdrop { opacity: 1; transform: none; }
    @starting-style {
      .modal[open], .modal[open]::backdrop { opacity: 0; }
      .modal[open] { transform: translateY(8px); }
    }

`overlay` and `display` with `allow-discrete` keep it in the top layer until
the fade-out ends; `@starting-style` is the entry. Backdrop `rgb(0 0 0 / 0.5)`
or so, as a token. Content the dialog shows is emptied only after
`getAnimations()` have finished, or the fade-out shows an empty box.

## 6. page-lock

`html:has(dialog:modal) { overflow: hidden }` — CSS, so Escape and a submit
unlock it as well as Cancel; `:modal`, not `[open]`, which also locks the page
behind a non-modal `show()`. `scrollbar-gutter: stable` on the page, so the
scrollbar disappearing does not shift it sideways on every open.

## 7. escape

Escape closes every modal, always — the one exit a keyboard user can count on
([APG](https://www.w3.org/WAI/ARIA/apg/patterns/dialogmodal/)). `showModal()`
gives it for free; never swallow it in a `keydown` handler. The only thing
allowed to hold it back is the unsaved-changes question (item 9), and then the
question itself closes on Escape.

Route every way out — Escape, the `×`, a confirmation's Cancel, a click outside —
through one close request, so one guard sees them all: the `×` and Cancel call
`dialog.requestClose()` where it exists (it fires `cancel` like Escape does),
and the guard is called directly where it does not.

## 8. dismiss

`closedby="any"` closes on a click outside, through the same `cancel` as
Escape. Where the browser does not know it
(`!("closedBy" in HTMLDialogElement.prototype)`), handle it: a click whose
target is the dialog element itself landed on the backdrop → the same close
request.

## 9. unsaved

A dialog holding a form asks before discarding what was typed — on Escape, the
`×` and a click outside alike. Saving is the only way out
that does not ask.

- **Dirty** means the form differs from when the dialog opened: snapshot
  `new URLSearchParams(new FormData(form)).toString()` on open and compare,
  rather than a flag set on `input`, which stays set when a change is undone.
- **Guard `cancel`**: dirty → `event.preventDefault()`, then ask.
- **Guard `close` too.** `cancel` is not always cancelable: Chromium ignores
  `preventDefault()` on a second Escape with no user activation in between, and
  can skip `cancel` entirely right after the click that opened the dialog
  ([Chromium 41484805](https://issues.chromium.org/issues/41484805),
  [whatwg/html#11230](https://github.com/whatwg/html/issues/11230)). So on
  `close`, if still dirty and not confirmed, `showModal()` again and ask — the
  fields keep their values, a closed dialog is not reset.
- **The question** is a second modal from the same template: "Discard
  changes?", *Keep editing* as the quiet default with focus on it, *Discard*
  as the danger button. `window.confirm()` only where the project already uses
  it; it cannot be styled and an embedded webview may not show it at all.
- **After a save** clear the snapshot first, so closing does not ask.

## 10. accessible

`showModal()` already makes the page behind inert, traps Tab inside and
closes on Escape. What is still the template's job
([APG](https://www.w3.org/WAI/ARIA/apg/patterns/dialogmodal/),
[MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/dialog)):

- **A name**: `aria-labelledby` on the dialog pointing at the header's heading;
  without one a screen reader announces only "dialog". `aria-describedby` for
  a short line of explanation, never for a whole form.
- **Focus in**: the first field of a form dialog (`autofocus` on it); the
  dialog itself (`tabindex="-1"`, then `dialog.focus()`) for content without
  one, so the `×`'s ring does not flash on every open; the least destructive
  button of a confirmation. Never the `×` itself.
- **Focus back**: to the element that opened it. The browser restores it when
  it can; restore it yourself when that element was re-rendered meanwhile.
- **The `×`** is a `<button type="button">` named by `aria-label` with the
  translated "Close", and no `title` saying the same — a screen reader reads
  that a second time, as the description. The icon `aria-hidden`, drawn in
  `currentColor` set from the text colour (`color-mix(in srgb, var(--fg) 68%,
  transparent)`), never a fixed grey: it flips with the scheme the way the
  bands do, where a grey picked on a light band all but vanishes on a dark one.
  Measure it at 3:1 or more against the band (WCAG 1.4.11) in light and in
  dark, and its focus ring too. A target of at least 24px (44px on a phone);
  negative margins keep it from making the band taller than its title. Its
  focus ring is an `outline`, not a `box-shadow`: forced-colours mode drops
  shadows, and a borderless icon button would show no focus at all.
- **Nothing positive in `tabindex`**, and every action reachable by keyboard
  in the order it reads.
- **Reduced motion** turns the fade off (item 5), and the text inside keeps
  its contrast against the tinted bands.

## 11. forms

Forms do not nest: a dialog printed inside another form submits that one, and
Enter in the dialog's field triggers the outer form's first submit button.
Render the dialog outside it — the end of `<body>`, a portal, another region.

## 12. sticky

A sticky `<thead>` sticks to the scrollport's content edge, so `padding-top`
on the body is a strip where rows scroll through above the header. Space the
body's first child with a margin instead, which scrolls away with it.
