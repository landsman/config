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
