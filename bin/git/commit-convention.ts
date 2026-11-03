#!/usr/bin/env bun
// Refuses a commit subject or a PR title that breaks the commit-messages rule.
// One check for both, because a squash-merge makes the PR title the subject.
//
//   commit-convention.ts <file>           a commit message file (commit-msg)
//   commit-convention.ts --title <text>   a PR title, before it is posted
//
// Wired as a commit-msg hook in .gitconfig through the `.sh` beside this file,
// called by openPullRequest and by the agents' PreToolUse hook
// bin/agents/pr-text-guard.ts. The types are the rule's table; change both.
import { subjectOf } from "@bin/git/forbidden-names";

/** What is wrong with a commit subject, or undefined when it follows the rule. */
export function subjectProblem(subject: string): string | undefined {
	if (subject === "" || GENERATED.test(subject)) {
		return undefined;
	}
	const parts = PREFIX.exec(subject);
	if (!parts) {
		return "no `<type>: ` or `<type>(<scope>): ` prefix, with a lowercase type and scope";
	}
	const [, type, , text] = parts;
	if (!(TYPES as readonly string[]).includes(type ?? "")) {
		return `\`${type}\` is not one of the types`;
	}
	if (!/^[a-z]/.test(text ?? "")) {
		return "the subject after the colon starts with a lowercase letter; reword so an identifier is not first";
	}
	if (subject.endsWith(".")) {
		return "the subject ends with a full stop";
	}
	const length = [...subject].length;
	if (length > MAX_LENGTH) {
		return `the subject is ${length} characters, over the ${MAX_LENGTH} cap`;
	}
	return undefined;
}

export const TYPES = [
	"security",
	"deps",
	"ci",
	"devops",
	"setup",
	"fe",
	"be",
	"docs",
	"chore",
] as const;

const MAX_LENGTH = 100;

/** `<type>(<scope>)!: ` — the shape only; the type is checked against TYPES after. */
const PREFIX = /^([a-z]+)(\([a-z0-9./-]+\))?!?: (.*)$/;

/** Git's own subjects and a fixup are not ours to reformat: a merge's is generated,
 *  a revert's quotes the original, a fixup is folded away before it lands. */
const GENERATED = /^(Merge |Revert |fixup!|squash!)/;

/** The same for a PR title. Forgejo's draft marker `WIP: ` is dropped first: the forge
 *  will not merge a draft, and taking the marker off re-checks the title it leaves. */
export function titleProblem(title: string): string | undefined {
	const subject = title.replace(/^\s*WIP:\s*/, "").trim();
	// Empty is an aborted commit, but never a PR worth opening.
	return subject === "" ? "the title is empty" : subjectProblem(subject);
}

/** The refusal, the same for a commit, a PR and an agent: what was given, what is
 *  wrong, and what is expected, so it can be fixed without opening the rule. */
export function refusal(subject: string, problem: string): string {
	return [
		`commit-convention: ${problem}`,
		`  got:      ${subject}`,
		"  expected: <type>(<scope>)!: <subject>, at most 100 characters, no full stop",
		`  types:    ${TYPES.join(" ")}`,
		"  e.g.      setup(agents): refuse a PR title that breaks the commit convention",
	].join("\n");
}

if (import.meta.main) {
	const args = process.argv.slice(2);
	const isTitle = args[0] === "--title";
	const subject = isTitle ? (args[1] ?? "") : subjectOf(await Bun.file(args[0] ?? "").text());
	const problem = isTitle ? titleProblem(subject) : subjectProblem(subject);
	if (problem) {
		console.error(refusal(subject, problem));
		process.exit(1);
	}
}
