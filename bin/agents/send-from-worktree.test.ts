// What send-from-worktree.ts would get wrong silently: letting a worktree's file
// through to a card that opens nothing, or holding a file that is fine.
import { expect, test } from "bun:test";
import { join } from "node:path";
import { runHook } from "@lib/testing";

const hook = join(import.meta.dir, "send-from-worktree.ts");
const send = (...files: string[]) => runHook(hook, { tool_input: { files } });

test("a screenshot inside a worktree is refused, with the copy into the main checkout", async () => {
	const answer = await send("/repo/.claude/worktrees/fix/.claude/screenshots/shot.png");
	expect(answer?.hookSpecificOutput?.permissionDecision).toBe("deny");
	expect(answer?.hookSpecificOutput?.permissionDecisionReason).toContain(
		"'/repo/.claude/worktrees/fix/.claude/screenshots/shot.png' '/repo/.claude/screenshots/shot.png'",
	);
});

test("a screenshot in the main checkout passes", async () =>
	expect(await send("/repo/.claude/screenshots/shot.png")).toBeUndefined());

test("a file in the scratchpad passes", async () =>
	expect(await send("/private/tmp/claude-501/x/scratchpad/report.html")).toBeUndefined());

test("one worktree file among others is enough to refuse", async () =>
	expect(
		(await send("/repo/a.png", "/repo/.claude/worktrees/w/b.png"))?.hookSpecificOutput
			?.permissionDecision,
	).toBe("deny"));
