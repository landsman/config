#!/usr/bin/env bun
// PreToolUse hook on SendUserFile: a file inside a git worktree is not sent from there.
//
// Claude Code shows a sent file's path relative to the session's directory at the
// time, which inside `.claude/worktrees/<name>/` is a path like
// `.claude/screenshots/shot.png`. The terminal resolves that link against the
// directory the session started in, the main checkout, where the file does not
// exist, so the card opens nothing. The worktree is swept a day after its work is
// pushed, too. Refused with the copy that fixes it: the same path in the main
// checkout, whose screenshot folder is gitignored just the same.
import { answer, event } from "@lib/hook";

const WORKTREE = /^(.*?)\/\.claude\/worktrees\/[^/]+\/(.+)$/;

const input = await event<{ tool_input?: { files?: unknown } }>();
const files = Array.isArray(input?.tool_input?.files) ? input.tool_input.files : [];
const moves = files
	.filter((f): f is string => typeof f === "string")
	.flatMap((file) => {
		const m = WORKTREE.exec(file);
		return m ? [`cp -p '${file}' '${m[1]}/${m[2]}'`] : [];
	});

if (moves.length)
	answer({
		hookSpecificOutput: {
			hookEventName: "PreToolUse",
			permissionDecision: "deny",
			permissionDecisionReason:
				"A file inside a git worktree shows up as a path relative to the worktree, and the user's terminal " +
				"resolves it against the main checkout, where it does not exist. Copy it there and send that path:\n" +
				moves.join("\n"),
		},
	});
