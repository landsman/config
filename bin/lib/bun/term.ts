// One look for the Bun scripts under bin/: what they print to a person,
// styled and indented, and nothing of it when a script reads the output. Each
// stream is asked apart, so `p=$(make -s …)` gets a bare stdout while the
// questions on stderr still look right.
//
//   import { ask, done, hint, link, live, say, warn } from "@lib/term";
//   live("Recording audio");          ● Recording audio
//   hint("Stop it with  make stop");    Stop it with  make stop       (dimmed)
//   done("Saved x.m4a", "1.2 MB");    ✓ Saved x.m4a  1.2 MB
//   warn("OBS does not answer");      ✗ OBS does not answer         (stderr)
//   await ask("Name it", "[Enter = the time]")
//                                     ? Name it [Enter = the time] ›  (stderr)

import { createInterface } from "node:readline";

type Stream = { tty: boolean; write: (s: string) => void };

export function createTerm(out: Stream, err: Stream) {
	const style = (s: Stream) => {
		const sgr = (code: string) => (t: string) => (s.tty ? `\x1b[${code}m${t}\x1b[0m` : t);
		return { bold: sgr("1"), dim: sgr("2"), red: sgr("1;31"), green: sgr("1;32"), cyan: sgr("1;36") };
	};
	const o = style(out), e = style(err);
	const line = (s: Stream, text: string) => s.write(`${s.tty ? "  " : ""}${text}\n`);

	return {
		/** Styling for text that goes to stdout. */
		o,
		/** Plain lines on stdout, indented on a terminal. */
		say: (...lines: string[]) => lines.forEach((l) => line(out, l)),
		/** Something finished: ✓ title, and a dimmed detail after it. */
		done: (title: string, detail = "") => line(out, `${o.green("✓")} ${o.bold(title)}${detail && `  ${o.dim(detail)}`}`),
		/** Something is running now: ● title. */
		live: (title: string) => line(out, `${o.red("●")} ${o.bold(title)}`),
		/** A dimmed note under the line before it. */
		hint: (text: string) => line(out, o.dim(`  ${text}`)),
		/** An error, on stderr: ✗ text. */
		warn: (text: string) => line(err, e.red(`✗ ${text}`)),
		/** A path as a terminal link (OSC 8), so ⌘-click opens it whatever the terminal makes of a bare path. */
		link: (path: string) => (out.tty ? `\x1b]8;;file://${encodeURI(path)}\x1b\\${path}\x1b]8;;\x1b\\` : path),
		/** A question on stderr, answered with one line of stdin; "" on Enter or no input. */
		async ask(question: string, hint: string): Promise<string> {
			err.write(`${err.tty ? "  " : ""}${e.cyan("?")} ${e.bold(question)} ${e.dim(hint)} ${e.cyan("›")} `);
			// readline on process.stdin, the stream untilKey reads too: two readers of
			// one stdin (Bun's `console` and process.stdin) lose each other's input.
			const rl = createInterface({ input: process.stdin });
			const answer = await new Promise<string>((resolve) => {
				rl.once("line", resolve);
				rl.once("close", () => resolve(""));
			});
			rl.close();
			return answer.trim();
		},
	};
}

/** Waits for one of `keys` on a terminal, calling tick() now and every second.
 *  Raw mode, so Ctrl+C ("\x03") arrives as a key rather than SIGINT: the
 *  signal would also reach `make`, which then ends with "*** Interrupt". */
export function untilKey(keys: string[], tick?: () => void): Promise<string> {
	tick?.();
	const timer = tick && setInterval(tick, 1000);
	process.stdin.setRawMode(true);
	process.stdin.resume();
	return new Promise((resolve) => {
		const onData = (b: Buffer) => {
			const key = b.toString();
			if (!keys.includes(key)) return;
			clearInterval(timer);
			process.stdin.off("data", onData);
			process.stdin.setRawMode(false);
			process.stdin.pause();
			resolve(key);
		};
		process.stdin.on("data", onData);
	});
}

// process.stderr.write, not console.error: Bun colours that one red on its own.
export const { o, say, done, live, hint, warn, link, ask } = createTerm(
	{ tty: !!process.stdout.isTTY, write: (s) => process.stdout.write(s) },
	{ tty: !!process.stderr.isTTY, write: (s) => process.stderr.write(s) },
);
