#!/usr/bin/env bun
// Refuses a commit that names a client or an employer outside their own repos —
// the check where-repos-live.md asks for before anything leaves the machine.
//
//   forbidden-names.ts          the staged diff (pre-commit)
//   forbidden-names.ts <file>   a commit message file (commit-msg), or any text
//   forbidden-names.ts -        stdin, e.g. a PR body before it is posted
//   forbidden-names.ts --verify both engines over a sample, for the port itself
//
// Wired as a config-based hook in .gitconfig (git 2.54+) through the `.sh` beside
// this file, not through core.hooksPath: that would replace every repo's own
// hooks, and a husky or a pre-commit framework setting its own path would switch
// this one off.
//
// The names are not in this repo, which is public — listing them here would be
// the leak. They live in the file `git config forbiddenNames.file` points at,
// one `<owner> <extended regex>` per line, # comments allowed. <owner> is the
// directory under ~/projects the name belongs to: inside that owner's repos its
// own names are fine, everywhere else they are not. A name shared by several
// folders (a client whose product lives under another one) lists them all,
// comma-separated: `acme,acme-holding acme`. One word on its own is both: the
// owner and its own pattern.
//
// The patterns are written for grep, and this reads them with JS. The two
// dialects agree on most of it and differ silently where it matters, so
// toRegExp() translates what differs and *throws* on anything it does not know
// rather than guess: a pattern that quietly stops matching is the leak this
// whole file exists to prevent. `--verify` is the other half of that promise —
// it runs grep and JS over the same sample and reports any line they disagree on.
import { $ } from "bun";
import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

/** An address anywhere in a subject line. Local part and domain as grep's
 *  [[:alnum:]._%+-] and [[:alnum:]-], spelled out for JS. */
export const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/;

/** POSIX bracket classes, which JS does not have: inside `[...]` JS reads
 *  `[[:alnum:]]` as the characters `[:alnum]`, matching an `a` and a `:` and
 *  never saying so. */
const POSIX_CLASSES: Record<string, string> = {
	alnum: "A-Za-z0-9",
	alpha: "A-Za-z",
	blank: " \\t",
	cntrl: "\\x00-\\x1f\\x7f",
	digit: "0-9",
	graph: "\\x21-\\x7e",
	lower: "a-z",
	print: "\\x20-\\x7e",
	punct: "!-\\/:-@\\[-`{-~",
	space: " \\t\\n\\v\\f\\r",
	upper: "A-Z",
	word: "A-Za-z0-9_",
	xdigit: "0-9A-Fa-f",
};

/** A grep ERE as a JS RegExp. `\<` and `\>` become `\b`, POSIX classes are
 *  expanded, and a construct with no JS equivalent throws. */
export function toRegExp(ere: string, flags = ""): RegExp {
	let out = "";
	for (let i = 0; i < ere.length; ) {
		const c = ere[i];
		if (c === "\\") {
			const next = ere[i + 1];
			if (next === undefined) throw new Error(`trailing backslash in /${ere}/`);
			// grep's word edges; JS spells both as \b.
			out += next === "<" || next === ">" ? "\\b" : `\\${next}`;
			i += 2;
			continue;
		}
		if (c === "[") {
			const [expanded, next] = bracket(ere, i);
			out += expanded;
			i = next;
			continue;
		}
		out += c;
		i++;
	}
	return new RegExp(out, flags);
}

/** One bracket expression from `ere[at]`, with its POSIX classes expanded, and
 *  where it ends. A `]` straight after `[` or `[^` is a literal, as in grep. */
function bracket(ere: string, at: number): [string, number] {
	let i = at + 1;
	let out = "[";
	if (ere[i] === "^") {
		out += "^";
		i++;
	}
	if (ere[i] === "]") {
		out += "\\]";
		i++;
	}
	for (; i < ere.length; i++) {
		if (ere[i] === "]") return [`${out}]`, i + 1];
		if (ere[i] === "[" && (ere[i + 1] === "." || ere[i + 1] === "=")) {
			// Collating symbols and equivalence classes: no JS equivalent at all.
			throw new Error(`[${ere[i + 1]} …${ere[i + 1]}] has no JS equivalent in /${ere}/`);
		}
		if (ere[i] === "[" && ere[i + 1] === ":") {
			const end = ere.indexOf(":]", i + 2);
			if (end === -1) throw new Error(`unterminated [: … :] in /${ere}/`);
			const name = ere.slice(i + 2, end);
			const chars = POSIX_CLASSES[name];
			if (!chars) throw new Error(`unknown character class [:${name}:] in /${ere}/`);
			out += chars;
			i = end + 1;
			continue;
		}
		out += ere[i] === "\\" ? `\\${ere[++i] ?? ""}` : ere[i];
	}
	throw new Error(`unterminated [ in /${ere}/`);
}

export type Pattern = { line: number; source: string; re: RegExp };

/** Whether the line names it — a *word*, not a run of letters inside another
 *  one: `cat` is not to be found in `concatenate`.
 *
 *  grep's own word edges cannot do this job. A word there is `[A-Za-z0-9_]`, so
 *  `client_acme_token` and `AcmeService` would stop matching, and those are
 *  exactly the shapes a name leaks in. The edges are therefore judged per match:
 *
 *    a letter before            inside a word: `concatenate` is not `cat`
 *    a lower-case letter after  the word goes on: `acmecorp` is not `acme`
 *    upper case after a match
 *      that is all upper case   a longer abbreviation: `ABC` is not `AB`
 *
 *  Anything else is an edge: a space, a digit (`acme2.cz`), `_`, `-`, `.`, `/`,
 *  or the capital that starts the next camelCase word — `AcmeService` is the
 *  name, and in code that is the common shape. The cost of the last rule is that
 *  `ACMECORP` reads as one abbreviation and passes; a name worth hiding in
 *  capitals is worth its own pattern.
 *
 *  Judging each match in code is why this is TypeScript: ERE has no lookaround,
 *  so the shell version could only ever offer its own `[A-Za-z0-9_]` edges. */
export function names(line: string, pattern: Pattern): boolean {
	const re = new RegExp(pattern.re.source, `${pattern.re.flags}g`);
	for (const match of line.matchAll(re)) {
		const hit = match[0];
		const before = line[match.index - 1] ?? "";
		const after = line[match.index + hit.length] ?? "";
		if (/[A-Za-z]/.test(before)) continue;
		if (/[a-z]/.test(after)) continue;
		if (/[A-Z]/.test(after) && /[A-Z]/.test(hit) && hit === hit.toUpperCase()) continue;
		return true;
	}
	return false;
}

/** The patterns this repo's owner is not allowed to write, by line in the list.
 *  A trailing space would otherwise leave an empty pattern, and an empty pattern
 *  matches every line — so each line is trimmed at the end, CR included.
 *
 *  A pattern in lower case matches either case: a name is the name however it is
 *  typed. One carrying an upper-case letter is matched case-sensitively, and that
 *  is the only way a two-letter abbreviation can be listed at all — in lower
 *  case it collides with half of the shell (`mv`, `cp`, `ln`, `rm`) and refused
 *  every commit that moved a file. Word boundaries stay the pattern's own
 *  business, and names() above judges every match's edges anyway. Word edges
 *  do not help a two-letter command: `mv` is a whole word in `mv "$t"`, which
 *  is why upper case is still how such a name is listed. */
export function patternsFor(list: string, owner: string): Pattern[] {
	const out: Pattern[] = [];
	list.split("\n").forEach((raw, index) => {
		const line = raw.replace(/\s+$/, "");
		if (/^\s*(#|$)/.test(line)) return;
		const owners = line.split(/\s+/)[0] ?? "";
		if (owner && owners.split(",").includes(owner)) return;
		const source = /\s/.test(line) ? line.replace(/^\S+\s+/, "") : line;
		out.push({ line: index + 1, source, re: toRegExp(source, /[A-Z]/.test(source) ? "" : "i") });
	});
	return out;
}

/** Added lines of a staged diff as `file:line: text`, so a hit points at the
 *  place to edit. `+++ ` is a header only before a file's first hunk: inside one
 *  it is an added line starting `++ `. */
export function addedLines(diff: string): string[] {
	const out: string[] = [];
	let header = false;
	let file = "";
	let n = 0;
	for (const line of diff.split("\n")) {
		if (line.startsWith("diff --git ")) header = true;
		else if (header && line.startsWith("+++ ")) file = line.slice(4).replace(/^b\//, "");
		else if (line.startsWith("@@")) {
			header = false;
			n = Number.parseInt(line.split(" ")[2]?.slice(1).split(",")[0] ?? "0", 10);
		} else if (!header && line.startsWith("+")) out.push(`${file}:${n++}: ${line.slice(1)}`);
	}
	return out;
}

/** A commit message as numbered lines. git's template comments are not the
 *  message, and neither is the diff `commit -v` appends below the scissors. */
export function messageLines(raw: string): string[] {
	const body = raw.split(/^# -{24} >8 -{24}$/m)[0] ?? "";
	return body
		.split("\n")
		.map((line, i) => ({ line, n: i + 1 }))
		.filter(({ line }) => !line.startsWith("#"))
		.map(({ line, n }) => `${n}:${line}`);
}

/** A PR body as numbered lines. Here a leading # is a Markdown heading, not a
 *  comment, so nothing is dropped. */
export function stdinLines(raw: string): string[] {
	return raw.split("\n").map((line, i) => `${i + 1}:${line}`);
}

/** The first line that is neither blank nor a comment — what a squash-merge
 *  copies onto the main branch, and what every notification shows. */
export function subjectOf(raw: string): string {
	return raw.split("\n").find((l) => !l.startsWith("#") && l.trim() !== "") ?? "";
}

/** Where the hit was, for the message: the same three words the shell version
 *  used, because the wording is what a refused commit is read by. */
type Source = { where: string; lines: string[] };

const die = (...lines: string[]): never => {
	for (const line of lines) console.error(`forbidden-names: ${line}`);
	process.exit(1);
};

async function git(...args: string[]): Promise<string> {
	return (await $`git ${args}`.nothrow().quiet()).stdout.toString();
}

/** The main checkout, also from a linked worktree, which may sit outside
 *  ~/projects — hence the common dir rather than the cwd. */
async function mainCheckout(): Promise<string> {
	const dir = (await git("rev-parse", "--path-format=absolute", "--git-common-dir")).trim();
	return realpathSync(dirname(dir));
}

async function collect(args: string[], stdin: string): Promise<Source> {
	if (args.length === 0) {
		// The prefixes are pinned against a diff.noprefix in anyone's config.
		const diff = await git(
			"diff", "--cached", "-U0", "--no-color", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/",
		);
		// The names too: an empty or binary file has no added line to carry its path.
		const names = (await git("diff", "--cached", "--name-only", "--diff-filter=d"))
			.split("\n")
			.filter(Boolean)
			.map((name) => `${name}: (file name)`);
		return { where: "staged", lines: [...addedLines(diff), ...names] };
	}
	if (args[0] === "-") return { where: "stdin", lines: stdinLines(stdin) };
	const file = Bun.file(args[0] as string);
	return { where: "the commit message", lines: messageLines(await file.text()) };
}

/** grep's answer for one pattern, to hold the JS one against. */
async function grepHits(pattern: Pattern, sample: string): Promise<Set<string>> {
	const flags = /[A-Z]/.test(pattern.source) ? "-E" : "-iE";
	const proc = Bun.spawn(["grep", flags, "-e", pattern.source], { stdin: new Blob([sample]), stdout: "pipe", stderr: "pipe" });
	const out = await new Response(proc.stdout).text();
	await proc.exited;
	return new Set(out.split("\n").filter(Boolean));
}

/** Both engines over the same sample, per pattern, reported by line in the list
 *  and never by its text: this prints in a terminal that may be shared. Any
 *  disagreement is a failed port, so it exits 1. */
async function verify(patterns: Pattern[], sample: string): Promise<never> {
	let bad = 0;
	for (const pattern of patterns) {
		const theirs = await grepHits(pattern, sample);
		const ours = new Set(sample.split("\n").filter((line) => names(line, pattern)));
		const onlyGrep = [...theirs].filter((l) => !ours.has(l));
		const onlyJs = [...ours].filter((l) => !theirs.has(l));
		const narrowed = onlyGrep.filter((l) => pattern.re.test(l));
		const lost = onlyGrep.filter((l) => !pattern.re.test(l));
		const mark = lost.length + onlyJs.length === 0 ? "ok  " : "FAIL";
		console.log(
			`${mark} list line ${pattern.line}: ${theirs.size} grep, ${ours.size} js, ` +
				`${narrowed.length} narrowed (inside a word), ${lost.length + onlyJs.length} unexplained`,
		);
		for (const line of [...lost, ...onlyJs].slice(0, 3)) console.log(`       unexplained: ${line.slice(0, 120)}`);
		if (mark === "FAIL") bad++;
	}
	console.log(
		bad === 0
			? `all ${patterns.length} patterns translate as grep reads them`
			: `${bad} of ${patterns.length} patterns differ for a reason the word rule does not explain`,
	);
	process.exit(bad === 0 ? 0 : 1);
}

if (import.meta.main) {
	const argv = process.argv.slice(2);
	const verifying = argv[0] === "--verify";
	const args = verifying ? argv.slice(1) : argv;
	const stdin = args[0] === "-" || verifying ? await Bun.stdin.text() : "";

	// An email address in the subject line, the one line a squash-merge copies
	// from the PR title, refused regardless of the names list. It also ends up in
	// `git log --oneline`, every changelog and every notification. The body may
	// carry one.
	if (!verifying && args.length > 0) {
		const raw = args[0] === "-" ? stdin : await Bun.file(args[0] as string).text();
		const subject = args[0] === "-" ? (raw.split("\n")[0] ?? "") : subjectOf(raw);
		if (EMAIL_RE.test(subject)) {
			die(
				`an email address in the subject or PR title: ${subject}`,
				"say whose address it is (the work address), not the address.",
			);
		}
	}

	const configured = (await git("config", "--get", "forbiddenNames.file")).trim();
	// Unset means a machine this repo never set up (a CI runner): nothing to check.
	if (!configured) process.exit(0);
	const listPath = configured.startsWith("~") ? join(homedir(), configured.slice(1)) : configured;
	const list = Bun.file(listPath);
	if (!(await list.exists())) {
		die(
			`${listPath} is missing, refusing to commit unchecked.`,
			"clone the brain, or skip this repo: git config hook.forbidden-names.enabled false",
		);
	}
	const text = await list.text();
	if (!text.split("\n").some((line) => !/^\s*(#|$)/.test(line))) {
		die(`${listPath} holds no patterns, refusing to commit unchecked.`);
	}

	const repo = await mainCheckout();
	// The repo that holds the list is private by definition.
	if (listPath.startsWith(`${repo}/`)) process.exit(0);
	const home = homedir();
	const owner = repo.startsWith(`${home}/projects/`)
		? (repo.slice(`${home}/projects/`.length).split("/")[0] ?? "")
		: "";

	const patterns = patternsFor(text, owner);
	// Every name belongs to this repo's owner: nothing is forbidden here.
	if (patterns.length === 0) process.exit(0);

	if (verifying) {
		const sample = stdin.trim() ? stdin : await git("log", "-p", "--no-color", "-n", "200");
		await verify(patterns, sample);
	}

	const { where, lines } = await collect(args, stdin);
	const hits = lines.filter((line) => patterns.some((p) => names(line, p)));
	if (hits.length === 0) process.exit(0);
	console.error(`forbidden-names: a name that belongs to another owner, in ${where}:`);
	for (const hit of [...new Set(hits)]) console.error(`  ${hit}`);
	die("use a placeholder (<org>, <host>) — see where-repos-live.md.");
}
