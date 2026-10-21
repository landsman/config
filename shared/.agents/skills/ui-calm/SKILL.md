---
name: ui-calm
description: Load before writing or reviewing what a web UI does around an action — a save, an add, a delete, a form submit — its loading state, its success or error feedback, a toast or snackbar, a form inside a dialog, and when a UI "feels jumpy" or "busy". Carries one loading state per action, no toasts for success or errors, a growing modal pinned by its top, Enter submitting, and the first field focused.
trigger-keywords: toast*, snackbar*, notifikac*, spinner*, loading state*, skeleton*, jumpy, busy UI, calm UI, klidn*
---

# Calm UI

**An action shows one change of state, where the user is looking.** From Max
Schmitt's [A Simple Guide to Calm UI](https://maxschmitt.me/posts/calm).

1. **One loading state.** The spinner stays on the button that started the
   action until everything it changes has refetched. Not button spinner, then
   list skeleton, then content: that is three flickers for one click. With a
   query library, await the invalidation inside the mutation
   (`await queryClient.invalidateQueries(…)` in TanStack Query) so `isPending`
   covers both.
2. **No toast for success.** The result is the confirmation: the new row in
   the list, the deleted one gone, the field showing its saved value.
3. **No toast for an error.** It appears far from the click, worst on a wide
   screen, and vanishes on a timer before anyone reads it. Show it beside the
   form or the field that caused it, and keep it until the next attempt.
4. **A modal whose height can change is pinned by its top.** Centred, an error
   line appearing moves the submit button under the cursor. For a native
   `<dialog>`: `margin-block: 10dvh auto`, so it grows only downward. This
   overrides the [optical centre](../ui-optical-centre/SKILL.md) for such a
   dialog; a panel that never changes height may still sit there.
5. **Enter submits.** A real `<form>` with a submit handler
   (`<form onSubmit={save}>` in React) and a `type="submit"` button, never
   `onClick` on a button.
6. **The first field has focus** when a dialog or an inline form opens
   (`autofocus` on it).

The rest of a dialog — its template, buttons, closing and accessibility — is
in the [ui-modal-dialogs](../ui-modal-dialogs/SKILL.md) skill.

A toast still has a place for what has no spot on screen: an event nobody
triggered (a background sync failed, a new message arrived) or an undo for an
action whose result is already visible.
