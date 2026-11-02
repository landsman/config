#!/usr/bin/env bun
// Stop hook: a PR, an issue or a CI run named in the reply comes with its full URL.
//
// `#177` or `PR 177` in a terminal is a lookup handed back to me: nothing resolves it
// there. When this turn's text names one by number and no URL in the turn ends in that
// number, the stop is blocked once with the list. A fenced block or inline code is
// left alone — a draft commit message or PR body keeps `#177`, the forge links it there.
//
// `stop_hook_active` is set on the stop that follows a block, so a turn is held at most once.
import { statSync } from "node:fs";
import { answer, event } from "@lib/hook";
import { content, lastTurn } from "@lib/transcript";

// `#177`, `PR 177`, `MR !12`, `run #6201`; not `&#123;`, not a `/#` fragment.
const REF = /(?<![\p{L}\p{N}_&/#])(?:(?:PR|MR|issue|run)\s+[#!]?|#|!)(\d+)\b/giu;
// A forge address ending in that number: GitHub, GitLab, Forgejo, Azure DevOps.
const LINKED = /\/(?:pull|pulls|issues|merge_requests|runs|pullrequest)\/(\d+)\b/g;
const CODE = /```[\s\S]*?(?:```|$)|~~~[\s\S]*?(?:~~~|$)|`[^`\n]*`/g;

/** What the assistant wrote since the last prompt. */
const turnText = (transcript: string) =>
	lastTurn(transcript)
		.filter((e) => e.type === "assistant")
		.flatMap(content)
		.filter((b) => b.type === "text")
		.map((b) => b.text ?? "")
		.join("\n");

export function bare(text: string): string[] {
	const linked = new Set([...text.matchAll(LINKED)].map((m) => m[1]));
	const named = [...text.replace(CODE, "").matchAll(REF)]
		.filter((m) => !linked.has(m[1]))
		.map((m) => m[0]);
	return [...new Set(named)];
}

if (import.meta.main) {
	const input = await event<{ transcript_path?: string; stop_hook_active?: boolean }>();
	const path = input?.transcript_path;
	if (path && !input.stop_hook_active && statSync(path, { throwIfNoEntry: false })?.isFile()) {
		const missing = bare(turnText(path));
		if (missing.length)
			answer({
				decision: "block",
				reason:
					"The reply names a PR, issue or CI run by number without its full URL, and a number in the terminal " +
					"is a lookup handed back to the user (rules/linking-work.md). Add the URL beside each, or drop the " +
					"number. A Forgejo run's URL carries its id, not the #number the API lists:\n" +
					missing.join("\n"),
			});
	}
}
