---
name: dependencies
description: Load before adding, proposing or reviewing a new dependency — an npm, Gradle or Maven, Composer, Go, PyPI or Homebrew package, a plugin or a tool — and when writing a research prompt that picks one. Carries where to look per ecosystem (the page for a person, the JSON API for an agent) and what to rank by — hard filters, then a ranked list. Not for bumping a version already in use.
trigger-keywords: dependenc*, závislost*, knihovn*, library, libraries
---

# Choosing a dependency

The sources and the criteria are the same whoever does the research: you, a
subagent, or Perplexity from a prompt (`perplexity-research` skill). Perplexity
cannot read this file, so paste the parts that apply into the prompt, the API
column included.

## Where to look

**Read the API, not the page.** Many of these pages render in JavaScript or sit
behind a bot check, and a fetch without a browser gets an empty shell or a 403.
Measured on 2026-10-16 with a plain HTTP client, which is what a web-fetch tool
is: ✅ the page carries its data, ⚠️ it is thin or rendered in JavaScript, ❌ it
is blocked.

Across ecosystems:

| What | Page | For an agent |
|---|---|---|
| Versions, licenses, dependents | https://deps.dev ⚠️ | `https://api.deps.dev/v3/systems/<system>/packages/<name>` |
| Vulnerabilities | https://osv.dev ✅, https://github.com/advisories ✅ | `POST https://api.osv.dev/v1/query` with `{"package":{"name":"<name>","ecosystem":"<ecosystem>"}}`; `https://api.github.com/advisories?ecosystem=<ecosystem>&affects=<name>` |
| Repo hygiene, the OpenSSF Scorecard | https://scorecard.dev ⚠️ | `https://api.securityscorecards.dev/projects/github.com/<owner>/<repo>` |
| Support windows | https://endoflife.date ✅ | `https://endoflife.date/api/v1/products/<product>` |
| The source repo | GitHub ✅ | `gh api repos/<owner>/<repo>`, `/releases`, `/issues?labels=bug` |

Per ecosystem:

| Ecosystem | Page | For an agent | Also |
|---|---|---|---|
| npm | https://www.npmjs.com ❌, https://npmtrends.com ❌ | `https://registry.npmjs.org/<name>/latest`; a year of downloads: `https://api.npmjs.org/downloads/range/last-year/<name>` | size: `https://bundlephobia.com/api/size?package=<name>` (page ⚠️); types and exports: `npx @arethetypeswrong/cli`, `npx publint`, run locally; supply chain: https://socket.dev ❌, a person's check |
| Gradle, Maven | https://central.sonatype.com ⚠️, https://mvnrepository.com ❌ | `https://search.maven.org/solrsearch/select?q=g:<group>+AND+a:<artifact>&wt=json`; `https://repo1.maven.org/maven2/<group/as/path>/<artifact>/maven-metadata.xml` | plugins: https://plugins.gradle.org ✅; on Spring Boot, whether Boot already manages it: https://docs.spring.io/spring-boot/appendix/dependency-versions/coordinates.html ✅ |
| Composer | https://packagist.org ✅ | `https://packagist.org/packages/<vendor>/<name>.json` (downloads, `abandoned`) | `composer audit` |
| Go | https://pkg.go.dev ✅ | `https://proxy.golang.org/<module>/@latest` | — |
| PyPI | https://pypi.org ✅, https://pypistats.org ⚠️ | `https://pypi.org/pypi/<name>/json`; `https://pypistats.org/api/packages/<name>/recent` | — |
| Homebrew | https://formulae.brew.sh ✅ | `https://formulae.brew.sh/api/formula/<name>.json`, install analytics included | — |

## What to rank by

Hard filters first: a candidate that fails one is out, with the reason in one
line.

1. **Needed at all** — compared against the standard library, the platform and
   a dependency we already have.
2. **License** — MIT, Apache-2.0, BSD or ISC pass. Flag copyleft (GPL, AGPL;
   LGPL with its linking terms), source-available (BSL, SSPL, Elastic), an open
   core whose feature we need is paid, and any relicensing in the project's
   history.
3. **Maintained** — a release in the last 6 months, commits from more than one
   person in the last year, not archived, deprecated or marked abandoned, issues
   and pull requests answered.
4. **Compatible** — our runtime and its version (Node, JDK, PHP, Go), the module
   format (ESM or CJS), bundled TypeScript types, our framework's version and
   the versions it manages, and edge or SSR runtimes where we deploy to them.
5. **No unpatched serious advisory.**

Then ranked, in this order:

6. **Bugs** — open bugs against closed, their age, regressions in recent
   releases, how fast fixes ship.
7. **Security posture** — the advisory history and its fix times, the Scorecard,
   signed releases or provenance, install scripts, the transitive dependency
   count.
8. **Adoption, as a trend** — downloads over a year, dependents, known users.
   Stars last: they measure attention, not use.
9. **Release discipline** — semver kept, a changelog, how often a minor version
   breaks something.
10. **Footprint** — bundle size in the browser, transitive dependencies, startup
    cost on the JVM.
11. **Who stands behind it** — a company, a foundation or one person, and its
    funding.
12. **Exit cost** — how much of our code would know about it, and what replacing
    it would take.

The answer names the exact version to pin, with its release date.
