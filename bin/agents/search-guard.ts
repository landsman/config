#!/usr/bin/env bun
// PreToolUse on Bash, Glob and Grep: refuses a search that walks the whole disk or home.
//
// `find / -name banks.csv` once went across the disk for a file that sat in the repo.
// ponytail: a regex over the raw command, not a shell parser. It catches a slip, not a
// determined bypass (`bash -c`, a path in a variable, `cd /` first); add a root when one
// slips through.
import { event, refuse } from "@lib/hook";

interface Input {
	tool_name?: string;
	tool_input?: { command?: string; path?: string };
}

// Where a program runs, so the word inside a commit message or a PR body does not count:
// the start of a line, after `;`, `&`, `|`, `(` or `$(`, or after sudo, xargs, exec, time.
const run = String.raw`(?:^|[;&|(]|\b(?:sudo|xargs|exec|time)\s)\s*`;
const treeWalker = new RegExp(
	String.raw`${run}(?:find|fd|rg|ag|du|tree)\b` +
		String.raw`|${run}grep(?:\s+-\S+)*\s+(?:-\w*[rR]|--recursive\b)` +
		String.raw`|${run}ls(?:\s+-\S+)*\s+-\w*R`,
	"m",
);
const unboundedIndex = new RegExp(String.raw`${run}(?:locate\b|mdfind\b(?!.*-onlyin))`, "m");
// `/`, `~`, `$HOME`, `/Users/<name>` or `/home/<name>`, alone or with /projects or /Library,
// and with `/*` after it, which walks the same tree.
const wholeDiskRoot =
	/(^|\s)"?(\/|~|\$\{?HOME\}?|\/(Users|home)(\/[^/\s"]+)?)"?(\/projects|\/Library)?\/?\*?"?(?=$|[\s;|&)])/;
// A single-quoted word is a pattern, never an expanded path: `rg '/Users/x' src`.
const singleQuoted = /'[^']*'/g;
// A double-quoted string with a space in it is prose, a commit message or a PR body, where
// `(find, fd)` or `this time find /` would otherwise read as a command. `"$HOME"` has none.
// ponytail: `"$(find / -name x)"` gets through with it; a parser would tell the two apart.
const doubleQuotedProse = /"[^"]*\s[^"]*"/g;

const input = await event<Input>();
if (input && sweepsTheDisk(input))
	refuse(
		"This walks the whole disk or home folder. Search inside the project, or name the " +
			"folder you mean (~/projects/<owner>/<repo>, not ~/projects).",
	);

function sweepsTheDisk(input: Input): boolean {
	const path = input.tool_input?.path;
	if (input.tool_name !== "Bash") return path !== undefined && wholeDiskRoot.test(path);
	const command = (input.tool_input?.command ?? "")
		.replace(singleQuoted, "''")
		.replace(doubleQuotedProse, '""');
	return unboundedIndex.test(command) || (treeWalker.test(command) && wholeDiskRoot.test(command));
}
