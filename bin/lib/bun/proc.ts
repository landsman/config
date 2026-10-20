// Waiting on other programs, for the scripts under bin/.
import { $ } from "bun";

/** Whether a process whose command line matches the pattern (pgrep -f) is running.
 *  No -q: procps on Linux rejects it with exit 2, read here as "not running". */
export const running = async (pattern: string) =>
	(await $`pgrep -f ${pattern}`.nothrow().quiet()).exitCode === 0;

/** Checks once a second until ok() holds, at most `seconds`; says whether it did. */
export async function waitFor(ok: () => Promise<boolean>, seconds: number): Promise<boolean> {
	for (let i = 0; i < seconds; i++) {
		if (await ok()) return true;
		await Bun.sleep(1000);
	}
	return ok();
}

/** Runs fn once a second until it succeeds, at most `seconds`, retrying only the
 *  errors `again` accepts (all by default); the last error is thrown. */
export async function retry<T>(fn: () => Promise<T>, seconds: number, again = (_: Error) => true): Promise<T> {
	for (let i = 0; ; i++) {
		try {
			return await fn();
		} catch (e) {
			if (i >= seconds || !again(e as Error)) throw e;
			await Bun.sleep(1000);
		}
	}
}
