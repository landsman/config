# Modal dialogs — one section per item

Not to be read whole. `SKILL.md` lists the items; open the one you are working
on with the `awk` line it gives.

## 1. native

`showModal()` gives the backdrop, the top layer, a focus trap, an inert page
behind and Escape for free, and returns focus when it closes. A `<div>` has to
rebuild all of it and misses some. On a phone, the mobile-first skill's item 12
applies on top.

## 2. template

One place owns the markup: a React `Modal` taking `header`/`footer` props and
children; a Latte `{embed 'modal.latte', id: …}` with `{block header}`,
`{block body}`, `{block footer}` (plus `{block hidden}` for tokens in a server
form); a Twig or Thymeleaf fragment the same way. The stylesheet is one file
keyed on the template's classes (`.modal`, `.modal-header`, `.modal-body`,
`.modal-footer`). A new dialog fills the slots and adds only its size and its
fields.

## 3. bands

Header and footer: a tint a few percent of the text colour over the background
(`color-mix(in srgb, var(--fg) 4%, var(--bg))`) and a hairline to the body, so
they follow the theme and both schemes with no colour of their own. The dialog
has `padding: 0` and `overflow: hidden` (the bands' corners would poke out of
the radius); the sections carry the padding. The dialog is a flex column only
when open — `dialog[open] { display: flex }`; a bare `display: flex` overrides
the closed dialog's `display: none` and it never closes. The body gets
`flex: 1; min-height: 0; overflow: auto; overscroll-behavior: contain`.

## 4. buttons

Not the site's general button style: a dialog follows the platform's dialog
convention. Every button quiet — a border and the background colour. The one
action that keeps the change is filled, last, in the bottom-right corner (green
when the project has a destructive pair, so the two cannot be confused).
A destructive action is outlined red, `margin-right: auto` to the left, away
from the button pressed without reading; it fills on hover. Cancel is
`formmethod="dialog"` in a form, so it closes without a line of script.

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

## 7. dismiss

`closedby="any"` closes on a click outside. Where the browser does not know it
(`!("closedBy" in HTMLDialogElement.prototype)`), handle it: a click whose
target is the dialog element itself landed on the backdrop → `close()`. Leave
it off for a dialog that asks before discarding edits; that one closes through
its own Cancel. A close `×` in the header when the dialog has no footer.

## 8. focus

`showModal()` then `dialog.focus()` (with `tabindex="-1"`), so a close button's
focus ring does not flash on every open and keys meant for the content reach
it. A form dialog may focus its first field instead.

## 9. forms

Forms do not nest: a dialog printed inside another form submits that one, and
Enter in the dialog's field triggers the outer form's first submit button.
Render the dialog outside it — the end of `<body>`, a portal, another region.

## 10. sticky

A sticky `<thead>` sticks to the scrollport's content edge, so `padding-top`
on the body is a strip where rows scroll through above the header. Space the
body's first child with a margin instead, which scrolls away with it.
