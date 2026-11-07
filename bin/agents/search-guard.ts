#!/usr/bin/env bun
// PreToolUse on Bash, Glob and Grep: a search stays inside the project folder.
//
// `find / -name banks.csv` once went across the whole disk for a file that sat in the
// repo: slow, and a sweep of ~/projects prints every client folder into the transcript
// (rules/where-repos-live.md). So a command that walks a tree — find, fd, rg, ag, du,
// tree, grep -r, ls -R, locate, mdfind — and the Glob and Grep tools may start only in
// the project (CLAUDE_PROJECT_DIR), a temp dir (the scratchpad), or the brain, which
// rules/brain.md says to grep before researching.
//
// ponytail: a hand-rolled tokeniser (quotes, `;`, `&&`, `|`, `$(`, `cd`), so a path
// held in a variable is read as relative and let through; add a case when one slips.
import { existsSync, realpathSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join, resolve, sep } from "node:path";
import { answer, event } from "@lib/hook";

const home = homedir();

interface Input {
	cwd?: string;
	tool_name?: string;
	tool_input?: { command?: string; path?: string };
}

/** Refuses the call when a search in it starts outside the allowed folders. */
function decide(input: Input) {
	const cwd = input.cwd ?? process.cwd();
	const project = process.env.CLAUDE_PROJECT_DIR || cwd;
	const allowed = [
		project,
		tmpdir(),
		"/tmp",
		"/var/folders",
		join(home, "projects/landsman/brain"),
	].map(real);
	const tool = input.tool_input ?? {};
	const dirs =
		input.tool_name === "Bash"
			? searchedDirs(tool.command ?? "", cwd)
			: [absolute(tool.path || ".", cwd)];
	const outside = [...new Set(dirs)].filter(
		(d) => !allowed.some((a) => d === a || d.startsWith(a + sep)),
	);
	if (outside.length)
		answer({
			hookSpecificOutput: {
				hookEventName: "PreToolUse",
				permissionDecision: "deny",
				permissionDecisionReason:
					`This searches ${outside.join(", ")}, outside the project ${real(project)}. A search stays in the ` +
					"project, the scratchpad or the brain. Search inside the project, or read a path you already know " +
					"directly. If the user asked for a search elsewhere, ask them to run it as `! <command>`.",
			},
		});
}

/** Every directory the command's searches start in, resolved against the cwd it reaches them with. */
function searchedDirs(command: string, cwd: string): string[] {
	let dir = cwd;
	const dirs: string[] = [];
	for (let words of segments(command)) {
		words = words.filter((w) => !/[<>]/.test(w)); // redirections
		while (words.length && (/^\w+=/.test(words[0]) || WRAPPERS.has(words[0])))
			words = words.slice(1);
		const [cmd = "", ...args] = words;
		const name = basename(cmd);
		if (name === "cd") {
			if (args[0] !== "-") dir = absolute(args[0] ?? "~", dir);
			continue;
		}
		const starts = walkRoots(name, args);
		if (starts) dirs.push(...(starts.length ? starts : ["."]).map((p) => absolute(p, dir)));
	}
	return dirs;
}

const WRAPPERS = new Set(["sudo", "command", "nice", "time", "nohup", "exec", "env"]);

/** Words per simple command, split on `;`, `|`, `&`, newlines, parentheses, backticks and `$(`. */
function segments(command: string): string[][] {
	const out: string[][] = [[]];
	let word: string | undefined;
	let quote = "";
	const end = () => {
		if (word !== undefined) out[out.length - 1].push(word);
		word = undefined;
	};
	for (let i = 0; i < command.length; i++) {
		const c = command[i];
		if (quote) {
			if (c === quote) quote = "";
			else word += c;
		} else if (c === "'" || c === '"') {
			quote = c;
			word ??= "";
		} else if (c === "\\" && i + 1 < command.length) {
			word = (word ?? "") + command[++i];
		} else if (c === " " || c === "\t") {
			end();
		} else if (";|&\n()`".includes(c) || (c === "$" && command[i + 1] === "(")) {
			end();
			out.push([]);
		} else {
			word = (word ?? "") + c;
		}
	}
	end();
	return out.filter((s) => s.length);
}

/** Where a tree-walking command starts: [] for its cwd, undefined for a command that walks nothing. */
function walkRoots(name: string, args: string[]): string[] | undefined {
	const short = (letter: string) => args.some((a) => new RegExp(`^-[a-zA-Z]*${letter}`).test(a));
	const recursive = (letter: string) =>
		short(letter) || args.some((a) => /^--(dereference-)?recursive$/.test(a));
	switch (name) {
		case "find": {
			const first = args.findIndex((a) => /^[-(!]/.test(a));
			return first < 0 ? args : args.slice(0, first);
		}
		case "locate":
			return ["/"];
		case "mdfind": {
			const at = args.indexOf("-onlyin");
			return at < 0 ? ["/"] : [args[at + 1] ?? "/"];
		}
		case "du":
			return positional(args, ["-d"]);
		case "tree":
			return positional(args, ["-L", "-P", "-I", "-o"]);
		case "ls":
			return short("R") || args.includes("--recursive") ? positional(args, []) : undefined;
		case "grep":
		case "egrep":
		case "fgrep":
			if (!recursive("[rR]")) return undefined;
			return withoutPattern(
				positional(args, GREP_VALUES),
				args.some((a) => /^(-e|-f|--regexp|--file)/.test(a)),
			);
		case "rg":
		case "ag":
			return withoutPattern(
				positional(args, GREP_VALUES),
				args.some((a) => /^(-e|-f|--regexp|--file|--files$)/.test(a)),
			);
		case "fd":
		case "fdfind": {
			const searchPaths = args.flatMap((a, i) =>
				/^--(search-path|base-directory)$/.test(a) ? [args[i + 1]] : [],
			);
			return [
				...withoutPattern(positional(args, FD_VALUES), false),
				...searchPaths.filter(Boolean),
			];
		}
		default:
			return undefined;
	}
}

// Flags whose value is the next word, so it is not taken for a path.
const GREP_VALUES = [
	"-A",
	"-B",
	"-C",
	"-m",
	"-e",
	"-f",
	"-g",
	"-t",
	"-T",
	"-M",
	"--include",
	"--exclude",
	"--glob",
	"--type",
];
const FD_VALUES = [
	"-e",
	"-t",
	"-d",
	"-E",
	"-x",
	"-X",
	"-c",
	"--extension",
	"--type",
	"--exclude",
	"--max-depth",
	"--search-path",
	"--base-directory",
];

function positional(args: string[], valueFlags: string[]): string[] {
	const out: string[] = [];
	for (let i = 0; i < args.length; i++) {
		if (args[i] === "--") return [...out, ...args.slice(i + 1)];
		if (valueFlags.includes(args[i])) i++;
		else if (!args[i].startsWith("-")) out.push(args[i]);
	}
	return out;
}

/** The first positional of grep, rg, ag and fd is the pattern, unless one came with a flag. */
const withoutPattern = (words: string[], patternGiven: boolean) =>
	patternGiven ? words : words.slice(1);

/** `~` expanded, a glob cut back to the folder it starts in, symlinks resolved. */
function absolute(path: string, dir: string): string {
	const expanded = path.replace(/^(~|\$HOME|\$\{HOME\})(?=\/|$)/, home);
	const glob = expanded.search(/[*?[{]/);
	const literal = glob < 0 ? expanded : dirname(`${expanded.slice(0, glob)}x`);
	return real(resolve(dir, literal));
}

/** realpath of the nearest folder that exists, so /tmp and /private/tmp compare equal on macOS. */
function real(path: string): string {
	let head = resolve(path);
	const tail: string[] = [];
	while (!existsSync(head) && head !== dirname(head)) {
		tail.unshift(basename(head));
		head = dirname(head);
	}
	try {
		head = realpathSync(head);
	} catch {}
	return join(head, ...tail);
}

// Last, so the constants above are initialised before anything reads them.
const input = await event<Input>();
if (input) decide(input);
