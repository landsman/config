# Claude Code sandbox

Runs Claude Code in a container with a scenario's settings, rules, skills and
hooks, against a fake API, and prints what reached the model and when. For
questions like: does this rule load, in what order do the hooks run, does a
`settings.json` change do what I meant, did an upgrade change the context.

    make claude-sandbox SCENARIO=bin/claude-sandbox/scenarios/late-rule MODE=both
    make claude-sandbox-test        # the example as a self-check

Needs Docker. The first run builds the image (downloads Claude Code, checked
against SHA-256s pinned in the Dockerfile).

## What is isolated

- No mount from the host's `$HOME`; the scenario is mounted read-only.
- `--network none`: loopback only. The API key is invalid and the endpoint is
  `server.pl` on 127.0.0.1, which stores each request and answers 401.
- Claude Code starts with `env -i`; autoupdate and telemetry are off.
- A scenario path with `:` in it is refused, since `docker -v` cannot mount it.
- The container's uid is the host user's, with no capabilities.

## A scenario

A directory:

| Path | Becomes |
|------|---------|
| `home/` | the container's `$HOME`: `.claude/settings.json`, `rules/`, `skills/`, `CLAUDE.md`, hook scripts |
| `work/` | the project the session starts in (optional) |
| `prompt` | what is typed |
| `expect` | optional, `present <text>` or `absent <text>` per line; a wrong line exits 1 |

Hooks can call `stamp "text"` to put a line in the timeline, and `stamp -j
<label>` in an `InstructionsLoaded` hook to log the file that was loaded.
`expect` text is matched literally in the raw request, which is JSON, so use a
single-line token rather than a sentence with newlines.

Give every scenario at least one `present` line. An `absent` passes just as
well when the request was empty or the wrong one, and only a `present` that
holds shows the request was the real one.

`scenarios/late-rule` is the worked example: a SessionStart hook creates a rule
two seconds in. The rule that already existed is in the request, the one the
hook made is not, because rules load in parallel with the hook, 10 to 80 ms
after it starts. A rule a hook links in reaches the next session.

## Output

A timeline in seconds since launch, the number of requests, one line per
`expect` with the count per request, and the directory with the raw files:
`req-N.json` (the body the model would have got), `timeline.log`, `claude.out`.

`MODE=p` is `claude -p`; `tty` is the interactive UI through `script(1)`, with
the prompt typed after 8 s. `both` runs one after the other (about 20 s more).
Interactive mode types after fixed sleeps (8 s before the prompt, a 40 s cap),
so a slow or cold machine can miss; rerun before trusting a failure. The two
send different requests (the interactive one is larger).

## Bumping Claude Code

Change `CLAUDE_VERSION` and the two `CLAUDE_SHA256_*` values in the
[Dockerfile](Dockerfile); its comment says where the checksums come from. The image is
tagged with it, and `make claude-sandbox-test` shows whether the example still
holds. To compare two versions, run the same scenario before and after and
diff the `req-1.json` files.

A weekly workflow, `claude-sandbox-version.yml`, opens (or updates) one issue
when a newer Claude Code major is out; minor and patch bumps are not announced.
It is a stopgap: the plan is a Renovate custom regex manager on the `ARG`s,
which would replace the script, its test and the workflow.

## What it cannot show

- Anything after the first response. The 401 ends the turn, so there are no
  tool calls, no permission prompts and no Stop hooks with a real turn behind
  them.
- macOS-only behaviour: the keychain, BSD tools, `/Users` paths. This is Debian.
- That an account, a model or a plan changes anything: there is no login.
- Settings from outside the scenario, such as managed settings or the real
  machine's `settings.local.json`.
