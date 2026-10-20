// The two ends of a Claude Code hook, for the hook scripts under bin/agents/:
// the event as JSON on stdin, the answer as JSON on stdout.

/** The event Claude Code sent, or undefined when stdin is not JSON: nothing to answer. */
export async function event<T>(): Promise<T | undefined> {
	try {
		return JSON.parse(await Bun.stdin.text());
	} catch {
		return undefined;
	}
}

/** Answers Claude Code. A hook that prints nothing has no opinion. */
export const answer = (body: object) => console.log(JSON.stringify(body));
