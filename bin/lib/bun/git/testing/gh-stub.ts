// For the tests of the git helpers: `gh` replaced by a stub first on PATH, so a
// test reaches no forge and needs no token. The stub prints `answer` and records
// its arguments, one per line, for the test to read back.
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

export function stubGh(scratch: string, answer: string) {
	const stubs = `${scratch}/stubs`;
	const calls = `${scratch}/gh-calls`;
	mkdirSync(stubs, { recursive: true });
	writeFileSync(
		`${stubs}/gh`,
		`#!/bin/sh\nprintf '%s\\n' "$@" >> '${calls}'\nprintf '%s\\n' '${answer}'\n`,
	);
	chmodSync(`${stubs}/gh`, 0o755);
	process.env.PATH = `${stubs}:${process.env.PATH}`;
	return {
		/** Every argument gh was called with so far, one per line. */
		calls: () => (existsSync(calls) ? readFileSync(calls, "utf8") : ""),
	};
}
