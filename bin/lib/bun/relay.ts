// State handed from one run of a script to the next when the runs start
// concurrently but must take turns in order: run N waits until run N-1 has
// written its state, works, and leaves its own for run N+1. One small file per
// relay, replaced whole, so a reader never sees half of one.
import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/** A relay's file under the system temp directory, private to this user. */
export function relayFile(dir: string, id: string): string {
	mkdirSync(join(tmpdir(), dir), { recursive: true, mode: 0o700 });
	return join(tmpdir(), dir, id);
}

/** The state run `turn - 1` left, waiting up to `seconds` for it; undefined when it never came. */
export async function awaitTurn<T>(file: string, turn: number, seconds: number): Promise<T | undefined> {
	const deadline = performance.now() + seconds * 1000;
	while (performance.now() < deadline) {
		try {
			const { next, state } = JSON.parse(readFileSync(file, "utf8"));
			if (next === turn) return state;
		} catch {
			// not written yet
		}
		await Bun.sleep(10);
	}
	return undefined;
}

/** Leaves `state` for run `turn + 1`. */
export function passTurn<T>(file: string, turn: number, state: T) {
	writeFileSync(`${file}.tmp`, JSON.stringify({ next: turn + 1, state }), { mode: 0o600 });
	renameSync(`${file}.tmp`, file);
}

/** Ends the relay: the last run leaves nothing behind. */
export const endRelay = (file: string) => rmSync(file, { force: true });
