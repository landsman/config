#!/usr/bin/env bun
// PreToolUse: a PR an agent opens or edits passes the two checks a commit does
// before its title and body leave the machine. The commit-msg hook never sees
// them, and a squash-merge makes them the commit on the main branch.
//
// The title, and the merge commit message where the forge takes one (Azure DevOps
// squashes with it instead of the title), go through bin/git/commit-convention.ts;
// all the text through bin/git/forbidden-names.sh. A refusal carries their own
// message, so the agent fixes the text and calls again.
//
// Bash is read as text, not parsed: a title in a variable or `$(…)` is not
// knowable here and passes; the whole command goes to forbidden-names, so a body
// inline or in a heredoc is checked wherever it sits.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { refusal, titleProblem } from "@bin/git/commit-convention";
import { answer, event } from "@lib/hook";

/** The subjects the call sets and the rest of its text, or undefined when the call
 *  opens or edits no pull request. */
export function pullRequestText(tool: string, toolInput: ToolInput): PullRequestText | undefined {
	if (/^mcp__.*forgejo__(create|update)_pull_request$/.test(tool)) {
		return { subjects: present([toolInput.title]), body: toolInput.body ?? "" };
	}
	if (/^mcp__.*azure-devops__repo_pull_request_write$/.test(tool)) {
		if (toolInput.action !== "create" && toolInput.action !== "update") {
			return undefined;
		}
		const mergeMessage = toolInput.mergeCommitMessage;
		return {
			subjects: present([toolInput.title, mergeMessage?.split("\n")[0]]),
			body: `${toolInput.description ?? ""}\n${mergeMessage ?? ""}`,
		};
	}
	const command = toolInput.command ?? "";
	if (tool !== "Bash" || !PULL_REQUEST_COMMAND.test(command)) {
		return undefined;
	}
	const bodyFile = BODY_FILE.exec(command)?.[1];
	const body =
		bodyFile && existsSync(bodyFile) ? `${command}\n${readFileSync(bodyFile, "utf8")}` : command;
	return {
		subjects: present([
			literalFlag(command, "--title|-t"),
			literalFlag(command, "--merge-commit-message"),
		]),
		body,
	};
}

export type ToolInput = {
	command?: string;
	title?: string;
	body?: string;
	action?: string;
	description?: string;
	mergeCommitMessage?: string;
};

type PullRequestText = { subjects: string[]; body: string };

const PULL_REQUEST_COMMAND =
	/\b(gh\s+pr\s+(create|edit)|glab\s+mr\s+(create|update)|az\s+repos\s+pr\s+(create|update))\b/;

const BODY_FILE = /(?:--body-file|-F)[=\s]+["']?([^\s"']+)/;

const present = (values: (string | undefined)[]) =>
	values.filter((value): value is string => value !== undefined);

/** `--title "…"`, `-t '…'` or `--title=…`, as written; undefined when it is not a
 *  literal, or the flag is not there at all (`--fill`, an edit of the labels). The
 *  first line only: a merge commit message's subject. */
function literalFlag(command: string, flags: string): string | undefined {
	const found = new RegExp(
		`(?:^|\\s)(?:${flags})(?:=|\\s+)(?:"((?:[^"\\\\]|\\\\.)*)"|'([^']*)'|([^\\s"']+))`,
	).exec(command);
	if (!found) {
		return undefined;
	}
	const [, doubleQuoted, singleQuoted, bare] = found;
	if (singleQuoted !== undefined) {
		return singleQuoted.split("\n")[0];
	}
	const value = doubleQuoted ?? bare ?? "";
	return value.includes("$") || value.includes("`")
		? undefined
		: value.replace(/\\(.)/g, "$1").split("\n")[0];
}

function conventionProblems(subjects: string[]): string[] {
	return subjects.flatMap((subject) => {
		const problem = titleProblem(subject);
		return problem ? [refusal(subject, problem)] : [];
	});
}

/** forbidden-names over all of it, the title first, where it looks for an email, run from the session's folder so a
 *  client's own names pass inside the client's own repos. */
async function namesProblem(text: PullRequestText, cwd: string | undefined) {
	const check = Bun.spawn([join(import.meta.dir, "..", "git", "forbidden-names.sh"), "-"], {
		cwd,
		stdin: new Blob([`${text.subjects.join("\n")}\n${text.body}`]),
		stderr: "pipe",
	});
	const said = await new Response(check.stderr).text();
	return (await check.exited) === 0 ? undefined : said.trim();
}

if (import.meta.main) {
	const input = await event<{
		tool_name?: string;
		tool_input?: ToolInput;
		cwd?: string;
	}>();
	const text = pullRequestText(input?.tool_name ?? "", input?.tool_input ?? {});
	if (text) {
		const problems = [
			...conventionProblems(text.subjects),
			await namesProblem(text, input?.cwd),
		].filter(Boolean);
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
