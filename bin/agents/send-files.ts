#!/usr/bin/env bun
// A file the reply names for me to look at gets sent, not just named, and sent from
// where its card opens. Two events, told apart by `hook_event_name`.
//
// Stop:
// A path in the reply opens nothing in the terminal, and a phone following the
// session has no file behind it at all. When this turn's text names an existing
// screenshot, PDF, page, office file or video that SendUserFile never sent in this
// session, the stop is blocked once with the list, so the model sends them. A path
// to source code is a reference into a repo, not something to look at, and passes.
//
// `stop_hook_active` is set on the stop that follows a block, so a turn that cannot
// send (no SendUserFile in this harness) is held at most once.
//
// PreToolUse on SendUserFile: a file inside `.claude/worktrees/<name>/` is refused.
// Its card shows the path relative to the worktree (`.claude/screenshots/shot.png`),
// the terminal resolves that against the main checkout, where the file does not
// exist, and the link opens nothing. The refusal names the copy into the same path
// in the main checkout; the worktree is swept a day after its work is pushed anyway.
import { realpathSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { answer, event } from "@lib/hook";
import { calls, content, lastTurn } from "@lib/transcript";

// An absolute or ~/ path ending in a format worth looking at, standing on its own:
// not the tail of a longer word or path, not cut short of its extension.
const LOOK =
	/(?<![\p{L}\p{N}_.~/-])((?:\/|~\/)[^\s`'"()<>[\]{}|*]+?\.(?:png|jpe?g|gif|webp|svg|pdf|html?|xlsx|docx|pptx|mp4|mov))(?![\p{L}\p{N}_-])/giu;

const expand = (path: string) => path.replace(/^~\//, `${homedir()}/`);
const isFile = (path: string) =>
	statSync(expand(path), { throwIfNoEntry: false })?.isFile() ?? false;

/** What the assistant wrote since the last prompt. */
const turnText = (transcript: string) =>
	lastTurn(transcript)
		.filter((e) => e.type === "assistant")
		.flatMap(content)
		.filter((b) => b.type === "text")
		.map((b) => b.text ?? "")
		.join("\n");

/** Every file SendUserFile sent in the session, resolved. */
const sent = (transcript: string) =>
	new Set(
		calls(transcript, "SendUserFile")
			.flatMap((input) => (input.files as string[] | undefined) ?? [])
			.filter(isFile)
			.map((f) => realpathSync(expand(f))),
	);

function unsent(transcript: string): string[] {
	const named = [...new Set([...turnText(transcript).matchAll(LOOK)].map((m) => m[1]))].filter(
		isFile,
	);
	if (!named.length) return [];
	const done = sent(transcript);
	return named.filter((path) => !done.has(realpathSync(expand(path))));
}

const WORKTREE = /^(.*?)\/\.claude\/worktrees\/[^/]+\/(.+)$/;

/** The copy out of a worktree for each file that sits in one. */
const copiesOutOfWorktrees = (files: unknown[]) =>
	files
		.filter((f): f is string => typeof f === "string")
		.flatMap((file) => {
			const m = WORKTREE.exec(file);
			return m ? [`cp -p '${file}' '${m[1]}/${m[2]}'`] : [];
		});

const input = await event<{
	hook_event_name?: string;
	tool_input?: { files?: unknown };
	transcript_path?: string;
	stop_hook_active?: boolean;
}>();

if (input?.hook_event_name === "PreToolUse") {
	const files = input.tool_input?.files;
	const copies = copiesOutOfWorktrees(Array.isArray(files) ? files : []);
	if (copies.length)
		answer({
			hookSpecificOutput: {
				hookEventName: "PreToolUse",
				permissionDecision: "deny",
				permissionDecisionReason:
					"A file inside a git worktree shows up as a path relative to the worktree, and the user's terminal " +
					"resolves it against the main checkout, where it does not exist. Copy it there and send that path:\n" +
					copies.join("\n"),
			},
		});
} else if (input?.transcript_path && !input.stop_hook_active && isFile(input.transcript_path)) {
	const missing = unsent(input.transcript_path);
	if (missing.length)
		answer({
			decision: "block",
			reason:
				"The reply names files for the user to look at, but a path opens nothing in their terminal and does not reach " +
				"a phone. Send them with SendUserFile (images with display: render), then finish; if that tool is not " +
				"available here, say so instead:\n" +
				missing.join("\n"),
		});
}
