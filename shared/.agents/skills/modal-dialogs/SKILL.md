---
name: modal-dialogs
description: Load before building, restyling or reviewing a modal dialog in any web UI — a <dialog>, a confirm, an edit form in a popup, a settings panel, a photo viewer — in React, a server template (Latte, Twig, Thymeleaf) or plain HTML. Carries the one design every modal of mine shares (a template with header, body and footer slots), its buttons, the fade of the dialog and its backdrop, the page lock, closing on Escape and on a click outside, asking before unsaved changes are lost, what makes it accessible, and the traps already met.
trigger-keywords: modal*, dialog*, popup*, pop-up*, dialóg*, okn*, backdrop*, showModal, overlay*, unsaved, neuložen*, requestClose, closedby
---

# Modal dialogs

**Every modal looks and behaves the same, in every project.** One template
with slots, used by every dialog; never a dialog styled on its own. If the
project has no template yet, make it before the second dialog, and move the
first one onto it.

## The list

1. **native** — `<dialog>` opened with `showModal()`, never a `<div>` overlay.
2. **template** — one component or partial with `header`, `body`, `footer` slots.
3. **bands** — header and footer set apart from the body; only the body scrolls.
4. **buttons** — quiet by default, one filled primary last, a destructive one outlined left.
5. **motion** — the dialog and its backdrop fade in and out together, 200ms.
6. **page-lock** — the page behind does not scroll or jump sideways.
7. **escape** — Escape always closes it; every way out goes through one close request.
8. **dismiss** — a click outside closes it too, through the same request.
9. **unsaved** — a form with changes asks before any way out discards them.
10. **accessible** — a name, focus in and back out, a labelled close button.
11. **forms** — a dialog never sits inside another `<form>`.
12. **sticky** — no padding-top on a body that holds a sticky header.

Open only the item you are working on — `sections.md` is not read whole:

    awk '/^## 4\. /{f=1;print;next} /^## /{f=0} f' sections.md
