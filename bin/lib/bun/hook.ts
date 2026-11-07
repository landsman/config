// The two ends of a Claude Code hook, for the hook scripts under bin/agents/:
// the event as JSON on stdin, the answer as JSON on stdout.

/**
 * The event Claude Code sent, or undefined when stdin is not JSON: nothing to answer.
 *
 * Call it once, at the top of a hook script, and do nothing when it is undefined —
 * a hook that throws shows up as an error on every prompt.
 */
export async function event<T>(): Promise<T | undefined> {
	try {
		return JSON.parse(await Bun.stdin.text());
	} catch {
		return undefined;
	}
}

/**
 * Answers Claude Code, the harness, not the agent. A hook that prints nothing has no opinion.
 *
 * The harness decides who reads which field, so pick it by the reader:
 * - the agent: `permissionDecisionReason` on a `deny` (use `refuse`), `additionalContext`,
 *   or `reason` on a Stop hook's `decision: "block"`;
 * - the user: `systemMessage`, and `permissionDecisionReason` on `allow` or `ask`.
 */
export const answer = (body: object) => console.log(JSON.stringify(body));

/**
 * Refuses a PreToolUse call: the tool does not run, and the agent reads `reason` in place
 * of its output, in the same turn. Nothing is shown to the user as a question.
 *
 * Write `reason` for the agent: what was wrong and what to do instead, since it acts on
 * the text and retries. To ask the user instead, answer `permissionDecision: "ask"`.
 */
export const refuse = (reason: string) =>
	answer({
		hookSpecificOutput: {
			hookEventName: "PreToolUse",
			permissionDecision: "deny",
			permissionDecisionReason: reason,
		},
	});
