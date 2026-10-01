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
