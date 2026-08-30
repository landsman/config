# Voice

Answers are spoken aloud by the `voice@cctools-plugins` plugin, documented at
<https://pchalasani.github.io/claude-code-tools/plugins-detail/voice/>.

Its settings live in `voice.local.md` one directory up: which voice reads the
summary, whether it speaks at all, and a `prompt:` that pins the spoken line to
English even when the written answer is in Czech. That last one belongs in the
plugin config rather than here, because the plugin also summarises through a
headless Claude that never sees this file.

Write the reply in whatever language the prompt used; the 📢 line stays English.
