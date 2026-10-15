---
paths:
  - "**/*.sh"
---

# Shell scripts

**A script that decides anything gets a test beside it, named `<script>.test.sh`,
and one target runs every test it finds.** A test that has to be listed somewhere
is the one that quietly stops running. The list is edited when a test is written
and forgotten when the next one is.

## The script

- `#!/usr/bin/env bash` and `set -euo pipefail`, or `#!/bin/sh` and `set -eu`
  when it is POSIX. The header says what it does, with one usage line per
  subcommand.
- Each decision is a subcommand (`release.sh checkout <tag>`,
  `release.sh publish <tag> <file>`), so a test reaches it without the rest.
- **Nothing it runs waits for input.** CI has no terminal, so a tool that asks
  a question either repeats it on EOF or waits until the job times out.
  `dylibbundler` filled 1.2 GB of log that way in 21 minutes. Answer it
  (`yes quit | tool`) or pass the flag that turns the prompt off.
- It lives where the repo keeps its scripts; see
  [shell in a config file](shell-in-config.md).

## The test

- **`foo.test.sh`, in the same directory as `foo.sh`.** Not `test-foo.sh`,
  `foo_test.sh` or a `tests/` folder: the pair sorts together, and `*.test.sh`
  matches every test and nothing else.
- Executable, with its own shebang. It finds its script as
  `"$(cd "$(dirname "$0")" && pwd)/foo.sh"`, so it runs from any directory.
- **No network, no token, no state of the machine.** Everything happens in a
  throwaway directory with `trap 'rm -rf "$t"' EXIT`. Each program the script
  calls out to (`gh`, `ssh`, `docker`, `apt`) is replaced by a stub on `PATH`,
  which appends its arguments to a file the test greps. Git is the exception:
  it gets a local bare repository as `origin`, and the real git runs.
- The header says what is worth testing: what the script would get wrong
  *silently*, such as the wrong branch, a half-written file, or an error taken for
  "nothing there".
- One line per check, `ok   <behaviour>` or `FAIL <behaviour>`, where the
  behaviour is a sentence. It keeps going after a failure and exits non-zero at
  the end.
- **Watch it fail once.** Break the decision it guards, see the `FAIL`, put it
  back. A test that has never been red proves nothing.

## Running them

One target, which CI runs on its cheapest runner, and which is run locally
before every push. CI confirms a green run; it is not where a change is tried
for the first time.

```make
scripts-test: ## shellcheck every script, run every *.test.sh
	mise exec shellcheck -- shellcheck $$(git ls-files '*.sh')
	@rc=0; for t in $$(git ls-files '*.test.sh'); do echo "== $$t"; "./$$t" || { echo "FAIL $$t"; rc=1; }; done; exit $$rc
```

- **`git ls-files`, not a glob.** `cli/*.test.sh cli/*/*.test.sh` misses
  anything one level deeper, and a directory nothing runs is where the next test
  lands. It lists tracked files only, so `git add` a new test before running it.
- **`"./$t"`, not `sh "$t"`.** The shebang picks the shell. `sh` runs a bash test
  under dash on Linux, where it fails on the first array.
- **`rc=1`, not `|| exit 1`, and not neither.** A `for` loop exits with the
  status of its last iteration, so with neither, a failing test reports green.
  `rc` also reports every failure in one run, not just the first.
- **The loop names the test that failed.** The error arrives after the last
  test, so without the `FAIL $t` line the log points at whichever test ran last,
  and a test can exit non-zero without printing a `FAIL` of its own.
- **The same shellcheck everywhere**, pinned in `mise.toml` and run as
  `mise exec shellcheck -- shellcheck`, with CI installing that pin rather than
  using the runner's. Versions give one finding different codes: an indirectly
  called function is SC2317 up to 0.10 and SC2329 in 0.11, so a suppression
  written locally failed CI. Rewrite the code so that it needs no suppression,
  and where one cannot be avoided, put it on its line with the reason.
