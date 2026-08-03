# Working in this repo

Conventions for any coding agent, which is why this file is `AGENTS.md` and not
a vendor's name. `CLAUDE.md` is a symlink to it, because that is the filename
Claude Code looks for — edit this file, never the link. Longer notes that no
agent needs loaded on every turn live in [`.docs-llm/`](.docs-llm/README.md);
the untracked `.claude/` at the root is the tool's own scratch space.

## An app goes on every platform that can run it

Adding an app is not done when it installs on the Mac. The machines multi-boot,
so a one-platform entry is a gap someone finds later on the wrong laptop.

- **Portable CLI tooling** — one `brew` line in the [Brewfile](Brewfile), no
  guard. Homebrew runs on both.
- **A cask with a Linux build** — outside the `if OS.mac?` guard, same as
  `1password-cli` and `localsend`.
- **A macOS-only cask** — inside the guard, *and* the Linux half in
  [`os/ubuntu/install-apps.sh`](os/ubuntu/README.md): the vendor's apt repo with
  its key pinned by fingerprint, a row in that README's package table, and a
  case in `install-apps.test.sh`.
- **Only a hand-download** — a `.deb` with no repo, no checksum, nothing to pin
  — is still worth installing when the app is one in daily use. It goes in the
  same script, fetched straight from the vendor, but as a *stated* exception:
  what is missing, what is left vouching for it, and how it gets updated, spelled
  out in the README beside it. Discord is the precedent. The exception is per
  app — the others in the same shape stay out.
- **No Linux build at all** — then it belongs in that README's *Not installable
  this way* table, with the reason. An unrecorded gap reads as an oversight; a
  recorded one is a decision.

Work out which of the five applies before asking. Ask when the answer would
introduce machinery the repo does not already have — a first flatpak, a first
snap, a first curl-a-tarball installer — because that is a bigger decision than
the app itself.

## GitHub Actions versions

Reference actions by their stable major tag — `actions/checkout@v7`, not a
commit SHA. The major tag is the version I read, compare and bump; a SHA tells
me nothing at a glance and turns a version bump into a lookup.

Use the **latest** major, and check what that is before writing it. Same for
every action, GitHub's own or a third party's. A model's idea of the current
version is whatever was true when it was trained: `actions/checkout` was written
here as `@v4` while v7 was out, and the repo next door still says `@v5`. Look it
up, do not recall it:

    gh api repos/<owner>/<action>/releases/latest --jq .tag_name

This holds even when a scanner asks for the SHA. `make security` excludes that
rule by id for exactly this reason. If a tool disagrees with something written
down here, change the tool's configuration, not the workflow — and say so.

## Pull requests

When the work is done and pushed, open the pull request. Do not ask first —
this is standing permission for this repo, so that the last step of a change
is not a round trip to hear "yes".

Opening only. Merging stays a decision I make, and so does anything that
touches a branch other than the one being worked on.

## Localisation

When building an application, never hardcode user-facing text. Always use localization (i18n) keys. If the project does not already have a localization solution, ask the user which library or framework they want to use before introducing one.

Use the localization approach that matches the project's existing technology stack:

- **Java/Kotlin (Spring Boot):** typically `messages.properties` files (for example `messages.properties`, `messages_en.properties`, `messages_de.properties`) configured through Spring Boot's `MessageSource` support. Do not introduce a different solution unless requested.
- **Java/Kotlin (non-Spring):** use the localization mechanism already present in the project, such as `ResourceBundle`.
- **Frontend (TypeScript/JavaScript):** use the project's existing solution, such as **i18next**, **Lingui**, **FormatJS (react-intl)**, Angular i18n, or simple JSON translation files if the project already uses them. Do not replace an existing localization library.

When adding new user-facing text:

- Add a localization key instead of a hardcoded string.
- Add translations for every language already supported by the application. If translations cannot be provided reliably, add the key with a placeholder value and clearly indicate which translations are still required.
- Reuse existing keys whenever possible instead of creating duplicates.
- Do not use localized text as identifiers, configuration values, API fields, database values, or business logic.

Localization keys should:

- Never contain spaces.
- Follow the project's existing naming convention. If none exists, use `camelCase` or `snake_case`, depending on the language, framework, linters, and project conventions.
- Be descriptive and stable. Prefer names such as `user.profile.saveButton` or `error.invalidCredentials` over generic names like `label1` or `text`.
- Be organized by feature or domain when appropriate.

### Email Templates

Email localization may be implemented using localization keys, separate templates per language, or another project-specific approach. Follow the existing architecture of the project instead of introducing a new one.

When creating or modifying email templates:

- Never hardcode user-facing text.
- Localize the email subject.
- Localize the email body, including headings, paragraphs, button labels, call-to-action text, footer text, and error messages.
- Keep dynamic values (such as user names, order numbers, dates, and links) as template placeholders rather than concatenating localized strings.
- Use locale-aware formatting for dates, times, numbers, currencies, and pluralization where supported by the localization framework.
- Add translations for every language already supported by the application. If translations cannot be provided reliably, add placeholder values and clearly indicate which translations are still required.

Email templates should share a common base layout (header, footer, branding, styling, etc.) to maximize reuse and minimize duplication. Individual templates should contain only email-specific content. Avoid copy-pasting shared HTML or styling between templates.

Avoid embedding user-facing text directly into images. Prefer HTML text whenever possible, as it is easier to localize, more accessible, and adapts better to different screen sizes and email clients. If an image must contain text (for example, a marketing banner or logo), provide localized variants for every supported language or explicitly inform the user that localized assets are required.