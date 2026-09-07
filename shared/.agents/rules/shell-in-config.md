# Shell inside a config file

**More than three lines of shell in a YAML or a Makefile earns its own `.sh`
file.** Under three, inline it; at four, move it.

The reason is not length, it is that embedded shell is unreachable by everything
that would otherwise catch a mistake in it:

- **No linter sees it.** shellcheck reads files, not the string value of a `run:`
  key. A quoting bug, an unquoted `$var`, a `||` binding to the wrong side of a
  pipe — all of it ships.
- **No test can call it.** There is no name to invoke. The logic is only reachable
  by triggering whatever the pipeline does, in the environment that triggers it.
- **You cannot run it by hand.** Debugging means a commit, a push, and a wait, in a
  loop, on a shared runner.
- **Two escaping layers stack.** YAML quoting, then the shell's, and on a workflow
  a templating pass before either. `${{ }}` expanded into a `run:` block is the
  injection every CI security pack has a rule for.

The failure this is really about is that CI shell usually runs on the unhappy
path — a failure handler, a retry, a notifier. It is the code that executes when
something is already broken, so a mistake in it surfaces as *silence*, not as an
error. That is exactly the code that should be tested, and inline shell is the one
shape that cannot be.

## What this looks like

    # bad — thirty lines of unreachable shell
    - name: Report the failure
      run: |
        set -euo pipefail
        existing=$(curl -fsSL ... | ...)
        if [ -n "$existing" ]; then
        ...

    # good
    - name: Report the failure
      run: ./cli/nightly-issue.sh report "$API" "$TITLE" "$BODY"

The script lands wherever the repo already keeps them — `cli/`, `bin/`,
`scripts/`. Do not invent a fourth location.

## What stays inline

A single command, or a call to `make`. `run: make test` is not shell worth
extracting, and neither is a one-line `curl`. The threshold is about logic
escaping review, not about banning the `run:` key.

Values still arrive through `env:`, never interpolated into the command line —
that is unchanged, and it matters more once the script is a real file with
arguments.

## Once it is a file, it is a file

It gets the two things it moved out to get, or the move only relocated the
problem:

- **The repo's shell linter runs over it.** Add the script to whatever target
  already lints, or add that target if there is none — a directory nothing checks
  is where the next one lands.
- **The non-trivial part gets one runnable check.** Not every branch: the decision
  that would otherwise fail silently. Expose it as a subcommand so a test can
  reach it without a network, a token or a server.

A script that only shells out to one command needs neither, and the same
proportionality applies as everywhere else.
