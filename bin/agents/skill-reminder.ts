#!/usr/bin/env bun
// UserPromptSubmit hook: a prompt that names a skill's topic gets a reminder to load it.
//
// A skill opts in with `trigger-keywords:` in its SKILL.md frontmatter, comma
// separated, matched case-insensitively as whole words. A trailing `*` matches
// any ending, because Czech inflects: `commit*` catches "commitu" and "commity",
// where a plain `commit` would not. Diacritics are dropped on both sides, so
// `komentář*` also catches "komentar" typed without them. Only user skills
// (~/.claude/skills, which is ~/.agents/skills) and the project's own
// .claude/skills are read; a skill already loaded this session is not reminded of
// again.
//
// Adapted from skill-keyword-reminder in github.com/fprochazka/claude-code-plugins.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { answer, event } from "@lib/hook";
import { fold, frontmatter } from "@lib/text";
import { calls } from "@lib/transcript";

type Skill = { name: string; keywords: string[] };

// A word character in any script, as Python's \w; JavaScript's own \w is ASCII only.
const WORD = String.raw`[\p{L}\p{N}_]`;

function skillFiles(): string[] {
	const dirs = [join(homedir(), ".claude/skills")];
	if (process.env.CLAUDE_PROJECT_DIR) dirs.push(join(process.env.CLAUDE_PROJECT_DIR, ".claude/skills"));
	return dirs.filter(existsSync)
		.flatMap((dir) => readdirSync(dir).map((name) => join(dir, name, "SKILL.md")))
		.filter(existsSync)
		.sort();
}

function skill(path: string): Skill {
	const meta = frontmatter(readFileSync(path, "utf8"));
	const keywords = (meta["trigger-keywords"] ?? "").split(",").map((k) => fold(k.trim())).filter(Boolean);
	return { name: meta.name || basename(dirname(path)), keywords };
}

/** Whether the prompt holds one of the keywords as a whole word, `x*` with any ending. */
function mentions(prompt: string, keywords: string[]): boolean {
	const words = keywords.map((k) => k.endsWith("*")
		? `${RegExp.escape(k.slice(0, -1))}${WORD}*`
		: `${RegExp.escape(k)}(?!${WORD})`);
	return new RegExp(`(?<!${WORD})(?:${words.join("|")})`, "iu").test(prompt);
}

const input = await event<{ prompt?: string; transcript_path?: string }>();
if (input) {
	const prompt = fold(input.prompt ?? "");
	const named = skillFiles().map(skill).filter((s) => s.keywords.length && mentions(prompt, s.keywords));
	// The transcript is the slow part, so it is read only when there is something to remind of.
	const loaded = new Set(named.length ? calls(input.transcript_path, "Skill").map((c) => String(c.skill)) : []);
	const hits = [...new Set(named.map((s) => s.name))].filter((name) => !loaded.has(name));
	if (hits.length) answer({
		hookSpecificOutput: {
			hookEventName: "UserPromptSubmit",
			// Not "IMPORTANT: load it": a keyword is a guess, and the model
			// judges relevance well once it is asked to (brain: skill-activation-hooks).
			additionalContext: hits.map((h) => `A keyword in this prompt matches the ${h} skill. Load it before acting`
				+ " if the prompt is really about what its description says; otherwise ignore this.").join("\n"),
		},
	});
}
