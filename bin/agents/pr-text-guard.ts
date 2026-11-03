#!/usr/bin/env bun
// PreToolUse: a PR an agent opens or edits passes the two checks a commit does
// before its title and body leave the machine. The commit-msg hook never sees
// them, and a squash-merge makes them the commit on the main branch.
//
// The title goes through bin/git/commit-convention.ts, the title and body through
// bin/git/forbidden-names.sh. A refusal carries their own message, so the agent
// fixes the text and calls again.
//
// Bash is read as text, not parsed: a title in a variable or `$(…)` is not
// knowable here and passes; the whole command goes to forbidden-names, so a body
// inline or in a heredoc is checked wherever it sits.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { refusal, titleProblem } from "@bin/git/commit-convention";
import { answer, event } from "@lib/hook";

/** The title (when the call sets one) and the body as the call carries them, or
 *  undefined when the call opens or edits no pull request. */
export function pullRequestText(
	tool: string,
	toolInput: { command?: string; title?: string; body?: string },
): PullRequestText | undefined {
	if (/^mcp__.*forgejo__(create|update)_pull_request$/.test(tool)) {
		return { title: toolInput.title, body: toolInput.body ?? "" };
	}
	const command = toolInput.command ?? "";
	if (tool !== "Bash" || !PULL_REQUEST_COMMAND.test(command)) {
		return undefined;
	}
	const bodyFile = BODY_FILE.exec(command)?.[1];
	const body =
		bodyFile && existsSync(bodyFile) ? `${command}\n${readFileSync(bodyFile, "utf8")}` : command;
	return { title: literalTitle(command), body };
}

type PullRequestText = { title: string | undefined; body: string };

const PULL_REQUEST_COMMAND = /\b(gh\s+pr\s+(create|edit)|glab\s+mr\s+create)\b/;

const BODY_FILE = /(?:--body-file|-F)[=\s]+["']?([^\s"']+)/;

/** `--title "…"`, `-t '…'` or `--title=…`, as written; undefined when it is not a
 *  literal, or there is no title flag at all (`--fill`, an edit of the labels). */
function literalTitle(command: string): string | undefined {
	const found = /(?:^|\s)(?:--title|-t)(?:=|\s+)(?:"((?:[^"\\]|\\.)*)"|'([^']*)'|([^\s"']+))/.exec(
		command,
	);
	if (!found) {
		return undefined;
	}
	const [, doubleQuoted, singleQuoted, bare] = found;
	if (singleQuoted !== undefined) {
		return singleQuoted;
	}
	const title = doubleQuoted ?? bare ?? "";
	return title.includes("$") || title.includes("`") ? undefined : title.replace(/\\(.)/g, "$1");
}

function conventionProblem(title: string | undefined): string | undefined {
	if (title === undefined) {
		return undefined;
	}
	const problem = titleProblem(title);
	return problem ? refusal(title, problem) : undefined;
}

/** forbidden-names over the title and body, run from the session's folder so a
 *  client's own names pass inside the client's own repos. */
async function namesProblem(text: PullRequestText, cwd: string | undefined) {
	const check = Bun.spawn([join(import.meta.dir, "..", "git", "forbidden-names.sh"), "-"], {
		cwd,
		stdin: new Blob([`${text.title ?? ""}\n${text.body}`]),
		stderr: "pipe",
	});
	const said = await new Response(check.stderr).text();
	return (await check.exited) === 0 ? undefined : said.trim();
}

if (import.meta.main) {
	const input = await event<{
		tool_name?: string;
		tool_input?: { command?: string; title?: string; body?: string };
		cwd?: string;
	}>();
	const text = pullRequestText(input?.tool_name ?? "", input?.tool_input ?? {});
	if (text) {
		const problems = [conventionProblem(text.title), await namesProblem(text, input?.cwd)].filter(
			Boolean,
		);
		if (problems.length) {
			answer({
				hookSpecificOutput: {
					hookEventName: "PreToolUse",
					permissionDecision: "deny",
					permissionDecisionReason: `The PR title or body would not pass the commit checks. Fix the text and call again:\n${problems.join("\n\n")}`,
				},
			});
		}
	}
}
