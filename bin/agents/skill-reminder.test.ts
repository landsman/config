// What skill-reminder.ts would get wrong silently: a keyword missed for its
// inflection or its diacritics, a skill reminded of inside an unrelated word, or
// one reminded of again after it was loaded. A throwaway HOME with its own skills.
import { afterAll, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runHook } from "@lib/testing";

const hook = join(import.meta.dir, "skill-reminder.ts");
const home = mkdtempSync(join(tmpdir(), "skill-reminder-"));
afterAll(() => rmSync(home, { recursive: true }));

function skill(dir: string, frontmatter: string) {
	mkdirSync(dir, { recursive: true });
	writeFileSync(join(dir, "SKILL.md"), `---\n${frontmatter}\n---\n`);
}
skill(join(home, ".claude/skills/git"), "name: commit-messages\ntrigger-keywords: commit*, pull request");
skill(join(home, ".claude/skills/pg"), "name: postgres\ntrigger-keywords: postgres, index*, rešerš*");
skill(join(home, ".claude/skills/quiet"), "name: quiet\ndescription: no keywords");
skill(join(home, ".claude/skills/forge"), "name: forgejo\ntrigger-keywords: git.insuit.cz");
skill(join(home, "project/.claude/skills/local"), "name: local\ntrigger-keywords: deploy");

/** The skills the hook reminds of for this prompt. */
async function reminded(prompt: string, more: { transcript_path?: string; project?: string } = {}) {
	const answer = await runHook(hook, { prompt, transcript_path: more.transcript_path },
		{ HOME: home, CLAUDE_PROJECT_DIR: more.project });
	return [...(answer?.hookSpecificOutput.additionalContext ?? "").matchAll(/matches the (\S+) skill/g)].map((m) => m[1]);
}

test("a whole word, in any case", async () => expect(await reminded("why is Postgres slow")).toEqual(["postgres"]));
test("a prefix keyword catches an inflected form", async () =>
	expect(await reminded("napiš zprávu ke commitu")).toEqual(["commit-messages"]));
test("a multi-word keyword", async () => expect(await reminded("open a pull request")).toEqual(["commit-messages"]));
test("no partial word without *", async () => expect(await reminded("postgresql is fine")).toEqual([]));
test("no match inside a word", async () => expect(await reminded("the recommit flag")).toEqual([]));
test("a keyword with diacritics matches a prompt without", async () =>
	expect(await reminded("udelej reserse")).toEqual(["postgres"]));
test("a host in a pasted link", async () =>
	expect(await reminded("zapracuj https://git.insuit.cz/o/r/pulls/7")).toEqual(["forgejo"]));
test("an unrelated prompt is silent", async () => expect(await reminded("hello")).toEqual([]));

test("a skill loaded this session is not repeated", async () => {
	const transcript = join(home, "t.jsonl");
	writeFileSync(transcript, `${JSON.stringify({ type: "assistant", message: { content: [
		{ type: "tool_use", name: "Skill", input: { skill: "postgres" } }] } })}\n`);
	expect(await reminded("add an index", { transcript_path: transcript })).toEqual([]);
});

test("the project's own skills count", async () =>
	expect(await reminded("deploy it", { project: join(home, "project") })).toEqual(["local"]));
