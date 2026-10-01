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

Today the one source is Homebrew: `brew vulns` (Homebrew 7 and later) over
every installed formula, dependencies included — trivy has no Homebrew support.
Casks are not covered. The fix is nearly always `brew upgrade`; pinning
Homebrew versions is no alternative, since Homebrew keeps only the latest of a
formula and a pin is what leaves the vulnerable one installed.
