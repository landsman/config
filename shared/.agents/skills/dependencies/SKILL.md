---
name: dependencies
description: Load before adding, proposing or reviewing a new dependency — an npm, Gradle or Maven, Composer, Go, PyPI or Homebrew package, a plugin, a GitHub or Forgejo action, a container base image or a tool — when checking a dependency's or a lockfile's vulnerabilities, and when writing a research prompt about either. Carries the procedure (identity first, hard filters, then ranking), nineteen criteria with how to measure each, vulnerability triage (which advisory source wins, KEV, EPSS, reachability, VEX exceptions, malicious packages, remediation speed), the sources and commands per ecosystem with the API an agent can read, and what never to trust alone. Not for bumping a version already in use.
trigger-keywords: dependenc*, závislost*, knihovn*, library, libraries, vulnerabilit*, zranitelnost*, cve
---

# Choosing a dependency

A dependency is code inside the product's trust boundary, not a convenience. The
same procedure holds whoever does the research — you, a subagent, or Perplexity
from a prompt (`perplexity-research` skill; it cannot read these files, so paste
what applies).

Three files hold the detail. **None is read whole**; open the one section you are
working on:

    awk '/^## C9 /{f=1;print;next} /^## /{f=0} f' ~/.agents/skills/dependencies/criteria.md
    awk '/^## V4 /{f=1;print;next} /^## /{f=0} f' ~/.agents/skills/dependencies/vulnerabilities.md
    awk '/^## npm/{f=1;print;next} /^## /{f=0} f' ~/.agents/skills/dependencies/sources.md

`vulnerabilities.md`:

- V1 Which source wins
- V2 Remediation speed
- V3 Other track-record metrics
- V4 Prioritising a finding
- V5 Reachability
- V6 Recording an exception
- V7 Malicious packages
- V8 A project's track record
- V9 Auditing a lockfile we have
- V10 Continuous checks and targets

`sources.md`: `Cross-ecosystem`, `npm and Bun`, `Gradle and Maven`, `Composer`,
`Go`, `PyPI`, `Homebrew`, `Actions`, `Container images`.

## Procedure

1. **Requirement and risk class** — the capability in one sentence, and what the dependency will touch: data, CI or build credentials, the browser or the edge, native code.
2. **Names from authoritative sources** — the framework's docs, the project's repo or the registry; never a coordinate that only a model, a blog command or autocomplete produced.
3. **Prove identity (C2)** — registry and repository agree on name, namespace, repository, publisher and release tag.
4. **Fetch without executing** — the exact artifact or manifest, inspected before anything installs or runs its scripts.
5. **Resolve the real graph safely** — dry run, lockfile only or scripts ignored; runtime, build, dev, peer and optional apart.
6. **Hard filters C1–C7**, for the package and its transitives — the first unresolvable failure ends it, reported in one line.
7. **Vulnerabilities (C5)** — the exact version, aliases collapsed, KEV before EPSS before CVSS, reachability named by its state, malicious records (V1, V4, V5, V7).
8. **Rank the survivors on C8–C19**, weighted by privilege: for an action, a build plugin or a base image, integrity, governance and security posture outrank popularity.
9. **Two sources for what decides** (below), then test compatibility and cost in the real target.
10. **Report**: verdict; exact version, its release date and the pinning form; the coordinate and its repository; the hard-filter results; ranked alternatives; commands run; any exception as an expiring VEX (V6); what is unresolved; when to look again.
11. **Ask the human** before a new or look-alike package, an ownership change, install hooks, opaque binaries, remote code, a nonstandard license, telemetry, a mutable action tag or an unattributed image.

Auditing a lockfile we already have, or a project's track record: V9 and V8.

## Criteria

Hard filters, any failure ends it:

- **C1 Necessity** — not already covered by the standard library, the platform or a dependency we have.
- **C2 Identity** — the coordinate is real, intended and controlled by the expected project.
- **C3 License** — the shipped license and every transitive one fit how we distribute and deploy.
- **C4 Compatibility** — shown to run on our runtime, framework, module system and target, not only declared.
- **C5 Vulnerabilities and support** — this version: no malicious record, no exploited or reachable serious hole without mitigation, still supported.
- **C6 Execution at install** — install scripts, plugins, native code and downloaded binaries reviewed and explained.
- **C7 Privacy and telemetry** — no undisclosed or unacceptable collection or network traffic.

Ranking signals:

- **C8 Integrity and publishing** — verifiable digests, signatures or provenance, hardened publishing; hard for actions, build plugins, binaries and images.
- **C9 Maintenance** — able to respond when needed; explicit abandonment is a hard failure.
- **C10 Governance** — who controls it and can publish, ownership changes, succession, funding.
- **C11 Dependency graph** — what it pulls in transitively, at build time and at run time.
- **C12 Defects** — relevant open bugs, regressions and how fast fixes ship.
- **C13 Release discipline** — compatibility policy, changelog, immutable versions.
- **C14 Adoption** — corroboration only; downloads and stars are gamed.
- **C15 Security posture** — disclosure policy, private reporting, branch-aware advisories, workflow and branch controls.
- **C16 Footprint** — measured bundle, startup, memory and image cost in the real target.
- **C17 Documentation and testability** — current docs, a testable API.
- **C18 Exit cost** — kept behind a narrow boundary we own, cheap to replace.
- **C19 Remediation speed** — disclosure to fixed release, per advisory and branch, open ones included.

## Never trust alone

Stars, forks, badges; download counts; a vendor's comparison page; README claims;
an aggregate Scorecard; a package name from a model; a mutable tag, branch or
`@v4`; a provenance badge nobody verified; registry license metadata without the
shipped license file; a clean scan of a graph you did not resolve; a missing EPSS
score, which is unknown, not zero; "not reachable" from a tool that had no
symbols for the advisory; NVD's silence — it stopped enriching every CVE on
2026-04-15; a dismissed alert.

Two independent sources for: identity, a license that is not standard, a serious
vulnerability, a support window (endoflife.date only corroborates the vendor), an
ownership change, provenance, and performance — where a local measurement wins.
