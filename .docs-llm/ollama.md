# Local models with ollama

Running a coding agent against a model on this laptop instead of an API.

## The models

[`make ollama`](../Makefile) pulls the list in `OLLAMA_MODELS`, one model per
entry. It is not part of `make apps`: these are tens of gigabytes each and a
fresh machine has better things to do for the first hour. Re-running it is how a
model gets updated — `ollama pull` on a current digest checks the manifest and
stops.

Today the list is `qwen3-coder:30b`, which is what the agents below get pointed
at.

## Running an agent against them

Nothing to configure. ollama ships the integration:

    ollama launch claude
    ollama launch opencode

`ollama launch` on its own opens a menu of every integration it knows — claude,
opencode, codex, cline, copilot and a dozen more — and `--model` picks the model
rather than being asked.

What each one does, so the wiring is not a black box:

- **claude** exports `ANTHROPIC_BASE_URL=http://localhost:11434` and
  `ANTHROPIC_AUTH_TOKEN=ollama`, then runs `claude`. Since v0.14 ollama serves
  the Anthropic Messages API at `/v1/messages` directly, so there is no proxy
  and no translation layer in between — Claude Code is talking to ollama the
  same way it talks to Anthropic.
- **opencode** sets `OPENCODE_CONFIG_CONTENT` with an `ollama` provider
  (`@ai-sdk/openai-compatible` against `http://127.0.0.1:11434/v1`) and the model
  preselected. It is passed in the environment rather than written to
  [`opencode.json`](../shared/.config/opencode/opencode.json), so the tracked
  config is left alone.

Both are per-invocation. Quitting the agent leaves nothing behind, and a normal
`claude` or `opencode` in the next terminal is back on the hosted models.

## What to expect

- **Context.** opencode wants 64k and Claude Code wants 32k. ollama picks a
  serving context from available VRAM (4k / 32k / 256k) rather than from the
  model's maximum, so on a small machine this is the setting that bites first —
  `ollama ps` prints what a loaded model actually got. Force it with
  `OLLAMA_CONTEXT_LENGTH`.
- **Tool calls.** Verified working end to end against `qwen3-coder:30b` through
  both `/api/chat` and `/v1/chat/completions`, streaming and not. If tool calls
  start leaking into the reply as literal `<function=...>` XML, that is the
  model failing to close a `<tool_call>` block, not the transport — fewer tools
  in the session is the lever, which mostly means fewer MCP servers.
- **Quantisation.** `qwen3-coder:30b` is Q4_K_M. Instruction-following and tool
  formatting are the first things a quant costs, before code quality.

## Installed how

Homebrew, as a formula rather than a cask — `ollama` is a CLI plus a server and
runs on both platforms, so it is one unguarded [Brewfile](../Brewfile) line under
this repo's first rule. The `ollama-app` cask is a macOS-only menu bar wrapper
around the same binary; it exists, and it is deliberately not what this repo
installs — one line that is true on every machine beats a guard plus a Linux
half, for a wrapper whose only additions are a menu bar icon and autostart.

Autostart is the one thing the cask does that the formula does not, so the
server is a service to start once per machine:

    brew services start ollama

`make ollama` checks for it and says so rather than failing with a connection
error. Models live in `~/.ollama/models` either way, so switching between the
two installs does not re-download anything.
