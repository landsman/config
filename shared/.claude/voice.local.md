---
voice: azelma
enabled: true
prompt: "Always write the spoken summary in English, even when the rest of the reply is in Czech or any other language."
---

# Voice Feedback Configuration

Read by the `voice@cctools-plugins` plugin, which speaks a summary of each answer.

`prompt:` is the reason this file is tracked. It is injected as a CUSTOM VOICE INSTRUCTION and pins
the spoken line to English no matter which language the written answer is in — including on the
fallback path, where a headless Claude writes the summary and never sees CLAUDE.md.

The `.local` in the name comes from the plugin, not from this repo's "keep it out of git" convention.

`voice:` and `enabled:` are toggles the plugin rewrites in place (`/voice:speak`, `/voice:speak stop`),
so an unexpected diff here is usually just a toggle, and `just_disabled: true` is transient — the stop
hook removes it on the next run. Don't commit that line.
