---
paths:
  - "**/Makefile"
  - "**/makefile"
  - "**/GNUmakefile"
  - "**/*.mk"
---

# Makefiles

Plain `make` must answer "what can I do here?", so every Makefile gets a `help`
target, and `help` is the **first target in the file** — Make's default goal is
the first target, which is what makes the bare `make` print it. Set
`.DEFAULT_GOAL := help` as well, not instead: it is what keeps the bare `make`
answering the day someone adds a target above `help` without noticing that
position was load-bearing.

`help` parses the Makefile rather than repeating it, so a target is described
where it is defined and the list cannot drift from the targets. Two markers:
`## text` at the end of a target line documents that target, `##@ Group` opens a
section. The colon after a heading is printed, not written — nine source lines
cannot each remember it.

    .PHONY: help
    help: ## show this help
    	@# Colour only when stdout is a tty: piped into less, or read back out
    	@# of a CI log, the escape codes print as text.
    	@test -t 1 && tty=1 || tty=0; \
    	awk -v tty="$$tty" 'BEGIN { FS = ":.*##"; \
    			if (tty) { hdr = "\033[1m"; tgt = "\033[36m"; off = "\033[0m" } \
    			print "usage: make <target>\n" } \
    		/^##@/ { printf "\n%s%s:%s\n", hdr, substr($$0, 5), off; next } \
    		/^[a-zA-Z0-9_.-]+:.*##/ { printf "  %s%-22s%s %s\n", tgt, $$1, off, $$2 }' $(MAKEFILE_LIST)

    ##@ Quality assurance
    lint: ## parse every shell file without running it

The parser is deliberately naive — it assumes `##@ ` with the space, one `##`
per line, and a target name inside 22 columns. Widen it when a line in the file
actually breaks it, not in advance.

Group targets by what they are *for*, not by what they call — checks, packages,
dotfiles, deploy — and keep the file in that order, because the section a target
sits under is the section it prints under. Spell the group name out: the heading
is read by someone who does not yet know what `QA` stands for here, which is the
whole reason they ran `make`.

Prefix a target with its group when the bare name would collide or read
ambiguously across groups. Four checks here each want the name `test`, so they
become `apps-test`, `stow-test`, `git-config-test` and `claude-settings-test`.
Prefix for that reason only: `stow`, `restow` and `unstow` are unambiguous as
they are.

A target with no `##` is deliberately unlisted — a prerequisite of another
target is not something to reach for by hand. Every target that is not a file is
`.PHONY`.
