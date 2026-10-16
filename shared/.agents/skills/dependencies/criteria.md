# Dependency criteria, one section each

**Not to be read whole.** Open the criterion you are checking:

    awk '/^## C9 /{f=1;print;next} /^## /{f=0} f' ~/.agents/skills/dependencies/criteria.md

Compiled from a research of 2026-10-16 (the brain's *Choosing a dependency*
page), sources read that day. C1–C7 are hard filters; C8–C18 rank.

## C1 Necessity

- **Why:** every dependency is code, transitive packages, update work, license
  terms and one more way in. Adding one is taking on another project's code for
  good ([Russ Cox, *Our Software Dependency Problem*](https://research.swtch.com/deps)).
- **Measure:** the capability in one sentence; compare the standard library, the
  platform, the framework, what the graph already has, a small own
  implementation, and each candidate.
- **Fails when** an accepted dependency or the platform already does it, or the
  package saves trivial code while adding network, native, privileged or
  install-time behaviour. No line-count threshold has evidence behind it.
- **Exceptions:** cryptography, parsers, protocols, compression and file formats
  favour a reviewed library even when the visible API is small.

## C2 Identity

- **Why:** typosquatting, dependency confusion, a taken-over namespace and names
  a model invented ("slopsquatting") put an attacker's package in before any
  quality check runs.
- **Measure:** take the coordinate from the framework's docs or the project's
  repo, then query the registry and compare description, homepage, repository,
  publisher, release history, tag and artifact contents. OpenSSF: "check if a
  similar name is more popular — that could indicate a typosquatting attack"
  ([Concise Guide](https://best.openssf.org/Concise-Guide-for-Evaluating-Open-Source-Software)).
  Flag look-alike characters, one-letter edits, an unexpected scope or group, a
  very new package, a repository that does not point back.
- **Fails when** it is not in the expected registry, registry and source
  disagree, the name came only from a model, or the publisher is not the
  expected one. A new package resembling a known one goes to the human.
- **Exceptions:** relocations, renames and forks — with an announcement from both
  the old and the new place.
- **Seen in:** [polyfill.io](https://blog.cloudflare.com/automatically-replacing-polyfill-io-links-with-cloudflares-mirror-for-a-safer-internet/)
  (2024, a domain sold to a new owner).

## C3 License

- **Why:** direct and transitive terms can clash with distribution, hosting,
  modification, notice, patent or paid-feature terms; registry metadata can be
  missing or wrong.
- **Measure:** the artifact's own `LICENSE` and `NOTICE`, the manifest, the
  source tag, and a license scan of the resolved graph, against how we ship:
  linked, SaaS, container, app.
- **Fails when** a license is unidentified or incompatible, a needed feature is
  paid under terms we refuse, or a transitive conflict is unresolved. MIT, BSD,
  ISC and Apache-2.0 are the defaults, not an automatic legal yes.
- **Exceptions:** LGPL, GPL, AGPL, MPL, BSL, SSPL, Elastic, Commons Clause and
  dual licensing need a look at the actual use; a dev-only tool or a separately
  run program is not a linked library.
- **Seen in:** relicensing — [Elasticsearch](https://www.elastic.co/blog/licensing-change)
  (2021), [Terraform's BSL](https://www.hashicorp.com/blog/hashicorp-adopts-business-source-license)
  (2023), [Redis](https://redis.io/blog/redis-adopts-dual-source-available-licensing/)
  (2024, later [AGPL](https://redis.io/blog/agplv3/)). Check every version you
  pick, not the project's reputation.

## C4 Compatibility

- **Why:** a declared range does not prove it runs in our graph: ESM and CJS,
  peer dependencies, JVM bytecode, architectures, PHP extensions, Python wheels,
  Workers APIs and SSR all break quietly.
- **Measure:** resolve it on a throwaway branch, read the peer and runtime
  constraints and the transitive versions picked, then build and run one real
  path on the exact runtime and target. On Spring Boot, check the
  [managed versions](https://docs.spring.io/spring-boot/appendix/dependency-versions/coordinates.html)
  first; an omitted version resolves to Boot's.
- **Fails when** a peer conflict stays unresolved, a range excludes our runtime,
  an API is missing in the target, or the smoke test fails.
- **Exceptions:** a constraint that lags proven compatibility — overriding it
  needs upstream evidence, a local test and an owner.

## C5 Vulnerabilities and support

- **Why:** known holes and unsupported versions are measurable exposure, though a
  package-level match can overstate it. OWASP widened the category to every
  supply-chain failure
  ([A03:2025](https://top10.owasp.org/2025/A03_2025-Software_Supply_Chain_Failures/)).
- **Measure:** OSV and GitHub Advisories for the exact version, the ecosystem's
  scanner over the resolved graph, the vendor's advisories, CISA KEV, the fixed
  version and the support window.
- **Fails when** a known-exploited hole is unpatched, a reachable critical or high
  one has no mitigation, or the version is out of security support.
- **Exceptions:** wrong coordinates, unreachable code, dev-only use and backported
  fixes — a time-bounded exception, with the evidence written down.

## C6 Execution at install

- **Why:** install hooks and downloaded binaries run at a high-trust moment,
  often holding developer or CI credentials. OpenSSF: "check the installation
  scripts/routines for maliciousness" and for exfiltration from `~/.ssh` and the
  environment ([Concise Guide](https://best.openssf.org/Concise-Guide-for-Evaluating-Open-Source-Software)).
- **Measure:** npm lifecycle scripts; Composer plugins and `allow-plugins`; Gradle
  and Maven plugins and repositories; Python build backends and native wheels;
  Go `cgo` and generators; Homebrew install blocks; action and container
  entrypoints; every download and whether it is checksummed.
- **Fails when** something is obfuscated without reason, a download is unpinned,
  credentials are touched for no stated purpose, or code is fetched and run
  without an immutable checksum. Any install-time code is at least a review.
- **Exceptions:** drivers, codecs, browser engines and binary wrappers — when
  documented, checksummed and isolated.
- **Seen in:** [ua-parser-js](https://github.com/advisories/GHSA-pjwm-rvh2-c87w)
  (2021), [tj-actions/changed-files](https://github.com/advisories/GHSA-mrrh-fwg8-r2c3)
  (2025), [trivy-action tags](https://github.com/advisories/GHSA-69fq-xp46-6x23)
  (2026).

## C7 Privacy and telemetry

- **Why:** a secure, healthy package can still send data where it must not go,
  or break offline use.
- **Measure:** search the source and the shipped files for telemetry endpoints,
  analytics, crash reporters, update checks, reads of environment variables or
  credential paths; watch the network in a smoke test where it handles
  sensitive data.
- **Fails when** telemetry is undisclosed or cannot be switched off, more is
  collected than the function needs, or code, prompts or secrets leave.
- **Exceptions:** opt-in error reporting or update checks, documented and with a
  working switch.
- **Seen in:** [node-ipc](https://snyk.io/blog/peacenotwar-malicious-npm-node-ipc-package-vulnerability/)
  (2022, behaviour by geography).

## C8 Integrity and publishing

- **Why:** a hash catches changed bytes; a signature or attestation ties an
  artifact to a registry or a CI run. Neither says the code is benign — npm:
  provenance "does not guarantee the package has no malicious code"
  ([npm docs](https://docs.npmjs.com/generating-provenance-statements/)); PyPI
  says the same of attestations ([security model](https://docs.pypi.org/attestations/security-model/)).
- **Measure:** digest, registry signature, provenance identity, source commit,
  workflow and builder; compare with earlier releases and look into a lost
  provenance or a new publisher. npm: `npm audit signatures`; trusted publishing
  removes long-lived tokens ([npm](https://docs.npmjs.com/trusted-publishers/)).
- **Fails when** integrity, a signature or an attestation is invalid. Missing
  provenance only ranks down a library, but fails an action, a build plugin, a
  binary tool or a base image when a verified alternative exists.
- **Exceptions:** stable projects older than Sigstore; a checksum published
  somewhere independent is weaker but usable.
- **Seen in:** [debug 4.4.2](https://github.com/advisories/GHSA-4x49-vf9v-38px)
  (2025-09-08, a phished npm account, published 2025-09-15).

## C9 Maintenance

- **Why:** the project has to be able to react — to a runtime change, a report, a
  regression.
- **Measure:** archived, deprecated or abandoned flags; the support policy;
  releases and commits over several years; issues and pull requests answered;
  how long a fix waits for a release; who is active.
- **Threshold:** OpenSSF asks for significant activity *and* a release within the
  previous 12 months
  ([Concise Guide](https://best.openssf.org/Concise-Guide-for-Evaluating-Open-Source-Software)).
  Use it as the trigger for a closer look, not as a filter. Explicit
  abandonment with no maintained fork fails; Packagist says so in `abandoned`,
  with a replacement where there is one ([API](https://packagist.org/apidoc)).
- **Exceptions:** finished small libraries, standards data, bindings to stable
  APIs — healthy with rare releases.

## C10 Governance

- **Why:** one person in control is a continuity risk; many publishers is a
  credential risk. What matters is whether authority is controlled and
  transferable.
- **Measure:** owner, legal entity or foundation, maintainers, who can publish,
  code owners, funding, succession, ownership changes. Contributors are not
  publishers. CHAOSS's [contributor absence factor](https://chaoss.community/kb/metric-contributor-absence-factor/)
  is a scenario, not a cutoff.
- **Review when** one person controls a high-impact package, ownership changed
  recently, the project's domain changed, or a release came from an unexpected
  identity.
- **Exceptions:** a focused single-author library with reproducible releases,
  isolated use and cheap replacement.
- **Seen in:** [event-stream](https://snyk.io/blog/a-post-mortem-of-the-malicious-event-stream-backdoor/)
  (2018, a handover), [XZ Utils](https://www.openwall.com/lists/oss-security/2024/03/29/4)
  (2024, a succession engineered over years).

## C11 Dependency graph

- **Why:** a small API can bring maintainers, licenses, installers, plugins,
  native code and advisories with it.
- **Measure:** resolve production, build, plugin, dev, optional and peer graphs
  apart; count components, duplicates, conflicts, native modules, scripts and
  independent publishers. Gradle shows what was picked and why
  ([dependency reports](https://docs.gradle.org/current/userguide/viewing_debugging_dependencies.html)).
- **Fails when** a transitive fails any hard filter. Otherwise the smallest graph
  wins; no count has evidence behind it.
- **Exceptions:** a coherent framework BOM can beat many loose micro-libraries.

## C12 Defects

- **Why:** issue counts mostly measure size and workflow. Relevant open
  regressions and fix latency predict cost.
- **Measure:** search the issues for our runtime, framework, feature and target;
  sample recent regressions; report-to-triage and fix-to-release times.
- **Fails when** a reproducible blocker sits on the path we need.
- **Exceptions:** large projects with many old issues and a well-kept subsystem;
  small ones that look perfect because nobody reports.

## C13 Release discipline

- **Why:** a semver label is not compatibility; migration notes, deprecation
  windows and immutable versions are.
- **Measure:** tags, changelog, release notes, deprecation policy, yanked or
  withdrawn versions, and how several recent upgrades actually went.
- **Fails when** the bytes under one version changed. Undocumented breaking
  changes and repeated emergency withdrawals rank down.
- **Exceptions:** pre-1.0 projects that say so.
- **Seen in:** [colors and faker](https://snyk.io/blog/open-source-npm-packages-colors-faker/)
  (2022, the maintainer sabotaged a release — caught only by pins, review and
  tests).

## C14 Adoption

- **Why:** real dependents are evidence; downloads include CI, mirrors and
  transitive installs, and stars are bought — millions of suspected fake ones
  ([study](https://arxiv.org/abs/2412.13459)). PyPI calls its own download
  numbers inaccurate ([guide](https://packaging.python.org/en/latest/guides/analyzing-pypi-package-downloads/)).
- **Measure:** download trends over several periods, reverse dependencies,
  downstream distributions, independent users. Homebrew: `install-on-request`,
  not total installs.
- **No minimum.** Low adoption plus sensitive data, CI credentials or build
  authority goes to the human.

## C15 Security posture

- **Why:** practices help prevention and fixing; they do not stop a malicious
  maintainer.
- **Measure:** security policy, disclosure channel, advisory history and fix
  times, branch protection, required review, workflow permissions, pinned
  automation, and the [Scorecard checks](https://github.com/ossf/scorecard/blob/main/docs/checks.md)
  one by one.
- **Fails when** exploitation is known and open, or the release process lets
  someone publish who should not.
- **Never** turn the aggregate Scorecard score into a threshold.

## C16 Footprint

- **Why:** bundle size, cold starts, JVM startup, image layers, native libraries
  and Workers limits can cost more than the feature.
- **Measure:** the same operation with and without it, in the real target:
  compressed bundle delta, Worker size and startup, JVM startup, image delta,
  memory, network calls. Bundlephobia is a lead; the local build decides.
- **Fails when** a platform limit or a budget breaks; otherwise rank by delta.

## C17 Documentation and testability

- **Why:** what cannot be understood, isolated or tested raises defect and exit
  cost.
- **Measure:** reference docs for the current release, examples that run, the
  error model, extension points, test utilities, logging.
- **Fails when** safe use depends on undocumented behaviour nobody can check.

## C18 Exit cost

- **Why:** a dependency behind a boundary we own is cheap to replace.
- **Measure:** call sites, its types in our APIs, stored formats, annotations,
  framework hooks, generated code, migrations.
- **Require** our own boundary for volatile vendors, remote services, telemetry,
  persistence formats and security components.
- **Exceptions:** standard interfaces already are one — JDBC, PSR, `io.Reader`,
  Fetch.
