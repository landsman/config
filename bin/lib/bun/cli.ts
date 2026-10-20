// The entry point of a script under bin/: `script.ts <command> [arg]`. An unknown
// command prints the script's own `// usage:` header; an error is one red line
// and exit 1, not a stack trace.
import { readFileSync } from "node:fs";
import { warn } from "@lib/term";

export async function cli(path: string, commands: Record<string, (arg?: string) => Promise<unknown>>) {
	const [cmd, arg] = process.argv.slice(2);
	const run = commands[cmd ?? ""];
	if (!run) {
		const usage = readFileSync(path, "utf8").match(/^\/\/ usage:[\s\S]*?(?=^(?!\/\/))/m)?.[0] ?? `usage: ${path} <command>`;
		process.stderr.write(usage.replace(/^\/\/ ?/gm, ""));
		process.exit(2);
	}
	try {
		await run(arg || undefined);
	} catch (e) {
		warn((e as Error).message);
		process.exit(1);
	}
}
