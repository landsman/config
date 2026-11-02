// Self-check for ./forbidden-names.ts: the pure halves directly, and the script
// itself in throwaway repos under a throwaway $HOME, run the way git runs it.
import { afterAll, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	EMAIL_RE,
	addedLines,
	messageLines,
	names,
	patternsFor,
	stdinLines,
	subjectOf,
	toRegExp,
} from "@bin/git/forbidden-names";

describe("toRegExp: a grep ERE read by JS", () => {
	test("word edges become \\b, so AB is a name and ABC is not", () => {
		const re = toRegExp("\\<AB\\>");
		expect(re.test("for AB today")).toBe(true);
		expect(re.test("the ABC controller")).toBe(false);
		// Without the i flag the shell's own command is not the abbreviation.
		expect(re.test('ab "$t"')).toBe(false);
	});
	test("a lower-case pattern is given the i flag by its caller", () => {
		expect(toRegExp("acme", "i").test("ACME Ltd")).toBe(true);
	});
	test("POSIX classes are expanded, not read as characters", () => {
		expect(toRegExp("[[:alnum:]]+@").test("a1@")).toBe(true);
		// JS would read this as the set [:alnum] and match a bare colon.
		expect(toRegExp("[[:alnum:]]+@").test(":@")).toBe(false);
	});
	test("a ] first in the class is a literal, as in grep", () => {
		expect(toRegExp("[]x]").test("]")).toBe(true);
	});
	test("what it cannot translate throws instead of guessing", () => {
		expect(() => toRegExp("[[:bogus:]]")).toThrow(/unknown character class/);
		expect(() => toRegExp("[[.hyphen.]]")).toThrow(/no JS equivalent/);
		expect(() => toRegExp("[[:alnum:]")).toThrow(/unterminated/);
		expect(() => toRegExp("acme\\")).toThrow(/trailing backslash/);
	});
});

describe("patternsFor: the list, by owner", () => {
	const list = [
		"# owner regex",
		"acme acme|acme-bot",
		"",
		"holding,acme shared-name",
		"padded padded  ",
		"ministry \\<AB\\>",
		"oneword",
	].join("\n");

	test("comments and blank lines are not patterns", () => {
		expect(patternsFor(list, "nobody").map((p) => p.line)).toEqual([2, 4, 5, 6, 7]);
	});
	test("the owner's own names are not forbidden in its own repos", () => {
		expect(patternsFor(list, "acme").map((p) => p.source)).not.toContain("acme|acme-bot");
	});
	test("a name listed for several owners is each owner's own", () => {
		expect(patternsFor(list, "holding").map((p) => p.source)).not.toContain("shared-name");
	});
	test("an owner whose folder only starts the same is not one of them", () => {
		expect(patternsFor(list, "acmez").map((p) => p.source)).toContain("acme|acme-bot");
	});
	test("trailing whitespace is cut: an empty pattern would match every line", () => {
		const padded = patternsFor(list, "x").find((p) => p.line === 5);
		expect(padded?.source).toBe("padded");
	});
	test("a single word is both the owner and its own pattern", () => {
		expect(patternsFor(list, "x").find((p) => p.line === 7)?.source).toBe("oneword");
		expect(patternsFor(list, "oneword").map((p) => p.line)).not.toContain(7);
	});
	test("upper case in the pattern means case-sensitive", () => {
		const abbrev = patternsFor(list, "x").find((p) => p.line === 6);
		expect(abbrev?.re.flags).toBe("");
		expect(patternsFor(list, "x").find((p) => p.line === 2)?.re.flags).toBe("i");
	});
});

describe("names: a word, not a run of letters inside one", () => {
	const of = (list: string, line: number) => {
		const pattern = patternsFor(list, "nobody").find((p) => p.line === line);
		if (!pattern) throw new Error(`no pattern on line ${line}`);
		return (text: string) => names(text, pattern);
	};
	const acme = of("acme", 1);
	const cat = of("cat", 1);
	const abbrev = of("ministry AB", 1);

	test("the name on its own, however it is punctuated around", () => {
		expect(acme("for acme today")).toBe(true);
		expect(acme("acme-bot")).toBe(true);
		expect(acme("acme.cz")).toBe(true);
		expect(acme("acme2.cz")).toBe(true);
		expect(acme("ACME Ltd")).toBe(true);
	});
	test("inside an identifier, which is where a name really leaks", () => {
		// grep's own word edges would lose both of these: `_` is a word character,
		// and camelCase has no edge at all.
		expect(acme("client_acme_token")).toBe(true);
		expect(acme("class AcmeService {")).toBe(true);
	});
	test("but not in the middle of another word", () => {
		expect(acme("acmecorp")).toBe(false);
		expect(acme("myacme")).toBe(false);
		expect(cat("concatenate the list")).toBe(false);
		expect(cat("cat_token")).toBe(true);
	});
	test("an upper-case abbreviation is not the start of a longer one", () => {
		expect(abbrev("rolled out for AB last spring")).toBe(true);
		expect(abbrev("the ABC controller")).toBe(false);
		// And the case rule still earns its place: the shell command passes.
		expect(abbrev('ab "$t" "$priv"')).toBe(false);
	});
});

describe("what gets searched", () => {
	const diff = [
		"diff --git a/f.txt b/f.txt",
		"index 0000000..1111111 100644",
		"--- a/f.txt",
		"+++ b/f.txt",
		"@@ -0,0 +4,2 @@",
		"+first added",
		"++ not a header",
		"-removed",
	].join("\n");

	test("added lines carry their file and line number", () => {
		expect(addedLines(diff)).toEqual(["f.txt:4: first added", "f.txt:5: + not a header"]);
	});
	test("a removed line is not the author's text any more", () => {
		expect(addedLines(diff).join()).not.toContain("removed");
	});
	test("git's template comments and the commit -v diff are not the message", () => {
		const raw =
			"fe: subject\n# a template comment\n# ------------------------ >8 ------------------------\n-removed acme\n";
		expect(messageLines(raw)).toEqual(["1:fe: subject", "3:"]);
	});
	test("in a PR body a leading # is a heading, so nothing is dropped", () => {
		expect(stdinLines("# Heading\nbody")).toEqual(["1:# Heading", "2:body"]);
	});
	test("the subject is the first line that is neither blank nor a comment", () => {
		expect(subjectOf("# hint\n\nfe: the subject\nbody")).toBe("fe: the subject");
	});
	test("an address in a subject is refused whatever the names list says", () => {
		expect(EMAIL_RE.test("fe: mail me@example.com")).toBe(true);
		expect(EMAIL_RE.test("fe: no address here")).toBe(false);
	});
});

describe("the script, as git runs it", () => {
	const hook = join(import.meta.dir, "forbidden-names.ts");
	// Resolved, because the script compares a realpath of the checkout against
	// $HOME: on macOS a temp dir is /var/folders/… and its real path
	// /private/var/folders/…, so an unresolved HOME would put every repo outside
	// ~/projects and leave the owner exemption untested.
	const tmp = realpathSync(mkdtempSync(join(tmpdir(), "forbidden-names-")));
	afterAll(() => rmSync(tmp, { recursive: true, force: true }));

	const env = {
		...process.env,
		HOME: tmp,
		GIT_CONFIG_GLOBAL: join(tmp, "gitconfig"),
		GIT_CONFIG_NOSYSTEM: "1",
	};
	const git = (cwd: string, ...args: string[]) => Bun.spawnSync(["git", ...args], { cwd, env });
	const run = (cwd: string, ...args: string[]) => {
		const p = Bun.spawnSync([process.execPath, hook, ...args], { cwd, env });
		return { code: p.exitCode, err: p.stderr.toString() };
	};
	const repo = (path: string) => {
		mkdirSync(path, { recursive: true });
		git(path, "init", "-q");
		return path;
	};
	const stage = (path: string, text: string) => {
		writeFileSync(join(path, "f.txt"), `${text}\n`);
		git(path, "add", "f.txt");
	};

	const names = join(tmp, "names");
	writeFileSync(names, "# owner regex\nacme acme|acme-bot\n");
	const public_ = repo(join(tmp, "projects", "landsman", "public"));

	test("no list configured: a runner has nothing to check", () => {
		stage(public_, "org=acme");
		expect(run(public_).code).toBe(0);
	});

	test("a staged name is refused, and the hit says where to edit", () => {
		git(public_, "config", "--global", "forbiddenNames.file", names);
		stage(public_, "org=ACME");
		const { code, err } = run(public_);
		expect(code).toBe(1);
		expect(err).toContain("belongs to another owner");
		expect(err).toContain("f.txt:1: org=ACME");
	});

	test("a clean diff passes", () => {
		stage(public_, "org=${ORG:?set ORG}");
		expect(run(public_).code).toBe(0);
	});

	test("the owner's own repo may name it", () => {
		const own = repo(join(tmp, "projects", "acme", "backend"));
		stage(own, "org=acme");
		expect(run(own).code).toBe(0);
	});

	test("a missing list refuses rather than passing unchecked", () => {
		git(public_, "config", "--global", "forbiddenNames.file", join(tmp, "gone"));
		stage(public_, "clean");
		const { code, err } = run(public_);
		expect(code).toBe(1);
		expect(err).toContain("refusing to commit unchecked");
	});

	test("an empty file named after it: no added line carries the path", () => {
		git(public_, "config", "--global", "forbiddenNames.file", names);
		git(public_, "rm", "-q", "--cached", "f.txt");
		writeFileSync(join(public_, "acme-deploy.sh"), "");
		git(public_, "add", "acme-deploy.sh");
		const { code, err } = run(public_);
		expect(code).toBe(1);
		expect(err).toContain("(file name)");
		git(public_, "rm", "-q", "--cached", "acme-deploy.sh");
	});

	test("a PR body on stdin, where # is a heading", () => {
		const p = Bun.spawnSync([process.execPath, hook, "-"], {
			cwd: public_,
			env,
			stdin: new Blob(["fe: a clean title\n\n# Heading\nfor acme\n"]),
		});
		expect(p.exitCode).toBe(1);
		expect(p.stderr.toString()).toContain("4:for acme");
	});

	test("git itself runs it, through the wrapper in .gitconfig", () => {
		git(public_, "config", "--global", "commit.gpgsign", "false");
		git(public_, "config", "--global", "user.email", "t@t");
		git(public_, "config", "--global", "user.name", "t");
		git(
			public_,
			"config",
			"--global",
			"hook.forbidden-names.command",
			join(import.meta.dir, "forbidden-names.sh"),
		);
		git(public_, "config", "--global", "--add", "hook.forbidden-names.event", "pre-commit");
		stage(public_, "org=acme");
		const commit = git(public_, "commit", "-qm", "fe: a clean subject");
		expect(commit.exitCode).not.toBe(0);
		expect(commit.stderr.toString()).toContain("belongs to another owner");
		git(public_, "config", "--global", "--unset-all", "hook.forbidden-names.event");
	});

	test("the repo holding the list is exempt", () => {
		const brain = repo(join(tmp, "projects", "landsman", "brain"));
		writeFileSync(join(brain, "names"), "acme acme\n");
		git(brain, "config", "--global", "forbiddenNames.file", join(brain, "names"));
		stage(brain, "acme is a client");
		expect(run(brain).code).toBe(0);
	});
});
