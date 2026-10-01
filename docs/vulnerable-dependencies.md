# Vulnerable dependencies

Two halves, because one finds and the other fixes.

- **`.github/workflows/dependencies.yml`** reads a repo's lockfiles with trivy
  and fails on a fixable HIGH or CRITICAL vulnerability in a production
  dependency. A repo calls it on its pull requests and on a weekly schedule of
  its own — the schedule is what catches an advisory published against a
  lockfile nobody touched. Next to `semgrep.yml`, which reads the code we
  wrote, and `dockerfile.yml`, which reads the base image.
- **Dependabot alerts and security updates** list every known vulnerability,
  dev dependencies and unfixable ones included, and open the pull request that
  fixes one, past the cooldown version updates wait for. They are repository
  settings, not files, so `bin/github/dependabot-security.sh <owner/repo>...`
  sets them; `--all <owner>` does every non-archived source repo, `--dry-run`
  first says what it would do.

## On this machine

The two halves above read a repository. What a laptop actually runs is
checked by `make audit` — `bin/audit/check.sh`, one function per source of
installed software, a source whose tool is missing skipped with a note. It
fails when anything at `SEVERITY` (default `high`) or above turns up, and
**fails closed**: an answer it cannot read — no network, a rate limit, a
changed output format — or a machine where no source could be checked is a
failure, never a pass. The script itself exits 1 for those and 2 for a usage
error; through `make` both are make's own 2.

Today the one source is Homebrew: `brew vulns` (Homebrew 7 and later) — trivy
has no Homebrew support. What it covers and what it does not:

- **Every installed formula brew can trace to a source**, dependencies
  included. The rest — a third of a typical machine, crypto libraries among
  them — it skips, and the audit lists them as not checked rather than
  letting a clean result look complete. Casks are not covered at all.
- **Every severity is asked for, and filtered here.** `brew vulns --severity`
  drops a vulnerability with no score at every level, and the newest CVEs are
  the ones not scored yet; those are always shown, as `UNSCORED`.
- **brew's own word counts.** When it finds nothing but exits non-zero — it
  could not scan an untrusted tap, or tell which version is installed — the
  audit fails as incomplete. Its warnings are shown.
- **Remote text is printed as text.** Control, invisible and
  direction-changing characters in advisory ids, formula names and brew's
  messages become `?`.

Each vulnerable formula says what fixes it, from `brew outdated`:
`→ brew upgrade to <version>` when Homebrew already has a newer one, `pinned`
when a pin holds that back, or `newest in Homebrew, no fix there yet` — then it
waits for Homebrew, or gets patched or replaced outside it. Without an
answer from `brew outdated` the hint is left out; the verdict never depends
on it. The fix is nearly always `brew upgrade`; pinning
Homebrew versions is no alternative, since Homebrew keeps only the latest of a
formula and a pin is what leaves the vulnerable one installed.
