# Localisation

User-facing text goes through a localisation key, never into the source as a
literal. The reason is that the second language is what makes the first one
expensive: a hardcoded string is invisible until someone has to find all of
them, and by then they are spread across templates, validators and error paths.

Use what the project already has, and never introduce a solution without asking
which one. "Already has" usually means `messages.properties` through Spring
Boot's `MessageSource`, `ResourceBundle` on plain Java or Kotlin, or i18next,
Lingui, react-intl, Angular i18n or plain JSON files on the frontend. An
existing library is not replaced as a side effect of adding a string.

For a new string:

- Add the key, and a translation in every language the app already ships. If a
  translation cannot be written reliably, add the key with a placeholder and say
  which languages are still missing — a quietly English row reads as done.
- Reuse a key before adding a near-duplicate.
- Keys carry no spaces, follow whatever convention the project already uses, and
  name the thing rather than its position: `user.profile.saveButton`,
  `error.invalidCredentials`, not `label1`.
- Localised text is for display only — never an identifier, a config value, an
  API field, a database value, or a branch in business logic. That turns
  translating a word into a behaviour change.

## Write the accented characters, not `\uXXXX`

A translation file holds the letters it means. `Nastavení se nepodařilo uložit`,
never `Nastaven\u00ed se nepoda\u0159ilo ulo\u017eit` — and the same for every
other alphabet a project ships.

The escapes are a reflex from Java 8 and earlier, where `.properties` were read
as ISO-8859-1 and `native2ascii` existed to work around it. **Java 9 reads
property resource bundles as UTF-8** (falling back to ISO-8859-1 only if the
bytes are not valid UTF-8), so on anything current the escape buys nothing and
costs a file nobody can read, review or grep. A reviewer cannot tell a typo from
a correct word, a diff of a one-letter fix is unreadable, and searching for a
phrase someone reported finds nothing.

Before writing a line into an existing file, **look at the line above it.** The
repo has already made this decision and the answer is sitting there; matching it
is the whole rule. Introducing escapes into a file that has none is the failure
this is about, and it is invisible in review precisely because escaped text
looks like nothing at all. If a project genuinely does escape — an old runtime,
a `native2ascii` step still in the build — follow it there and say so, rather
than converting the file as a side effect of adding a string.

This is about the source file, not the wire. Encoding a character because a
format demands it (a JSON `\u` escape a serialiser emits, a URL percent-encoding)
is not the same thing and is fine.

## Email templates

Same rule, and the subject line is the one that gets missed. Localise the
subject, the headings, the body, the button labels, the footer. Keep dynamic
values — names, order numbers, dates, links — as placeholders in the template
instead of concatenating around a localised fragment, because the word order is
not the same in every language. Dates, numbers, currencies and plurals go
through the framework's locale-aware formatting.

Whether that is keys or a template per language is a decision the project has
already made; follow it.

Templates share one base layout — header, footer, branding, styling — and hold
only their own content. Copy-pasted markup between two templates is a footer
that gets fixed in one of them.

Text baked into an image is not translatable, not selectable and not readable by
a screen reader, so use HTML text. If a banner or a logo genuinely has to carry
words, either ship a variant per language or say up front that the localised
assets are missing.
