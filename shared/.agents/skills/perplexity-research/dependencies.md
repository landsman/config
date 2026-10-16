# Choosing a dependency: what goes into the prompt

For a prompt that picks a library, a framework, a plugin or a tool — npm,
Gradle or Maven, Composer, Go, PyPI, Homebrew. Perplexity cannot read this
file: copy the parts that apply into the prompt.

## Where to look

Across ecosystems:

- https://deps.dev — versions, licenses, dependents, advisories and the OpenSSF
  Scorecard (npm, Maven, Go, PyPI, NuGet, Cargo).
- https://osv.dev and https://github.com/advisories — known vulnerabilities, and
  how fast they were fixed.
- https://scorecard.dev — the OpenSSF Scorecard of the source repo: maintenance,
  code review, signed releases, CI.
- https://endoflife.date — the support window of a runtime or framework it ties
  us to.
- The source repo itself: releases, commit history, open and closed issues, the
  changelog.

Per ecosystem:

| Ecosystem | Registry | Usage over time | Specific checks |
|---|---|---|---|
| npm | https://www.npmjs.com | https://npmtrends.com | size: https://bundlephobia.com, https://pkg-size.dev; supply chain: https://socket.dev; types and exports: https://arethetypeswrong.github.io, https://publint.dev |
| Gradle, Maven | https://central.sonatype.com | https://mvnrepository.com ("Used by") | plugins: https://plugins.gradle.org; on Spring Boot, whether Boot already manages a version: https://docs.spring.io/spring-boot/appendix/dependency-versions/coordinates.html |
| Composer | https://packagist.org (installs, dependents, the *abandoned* flag) | the same page | `composer audit` advisories |
| Go | https://pkg.go.dev ("Imported by") | the same page | — |
| PyPI | https://pypi.org | https://pypistats.org | — |
| Homebrew | https://formulae.brew.sh (install analytics) | the same page | — |

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

Ask for the exact version to pin, with its release date.
