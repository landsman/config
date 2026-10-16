# Vulnerabilities, one section each

**Not to be read whole.** Open the section you need:

    awk '/^## V4 /{f=1;print;next} /^## /{f=0} f' ~/.agents/skills/dependencies/vulnerabilities.md

Compiled from a research of 2026-10-16 (the brain's *Checking a dependency's
vulnerabilities* page), checked against its key sources that day. Commands are in
`sources.md`, per ecosystem.

## V1 Which source wins

No source wins every field; resolve them one at a time.

1. **Identity:** the registry and the artifact itself.
2. **Affected versions:** the project's or the ecosystem's own advisory, with exact
   package coordinates, checked against tags and release history. NVD's CPE
   matching comes after, and never overrides clear package evidence.
3. **Fixed version:** an advisory saying so *and* a published, not yanked
   artifact containing the patch. A `fixed` event naming an unreleased version is
   no fix.
4. **Exploitation:** CISA KEV or a credible primary report beats EPSS, which only
   predicts.
5. **Severity:** keep every source's CVSS vector with its source; work out what
   applies to the deployment rather than picking the highest number.
6. **Duplicates:** collapse by aliases (CVE, GHSA, OSV, ecosystem, vendor IDs),
   keeping each source's ranges and timestamps.
7. **Unreviewed GitHub advisories** are early warnings until corroborated.
8. **Conflicting fixes:** assume the wider affected range and the later fix until
   the source settles it.

**NVD stopped enriching every CVE on 2026-04-15.** It now prioritises KEV entries
(within one business day), federally used software and critical software; the
rest is listed but "lowest priority", and the backlog from before 2026-03-01 is
"Not Scheduled" ([NIST](https://www.nist.gov/news-events/news/2026/04/nist-updates-nvd-operations-address-record-cve-growth)).
So a missing NVD score or CPE is almost no evidence, and tools that match through
NVD CPEs — OWASP Dependency-Check — see less than they did.

## V2 Remediation speed

C19's metric. It describes the project, not the version: a project can have a
good record and a vulnerable latest release, or the reverse.

Timestamps, never substituted for one another:

- **public disclosure** — the earliest public advisory, release note or post that
  identifies the issue;
- **advisory `published`** — the source's own field, which can come after the fix;
  `modified` is only an edit of the record;
- **fixed release** — the registry's publication time of the first non-yanked
  release containing the complete fix, *per supported branch*.

Per advisory and branch: **fixed release − public disclosure.** A fix released
before disclosure is reported as "fixed N hours before disclosure", never as a
negative time or a zero. Use timestamps, not dates: Log4j 2.15.0 reached Maven
Central at 2021-12-09 18:26 UTC and the GHSA was published at 2021-12-10 00:40
UTC — six hours, which a day-precision count turns into "a day".

Aggregate: median, then 75th and 90th percentiles when the sample allows,
maximum, the share still open at 30, 90, 180 and 365 days. **Open advisories
stay in**, with their current age; dropping them makes a slow project look fast.
Separate known-exploited and critical cases, and supported from unsupported
branches.

| Advisories | Report |
|---:|---|
| 0 | "no public track record" — never "a perfect record" |
| 1–4 | each case, no project-wide number |
| 5–9 | median and every open case, low confidence |
| 10–19 | median, 75th percentile, open share |
| 20+ | add the 90th percentile and the splits |

That table is a reporting policy, not a finding. **No universal "a good project
fixes within N days" exists**; compare candidates in the same ecosystem and
function.

## V3 Other track-record metrics

- **Advisory recency** — time since the latest public advisory, and counts over
  12, 24 and 36 months. A recent advisory with a prompt fix shows a working
  process; a long silence may be stability or nobody looking. No threshold.
- **Share with a fixed version** — advisories with a complete, published fix over
  all of them, with three states: fixed, mitigation only, no fix. `last_affected`
  is not a fix; "upgrade to an unsupported major" is said as such.
- **Propagation** — how long until dependents resolve the fix. Read it from
  lockfiles or SBOMs, never from manifest ranges: `^1.2.0` admits 1.2.4 without a
  release, and an unchanged lockfile keeps the old one.

## V4 Prioritising a finding

Record for each: exact version and its role (runtime, transitive, build, dev,
action, image layer), CVSS vector and source, EPSS with its date, KEV with
`dateAdded` and `dueDate`, the reachability state (V5), exposure, privileges and
secrets in reach, fixed version, mitigations.

Order:

1. known exploitation (KEV, or a credible report not yet in KEV);
2. a reachable path from attacker-controlled input;
3. privilege and blast radius — CI credentials, signing keys, production secrets,
   another tenant's data;
4. whether a safe fix or a complete mitigation exists;
5. exploit conditions — network or local, authentication, interaction;
6. EPSS;
7. CVSS;
8. dependency role;
9. how sure the evidence is.

| Condition | Default |
|---|---|
| KEV, present in an exposed or privileged path | emergency; KEV's `dueDate` is an upper bound, not a reason to wait |
| reachable critical or high from unauthenticated input | block the adoption; patch or mitigate first |
| reachable in an action, a build plugin or an install script with secrets | high, whatever the runtime says |
| not reached, by complete symbol-aware analysis | keep the finding, write an expiring VEX (V6), rescan on changes |
| the advisory has no symbols | exposure unknown — never "not reachable" |
| a compatible fixed version exists | upgrade instead of suppressing |
| no fix and the project does not answer | containment or replacement is the fix |

EPSS is the probability of observed exploitation in the next 30 days, with a
percentile ([FIRST](https://www.first.org/epss/)); FIRST sets no cutoff, so any
threshold is our policy and must say so. A missing EPSS is unknown, not zero, and
a low one never overrides KEV. CVSS Base is severity under its own assumptions,
not exploit probability or exposure; v4 separates Base, Threat and Environmental
([FIRST](https://www.first.org/cvss/v4.0/user-guide)).

## V5 Reachability

States, of which only the second and the last lower a finding:

- **reachable** — a call path was found;
- **not reached, complete analysis** — the advisory's symbols were known and
  analysed for this build;
- **unknown, no symbols** — the advisory names no vulnerable function;
- **unknown, unsupported** — the tool cannot analyse this language or artifact;
- **unknown, incomplete** — reflection, dynamic imports, plugins, native code,
  build tags or generated code may escape;
- **not present** — the vulnerable code is not in the shipped artifact.

| Ecosystem | Free reachability | Limits |
|---|---|---|
| Go | `govulncheck`, source and binary mode | needs symbol data; repeat per build tags, `GOOS`, `GOARCH`, CGO |
| JVM | OSV-Scanner call analysis on JARs, version-dependent | reflection, DI, proxies, service loaders; Dependency-Check is matching only |
| JS and TS, PHP, Python | none comparable to `govulncheck` | targeted search for the advisory's functions, tests, manual review |
| Containers | none — Trivy, Grype, OSV-Scanner show presence | a package in an image may be unused |
| Actions | review of `action.yml`, entrypoints, inputs and permissions | the call graph is the wrong question; any entrypoint counts |

Check the installed OSV-Scanner's `--call-analysis` values before relying on it;
support is rolling out per language
([changelog](https://github.com/google/osv-scanner/blob/main/CHANGELOG.md)).

## V6 Recording an exception

When a component stays but is not exploitable here, write VEX, not a dismissed
alert. CISA's `not_affected` justifications: `component_not_present`,
`vulnerable_code_not_present`, `vulnerable_code_not_in_execute_path`,
`vulnerable_code_cannot_be_controlled_by_adversary`,
`inline_mitigations_already_exist`
([CISA](https://www.cisa.gov/resources-tools/resources/vulnerability-exploitability-exchange-vex-status-justification-document-june-2022)).

Store with it: the advisory and its aliases, product and component (purl or
digest), the evidence and the tool version, source revision and lockfile hash,
build target, who reviewed it and when, an expiry, and what invalidates it — a
dependency or code change, an advisory edit, new symbols, new exploitation.

    vexctl create --vuln CVE-… --product 'pkg:oci/…@sha256:…' \
      --subcomponents 'pkg:maven/…@1.2.3' --status not_affected \
      --justification vulnerable_code_not_in_execute_path \
      --impact-statement '… applies to commit abc123, expires 2027-01-16'

Then the scanner's own, as narrow as it allows:

| Tool | Mechanism |
|---|---|
| OSV-Scanner | `[[IgnoredVulns]]` in `osv-scanner.toml`: `id`, `reason`, optional `ignoreUntil` ([docs](https://google.github.io/osv-scanner/configuration/); what happens after the date is not documented — check before relying on it) |
| npm | no expiring ignore; prefer `overrides` to a safe version; `--audit-level` only changes the exit code |
| Bun | `bun audit --ignore <id>`, affecting the exit code only |
| Composer | advisory ignores in `config.audit` with a reason; check the installed version's options |
| pip-audit | `--ignore-vuln <id>`, kept in versioned CI config with the reason |
| Trivy, Grype | `.trivyignore.yaml`, `.grype.yaml`, and their VEX inputs |
| Dependency-Check | suppression XML, matched as narrowly as possible |

## V7 Malicious packages

A separate path: CVSS, fix times and reachability do not fit a credential stealer
that runs at install.

- **Sources:** OSV records with `MAL-` IDs, the
  [OpenSSF malicious-packages](https://github.com/ossf/malicious-packages)
  repository behind them, GitHub advisories of type malware, and the registry's
  own removal or security-holder placeholder. All retrospective — a clean answer
  is no proof.
- **Before installing, read the contents:** new or changed install hooks,
  obfuscated code with no matching source, reads of credentials, SSH keys, cloud
  metadata or CI secrets, unrelated network endpoints, behaviour keyed to
  environment or geography, downloads without a pinned hash, a tiny package with a
  large binary, a sudden change of publisher, repository or domain, an artifact
  that differs from its tag. None is proof alone; each raises the evidence needed.
- **Tools:** [GuardDog](https://github.com/DataDog/guarddog) (`guarddog npm scan`,
  `guarddog pypi scan`), pinned to a reviewed version; heuristic, it misses staged
  payloads.
- **Cooldown:** waiting before a new release buys time for detection but delays
  fixes; no evidence supports any particular length. Renovate:
  `minimumReleaseAge`. Dependabot: `cooldown`, 3 days when unset, for version
  updates only — never security updates
  ([docs](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference)).
  Fast-track KEV and urgent security fixes; package age is not safety.

## V8 A project's track record

1. Scope: repository, coordinates, supported branches, the period.
2. Collect from OSV, reviewed and unreviewed GitHub advisories, vendor records,
   the ecosystem database and NVD.
3. Deduplicate by aliases, keeping each source's timestamps and ranges.
4. Keep malicious releases, dependency-only findings and infrastructure
   compromises apart.
5. Rebuild each timeline: disclosure, acknowledgement, patch commit, fixed
   release, later corrections.
6. Confirm the patch is in the registry artifact, per branch.
7. Keep the open ones, with their age.
8. Compute V2 and V3; split by severity, exploitation and branch.
9. Process evidence (C15).
10. Compare candidates over the same period and sources, and say how sure.

## V9 Auditing a lockfile we have

1. Freeze the evidence: revision, lockfile hash, build target, scanner versions.
2. Inventory the resolved graph or an SBOM, build plugins, actions and image
   layers included.
3. Two complementary scans — the ecosystem's own and OSV-Scanner or Trivy — with
   aliases collapsed.
4. Drop wrong coordinate matches before ranking.
5. Rank by V4; run reachability where V5 has a tool.
6. The least disruptive complete fix: a compatible update, an override, a
   backport, a mitigation, isolation or replacement.
7. Review the update's diff like a new dependency — owners, scripts, provenance,
   license.
8. Test, deploy, and close on a deployed fix or a current VEX, never on a
   dismissed alert.
9. Scheduled rescans, because advisories, KEV and EPSS change without the
   lockfile changing.

## V10 Continuous checks and targets

- **On every pull request:** the lockfile diff, and the ecosystem scanner plus
  OSV-Scanner on what is new. **Scheduled:** a full rescan, daily or weekly.
- **Noise to expect:** npm dev dependencies and duplicate paths; NVD CPE
  mismatches on the JVM; Go findings without symbols; distribution backports in
  images.
- **On Forgejo:** Renovate supports Forgejo as a platform
  ([docs](https://docs.renovatebot.com/modules/platform/forgejo/)); Dependabot
  exists only on GitHub.
- **Published targets** are examples, not evidence of upstream quality: KEV's
  `dueDate` binds US federal agencies
  ([BOD 22-01](https://www.cisa.gov/news-events/directives/bod-22-01-reducing-significant-risk-known-exploited-vulnerabilities));
  PCI DSS asks critical and high patches within a month for in-scope systems. Any
  internal table — say 24–72 h for critical and reachable, 7–14 days for high —
  is our policy and says so.
