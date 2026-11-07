#!/usr/bin/env bun
// PreToolUse on Bash, Glob and Grep: refuses a search that walks the whole disk or home.
//
// `find / -name banks.csv` once went across the disk for a file that sat in the repo.
// ponytail: a regex over the raw command, not a shell parser. It catches a slip, not a
// determined bypass (`bash -c`, a path in a variable, `cd /` first); add a root when one
// slips through.
import { answer, event } from "@lib/hook";

interface Input {
	tool_name?: string;
	tool_input?: { command?: string; path?: string };
}

const treeWalker = /\b(find|fd|rg|ag|du|tree)\b|\bgrep\s+-\w*[rR]|\bls\s+-\w*R/;
const unboundedIndex = /\blocate\b|\bmdfind\b(?!.*-onlyin)/;
// `/`, `~`, `$HOME`, `/Users/<name>` or `/home/<name>`, alone or with /projects or /Library.
const wholeDiskRoot =
	/(^|\s)"?(\/|~|\$\{?HOME\}?|\/(Users|home)(\/[^/\s"]+)?)(\/projects|\/Library)?\/?"?(?=$|[\s;|&)])/;
// A single-quoted word is a pattern, never an expanded path: `rg '/Users/x' src`.
const singleQuoted = /'[^']*'/g;

const input = await event<Input>();
if (input && sweepsTheDisk(input))
	answer({
		hookSpecificOutput: {
			hookEventName: "PreToolUse",
			permissionDecision: "deny",
			permissionDecisionReason:
				"This walks the whole disk or home folder. Search inside the project, or name the " +
				"folder you mean (~/projects/<owner>/<repo>, not ~/projects).",
		},
	});

function sweepsTheDisk(input: Input): boolean {
	const path = input.tool_input?.path;
	if (input.tool_name !== "Bash") return path !== undefined && wholeDiskRoot.test(path);
	const command = (input.tool_input?.command ?? "").replace(singleQuoted, "''");
	return unboundedIndex.test(command) || (treeWalker.test(command) && wholeDiskRoot.test(command));
}
